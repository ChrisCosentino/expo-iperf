//
//  IperfRunner.m
//  ExpoIperf
//
//  Created by Chris Cosentino on 2025-09-30.
//

#import "IperfRunner.h"
#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <dlfcn.h> 
#import <pthread.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

// iperf3 headers (from ios/iperf3/src)
#import "iperf_api.h"
#import "iperf.h"

// Weak-import optional iperf symbols (some builds don't export these)
extern void iperf_set_test_one_off(struct iperf_test *t, int one_off) __attribute__((weak_import));

@implementation IperfRunner {
  // State
  atomic_bool _isRunning;
  NSThread *_thread;
  dispatch_group_t _threadGroup;

  // Logging
  IperfLogBlock _onLog;

  // iperf test pointer guarded by _stateLock for race-free stop/free
  struct iperf_test *_test;   // GUARDED_BY(_stateLock)
  int _serverPort;            // last port (for fallback wake)
  NSLock *_stateLock;         // protects _test + _serverPort

  // Config
  BOOL _oneOff;               // YES = auto-exit after one client
}

// Static reference for the C JSON callback
static __weak IperfRunner *s_currentRunner = nil;

#pragma mark - iperf JSON Callback (C entrypoint)

static void iperf_json_output_callback(struct iperf_test * /*test*/, char *json_string) {
  if (!json_string) return;
  IperfRunner *runner = s_currentRunner;
  if (!runner) return;

  NSString *line = [[NSString alloc] initWithUTF8String:json_string];
  if (!line) return;

  dispatch_async(dispatch_get_main_queue(), ^{
    [runner postLog:line];
  });
}

#pragma mark - Init

+ (instancetype)shared {
  static IperfRunner *s; static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [IperfRunner new]; });
  return s;
}

- (instancetype)init {
  if ((self = [super init])) {
    atomic_store(&_isRunning, false);
    _thread = nil;
    _threadGroup = dispatch_group_create();
    _onLog = nil;
    _test = NULL;
    _serverPort = 0;
    _stateLock = [NSLock new];
    _oneOff = YES; // set NO if you want multi-client
  }
  return self;
}

- (BOOL)isRunning { return atomic_load(&_isRunning); }

#pragma mark - Public API

- (void)startOnPort:(int)port json:(BOOL)json udp:(BOOL)udp onLog:(IperfLogBlock)onLog {
  // Non-blocking stop of any previous run
  [self stop];

  // Optional: give any previous worker up to ~2s to finish (off-UI)
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    (void)dispatch_group_wait(self->_threadGroup,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
  });

  _onLog = [onLog copy];
  s_currentRunner = self;

  atomic_store(&_isRunning, true);
  @synchronized (_stateLock) {
    _serverPort = port;
  }

  dispatch_group_enter(_threadGroup);

  __weak IperfRunner *weakSelf = self;
  _thread = [[NSThread alloc] initWithBlock:^{
    @autoreleasepool {
      IperfRunner *strongSelf = weakSelf;
      if (!strongSelf) { dispatch_group_leave(self->_threadGroup); return; }

      struct iperf_test *t = iperf_new_test();
      if (!t) {
        [strongSelf postLog:@"{\"event\":\"error\",\"message\":\"iperf_new_test failed\"}"];
        atomic_store(&strongSelf->_isRunning, false);
        dispatch_group_leave(strongSelf->_threadGroup);
        return;
      }

      // Publish the test under lock so stop() can safely interrupt it.
      @synchronized (strongSelf->_stateLock) {
        strongSelf->_test = t;
        strongSelf->_serverPort = port;
      }

      iperf_defaults(t);
      iperf_set_test_role(t, 's');                        // server
      iperf_set_test_server_port(t, port);                // port
      iperf_set_test_bind_address(t, (char *)"0.0.0.0");  // IPv4 all interfaces

      if (iperf_set_test_one_off) {
        iperf_set_test_one_off(t, strongSelf->_oneOff ? 1 : 0);
      }

      if (json) {
        iperf_set_test_json_output(t, 1);
        iperf_set_test_json_stream(t, 1);
        iperf_set_test_json_callback(t, iperf_json_output_callback);
      }
      // if (udp) iperf_set_test_protocol(t, Pudp);  // wire up if needed

      // Main run loop (one-off exits after a single client)
      while (atomic_load(&strongSelf->_isRunning)) {
        int rc = iperf_run_server(t);

        if (!atomic_load(&strongSelf->_isRunning)) break;

        if (rc < 0) {
          const char *err = iperf_strerror(i_errno);
          NSString *msg = [NSString stringWithFormat:
                           @"{\"event\":\"error\",\"message\":\"%s\"}", err ?: "unknown"];
          [strongSelf postLog:msg];
          break;
        }

        if (strongSelf->_oneOff) break;

        // Prepare for next client
        iperf_reset_test(t);
        iperf_set_test_role(t, 's');
        iperf_set_test_server_port(t, port);
        iperf_set_test_bind_address(t, (char *)"0.0.0.0");
        if (json) {
          iperf_set_test_json_output(t, 1);
          iperf_set_test_json_stream(t, 1);
          iperf_set_test_json_callback(t, iperf_json_output_callback);
        }
      }

      // Protect free with the same lock stop() uses so we can’t race
      @synchronized (strongSelf->_stateLock) {
        iperf_free_test(t);
        strongSelf->_test = NULL;
      }

      atomic_store(&strongSelf->_isRunning, false);

      dispatch_async(dispatch_get_main_queue(), ^{
        strongSelf->_thread = nil;
        // keep _onLog; next start will replace it
        s_currentRunner = nil;
      });

      dispatch_group_leave(strongSelf->_threadGroup);
    }
  }];

  [_thread start];
}

- (void)stop {
  if (!self.isRunning) return;

  // Stop callbacks immediately
  atomic_store(&_isRunning, false);

  // Interrupt under lock so worker cannot free _test while we signal it
  struct iperf_test *local = NULL;
  int port = 0;
  @synchronized (_stateLock) {
    local = _test;
    port = _serverPort;

    if (local) {
      [self interruptIperf:local port:port]; // do it while holding the lock
    }
  }
}

#pragma mark - Helpers

// Post a line of log JSON to the callback on the main queue.
- (void)postLog:(NSString *)line {
  IperfLogBlock cb = _onLog; // snapshot
  if (!cb) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_onLog) self->_onLog(line);
  });
}

// Interrupt iperf gracefully; fallback wakes accept() via loopback connect.
- (void)interruptIperf:(struct iperf_test *)t port:(int)port {
  if (!t) return;

  // ✅ Dynamic lookup of iperf_got_sigint (if present in this build)
  typedef void (*got_sigint_fn_t)(struct iperf_test *);
  static got_sigint_fn_t dynamicSigint = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dynamicSigint =
      (got_sigint_fn_t)dlsym(RTLD_DEFAULT, "iperf_got_sigint");
  });

  if (dynamicSigint) {
    dynamicSigint(t);
    return;
  }

  // ✅ Fallback: mark server done and wake accept()
  t->done = 1;
  iperf_set_test_state(t, IPERF_DONE);

  if (port > 0) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s >= 0) {
      struct sockaddr_in sa; memset(&sa, 0, sizeof(sa));
      sa.sin_family = AF_INET;
      sa.sin_port = htons((uint16_t)port);
      sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      (void)connect(s, (struct sockaddr *)&sa, sizeof(sa)); // ignore result
      close(s);
    }
  }
}



@end
