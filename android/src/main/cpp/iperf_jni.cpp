#include <jni.h>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include <atomic>
#include <mutex>
#include <dlfcn.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>

#include "iperf3/src/iperf_api.h"
#include "iperf3/src/iperf.h"

// ========= FDSAN (Android Q+) =================================================

static void disable_fdsan_once() {
    void* libc = dlopen("libc.so", RTLD_NOW);
    if (libc) {
        typedef int (*set_error_level_func)(int);
        auto set_fdsan = (set_error_level_func)dlsym(libc, "android_fdsan_set_error_level");
        if (set_fdsan) set_fdsan(0);
        dlclose(libc);
    }
}

// ========= Global state =======================================================

static std::atomic<bool> g_isRunning(false);
static pthread_t g_thread{};
static JavaVM *g_jvm = nullptr;

static std::mutex g_callbackMutex;     // guards g_callbackObject only
static jobject g_callbackObject = nullptr;

static std::mutex g_stateMutex;        // guards lifecycle: g_test/g_threadStarted/g_threadValid/g_server_port
static struct iperf_test *g_test = nullptr;   // guarded by g_stateMutex
static bool g_threadStarted = false;          // guarded by g_stateMutex
static bool g_threadValid = false;            // guarded by g_stateMutex (true if pthread_create succeeded and not yet joined)
static int  g_server_port = 0;                // guarded by g_stateMutex

static std::once_flag g_fdsan_init;

// ========= Weak iperf symbols (optional in some builds) ======================

extern "C" {
__attribute__((weak)) void iperf_got_sigint(struct iperf_test *test);
__attribute__((weak)) void iperf_set_test_one_off(struct iperf_test *t, int one_off);
}

// ========= Helpers ============================================================

static bool get_jni_env(JNIEnv **out_env, bool *out_detached) {
    *out_env = nullptr;
    *out_detached = false;
    if (!g_jvm) return false;

    JNIEnv *env = nullptr;
    const jint stat = g_jvm->GetEnv((void **)&env, JNI_VERSION_1_6);
    if (stat == JNI_OK) { *out_env = env; return true; }
    if (stat == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != 0) return false;
        *out_env = env; *out_detached = true; return true;
    }
    return false;
}

static void release_jni_env(bool detached) {
    if (detached && g_jvm) g_jvm->DetachCurrentThread();
}

static jobject acquire_callback_local(JNIEnv* env) {
    std::lock_guard<std::mutex> lock(g_callbackMutex);
    if (!g_callbackObject || !g_isRunning.load()) return nullptr;
    return env->NewLocalRef(g_callbackObject);
}

static void release_callback_local(JNIEnv* env, jobject cb) {
    if (cb) env->DeleteLocalRef(cb);
}

static void send_log_line(const char* text) {
    if (!text || !g_jvm) return;

    JNIEnv *env = nullptr;
    bool detached = false;
    if (!get_jni_env(&env, &detached)) return;

    jobject cb = acquire_callback_local(env);
    if (cb) {
        jclass cls = env->GetObjectClass(cb);
        if (cls) {
            jmethodID mid = env->GetMethodID(cls, "onLog", "(Ljava/lang/String;)V");
            if (mid) {
                jstring jstr = env->NewStringUTF(text);
                if (jstr) {
                    env->CallVoidMethod(cb, mid, jstr);
                    if (env->ExceptionCheck()) env->ExceptionClear();
                    env->DeleteLocalRef(jstr);
                }
            }
            env->DeleteLocalRef(cls);
        }
        release_callback_local(env, cb);
    }

    release_jni_env(detached);
}

// Safely interrupt a running iperf server even if iperf_got_sigint is missing.
// We *never* close iperf's fds here; iperf owns them. We only wake accept().
static void safe_interrupt_iperf(struct iperf_test* t, int server_port) {
    if (!t) return;

    if (iperf_got_sigint) {
        iperf_got_sigint(t);  // best path: mirrors Ctrl-C in iperf
        return;
    }

    // Fallback: mark done + set state so the loop will exit once accept() returns.
    t->done = 1;
    iperf_set_test_state(t, IPERF_DONE);

    // Best-effort nudge on listener (often a no-op on listening sockets).
    if (t->listener >= 0) {
        shutdown(t->listener, SHUT_RDWR);
    }

    // Deterministic wake: connect to the server port on loopback to unblock accept().
    if (server_port > 0) {
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s >= 0) {
            struct sockaddr_in sa{};
            sa.sin_family = AF_INET;
            sa.sin_port = htons((uint16_t)server_port);
            sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // 127.0.0.1
            (void)connect(s, (struct sockaddr*)&sa, sizeof(sa)); // ignore result
            close(s);
        }
    }
}

// ========= iperf JSON callback ===============================================

static void iperf_json_output_callback(struct iperf_test * /*test*/, char *json_string) {
    if (!json_string || !g_jvm) return;

    JNIEnv *env = nullptr;
    bool detached = false;
    if (!get_jni_env(&env, &detached)) return;

    jobject cb = acquire_callback_local(env);
    if (cb) {
        jclass cls = env->GetObjectClass(cb);
        if (cls) {
            jmethodID mid = env->GetMethodID(cls, "onLog", "(Ljava/lang/String;)V");
            if (mid) {
                jstring jstr = env->NewStringUTF(json_string);
                if (jstr) {
                    env->CallVoidMethod(cb, mid, jstr);
                    if (env->ExceptionCheck()) env->ExceptionClear();
                    env->DeleteLocalRef(jstr);
                }
            }
            env->DeleteLocalRef(cls);
        }
        release_callback_local(env, cb);
    }

    release_jni_env(detached);
}

// ========= Thread data / worker ==============================================

struct ThreadData {
    int  port;
    bool json;
    bool udp;
    bool oneOff;
};

static void* iperf_thread_func(void* arg) {
    std::call_once(g_fdsan_init, disable_fdsan_once);

    ThreadData *data = static_cast<ThreadData*>(arg);

    struct iperf_test *t = iperf_new_test();
    if (!t) {
        send_log_line("{\"event\":\"error\",\"message\":\"iperf_new_test failed\"}");
        g_isRunning = false;

        // Clear state under lock and mark thread not started/valid
        {
            std::lock_guard<std::mutex> lk(g_stateMutex);
            g_test = nullptr;
            g_threadStarted = false;
            g_threadValid = false;
            // g_server_port left as last known (harmless)
        }
        delete data;
        return nullptr;
    }

    // Publish state under lock
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        g_test = t;
        g_server_port = data->port;
        g_threadStarted = true;
        // g_threadValid was set by nativeStart immediately after pthread_create
    }

    iperf_defaults(t);
    iperf_set_test_role(t, 's');
    iperf_set_test_server_port(t, data->port);
    iperf_set_test_bind_address(t, const_cast<char*>("0.0.0.0"));

    if (iperf_set_test_one_off) {
        iperf_set_test_one_off(t, data->oneOff ? 1 : 0);
    }

    if (data->json) {
        iperf_set_test_json_output(t, 1);
        iperf_set_test_json_stream(t, 1);
        iperf_set_test_json_callback(t, iperf_json_output_callback);
    }

    while (g_isRunning.load()) {
        const int rc = iperf_run_server(t);

        if (!g_isRunning.load()) break;

        if (rc < 0) {
            const char* err = iperf_strerror(i_errno);
            std::string msg = std::string("{\"event\":\"error\",\"message\":\"") +
                              (err ? err : "unknown") + "\"}";
            send_log_line(msg.c_str());
            break;
        }

        if (data->oneOff) break;

        // Prepare for next client
        iperf_reset_test(t);
        iperf_set_test_role(t, 's');
        iperf_set_test_server_port(t, data->port);
        iperf_set_test_bind_address(t, const_cast<char*>("0.0.0.0"));
        if (data->json) {
            iperf_set_test_json_output(t, 1);
            iperf_set_test_json_stream(t, 1);
            iperf_set_test_json_callback(t, iperf_json_output_callback);
        }
    }

    g_isRunning = false;

    // IMPORTANT: take the state lock BEFORE freeing test so stop() can’t
    // snapshot and use the pointer while we free it.
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        // Free while holding lock so stop() cannot race with safe_interrupt_iperf
        iperf_free_test(t);
        g_test = nullptr;
        g_threadStarted = false;
        // g_threadValid remains true until the joiner resets it (in stop or start)
    }

    delete data;
    return nullptr;
}

// ========= JNI exports ========================================================

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    g_jvm = vm;
    disable_fdsan_once();
    return JNI_VERSION_1_6;
}

static void stop_if_running_and_join(JNIEnv* env) {
    // Fast path: if nothing is running and no thread handle, just ensure callback is cleared
    bool threadValidSnapshot = false;
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        threadValidSnapshot = g_threadValid;
    }
    if (!g_isRunning.load() && !threadValidSnapshot) {
        std::lock_guard<std::mutex> lock(g_callbackMutex);
        if (g_callbackObject) {
            env->DeleteGlobalRef(g_callbackObject);
            g_callbackObject = nullptr;
        }
        return;
    }

    // Stop callbacks immediately
    g_isRunning.store(false);

    // Snapshot pointer & port and INTERRUPT while holding the state lock so the worker
    // cannot free the test underneath us (worker also takes this lock before free).
    struct iperf_test* local_test = nullptr;
    int local_port = 0;
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        local_test = g_test;
        local_port = g_server_port;

        if (local_test) {
            // Interrupt while holding lock to avoid use-after-free
            safe_interrupt_iperf(local_test, local_port);
        }
    } // release lock BEFORE join

    // Join the worker if a thread handle exists (regardless of g_threadStarted snapshot).
    // This handles races between pthread_create and flag writes.
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        threadValidSnapshot = g_threadValid;
    }
    if (threadValidSnapshot) {
        void* retval = nullptr;
        pthread_join(g_thread, &retval);
        // Mark handle no longer valid
        std::lock_guard<std::mutex> lk(g_stateMutex);
        g_threadValid = false;
    }

    // Now it's safe to drop the global callback (no worker thread alive).
    std::lock_guard<std::mutex> lock(g_callbackMutex);
    if (g_callbackObject) {
        env->DeleteGlobalRef(g_callbackObject);
        g_callbackObject = nullptr;
    }
}

JNIEXPORT void JNICALL
Java_expo_modules_iperf_IperfRunner_nativeStart(
        JNIEnv* env,
        jobject /*thiz*/,
        jint port,
        jboolean json,
        jboolean udp,
        jobject callback) {

    // Ensure previous instance is fully stopped
    stop_if_running_and_join(env);

    // Install/replace global callback ref
    {
        std::lock_guard<std::mutex> lock(g_callbackMutex);
        if (g_callbackObject) {
            env->DeleteGlobalRef(g_callbackObject);
            g_callbackObject = nullptr;
        }
        g_callbackObject = env->NewGlobalRef(callback);
    }

    auto *data = new ThreadData();
    data->port   = static_cast<int>(port);
    data->json   = json == JNI_TRUE;
    data->udp    = udp == JNI_TRUE;
    data->oneOff = false; // recommended default

    g_isRunning.store(true);

    const int err = pthread_create(&g_thread, nullptr, iperf_thread_func, data);
    if (err != 0) {
        g_isRunning.store(false);
        {
            std::lock_guard<std::mutex> lock(g_callbackMutex);
            if (g_callbackObject) {
                env->DeleteGlobalRef(g_callbackObject);
                g_callbackObject = nullptr;
            }
        }
        delete data;
        std::string msg = std::string("{\"event\":\"error\",\"message\":\"pthread_create failed: ") +
                          std::to_string(err) + "\"}";
        send_log_line(msg.c_str());
        return;
    }

    // Mark the thread handle valid immediately after successful create.
    {
        std::lock_guard<std::mutex> lk(g_stateMutex);
        g_threadValid = true;
        g_server_port = static_cast<int>(port);
        // g_threadStarted is set in the worker after iperf_new_test succeeds
    }
}

JNIEXPORT void JNICALL
Java_expo_modules_iperf_IperfRunner_nativeStop(
        JNIEnv* env,
        jobject /*thiz*/) {
    stop_if_running_and_join(env);
}

JNIEXPORT jboolean JNICALL
Java_expo_modules_iperf_IperfRunner_nativeIsRunning(
        JNIEnv* /*env*/,
        jobject /*thiz*/) {
    return g_isRunning.load() ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"