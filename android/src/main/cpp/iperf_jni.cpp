#include <jni.h>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include <atomic>
#include <mutex>
#include <dlfcn.h>
#include "iperf3/src/iperf_api.h"
#include "iperf3/src/iperf.h"

// Disable fdsan for the entire process on Android Q+
static void disable_fdsan() {
    // Try to find and call android_fdsan_set_error_level_ptr dynamically
    void* libc = dlopen("libc.so", RTLD_NOW);
    if (libc) {
        typedef int (*set_error_level_func)(int);
        auto set_fdsan = (set_error_level_func)dlsym(libc, "android_fdsan_set_error_level");
        if (set_fdsan) {
            // 0 = ANDROID_FDSAN_ERROR_LEVEL_DISABLED
            set_fdsan(0);
        }
        dlclose(libc);
    }
}

// Global state
static std::atomic<bool> g_isRunning(false);
static pthread_t g_thread;
static struct iperf_test *g_test = nullptr;
static JavaVM *g_jvm = nullptr;
static jobject g_callbackObject = nullptr;
static std::mutex g_callbackMutex;
static std::once_flag g_fdsan_init;

// Forward declarations
void iperf_json_output_callback(struct iperf_test *test, char *json_string);
void* iperf_thread_func(void* arg);

// Struct to pass data to thread
struct ThreadData {
    int port;
    bool json;
    bool udp;
};

// Callback from iperf C library
void iperf_json_output_callback(struct iperf_test *test, char *json_string) {
    if (!json_string || !g_jvm) return;

    // Lock to prevent callback deletion during execution
    std::lock_guard<std::mutex> lock(g_callbackMutex);
    
    if (!g_callbackObject || !g_isRunning) return;

    JNIEnv *jenv;
    bool needDetach = false;

    // Get JNI environment
    int getEnvStat = g_jvm->GetEnv((void**)&jenv, JNI_VERSION_1_6);
    if (getEnvStat == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&jenv, nullptr) != 0) {
            return;
        }
        needDetach = true;
    }

    // Call Java callback method
    jclass cls = jenv->GetObjectClass(g_callbackObject);
    if (cls != nullptr) {
        jmethodID mid = jenv->GetMethodID(cls, "onLog", "(Ljava/lang/String;)V");
        
        if (mid != nullptr) {
            jstring jstr = jenv->NewStringUTF(json_string);
            if (jstr != nullptr) {
                jenv->CallVoidMethod(g_callbackObject, mid, jstr);
                jenv->DeleteLocalRef(jstr);
            }
        }
        jenv->DeleteLocalRef(cls);
    }

    if (needDetach) {
        g_jvm->DetachCurrentThread();
    }
}

// Thread function
void* iperf_thread_func(void* arg) {
    ThreadData *data = (ThreadData*)arg;

    // Disable fdsan once
    std::call_once(g_fdsan_init, disable_fdsan);

    struct iperf_test *t = iperf_new_test();
    if (!t) {
        g_isRunning = false;
        delete data;
        return nullptr;
    }

    g_test = t;
    iperf_defaults(t);
    iperf_set_test_role(t, 's');
    iperf_set_test_server_port(t, data->port);

    // Set idle timeout for responsive stopping
    t->settings->idle_timeout = 1;

    if (data->json) {
        iperf_set_test_json_output(t, 1);
        iperf_set_test_json_stream(t, 1);
        iperf_set_test_json_callback(t, iperf_json_output_callback);
    }

    // Run server loop
    while (g_isRunning) {
        int rc = iperf_run_server(t);

        // Check if we should stop BEFORE resetting
        if (!g_isRunning) {
            break;
        }

        // If there was an error, stop
        if (rc < 0) {
            break;
        }

        // Only reset if we're continuing - this prepares for the next client
        iperf_reset_test(t);
    }

    // Cleanup - iperf_free_test will handle closing all sockets
    g_isRunning = false;
    iperf_free_test(t);
    g_test = nullptr;

    delete data;
    return nullptr;
}

extern "C" {

// JNI_OnLoad - called when library is loaded
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    // Disable fdsan immediately when library loads
    disable_fdsan();
    return JNI_VERSION_1_6;
}

// Start iperf server
JNIEXPORT void JNICALL
Java_expo_modules_iperf_IperfRunner_nativeStart(
        JNIEnv* jenv,
        jobject thiz,
        jint port,
        jboolean json,
        jboolean udp,
        jobject callback) {

    if (g_isRunning) return;

    // Lock for callback setup
    std::lock_guard<std::mutex> lock(g_callbackMutex);

    // Store callback object as global reference
    if (g_callbackObject) {
        jenv->DeleteGlobalRef(g_callbackObject);
    }
    g_callbackObject = jenv->NewGlobalRef(callback);

    g_isRunning = true;

    // Create thread data
    ThreadData *data = new ThreadData();
    data->port = port;
    data->json = json;
    data->udp = udp;

    // Start thread
    pthread_create(&g_thread, nullptr, iperf_thread_func, data);
}

// Stop iperf server
JNIEXPORT void JNICALL
Java_expo_modules_iperf_IperfRunner_nativeStop(
        JNIEnv* jenv,
        jobject thiz) {

    if (!g_isRunning) return;

    // Signal the thread to stop
    g_isRunning = false;

    // Signal iperf to terminate by setting state
    if (g_test) {
        g_test->done = 1;
        iperf_set_test_state(g_test, IPERF_DONE);
    }

    // Wait for thread to finish - it will clean up everything
    pthread_join(g_thread, nullptr);

    // Lock before cleaning up callback
    std::lock_guard<std::mutex> lock(g_callbackMutex);

    // Cleanup callback
    if (g_callbackObject) {
        jenv->DeleteGlobalRef(g_callbackObject);
        g_callbackObject = nullptr;
    }
}

// Check if running
JNIEXPORT jboolean JNICALL
Java_expo_modules_iperf_IperfRunner_nativeIsRunning(
        JNIEnv* jenv,
        jobject thiz) {
    return g_isRunning;
}

} // extern "C"