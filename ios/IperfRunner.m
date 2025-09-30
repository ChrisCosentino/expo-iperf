//
//  IperfRunner.m
//  ExpoIperf
//
//  Created by Chris Cosentino on 2025-09-30.
//

#import "IperfRunner.h"
#import "iperf_api.h"      // from ios/iperf3/src
#import <stdatomic.h>

@implementation IperfRunner {
  atomic_bool _running;
  NSThread *_thread;
  IperfLogBlock _onLog;
}

+ (instancetype)shared {
  static IperfRunner *s; static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [IperfRunner new]; });
  return s;
}

- (void)startOnPort:(int)port json:(BOOL)json udp:(BOOL)udp onLog:(IperfLogBlock)onLog {
  if (self.running) return;
  _onLog = [onLog copy];
  atomic_store(&_running, true);

  _thread = [[NSThread alloc] initWithBlock:^{
    struct iperf_test *t = iperf_new_test();
    if (!t) { if(self->_onLog) self->_onLog(@"iperf_new_test failed"); return; }
    iperf_defaults(t);
    iperf_set_test_role(t, 's');
    iperf_set_test_server_port(t, port);
    if (json) iperf_set_test_json_output(t, 1);
//    if (udp)  iperf_set_test_protocol(t, Pudp);

    while (atomic_load(&self->_running)) {
      int rc = iperf_run_server(t);            // serves ONE client
      if (rc < 0 && self->_onLog) {
        const char *err = iperf_strerror(i_errno);
        self->_onLog([NSString stringWithUTF8String: err ?: "iperf_run_server error"]);
      }
      iperf_reset_test(t);                      // ready for the next client
    }
    iperf_free_test(t);
  }];
  [_thread start];
}

- (void)stop {
  if (!self.running) return;
  atomic_store(&_running, false);
  _thread = nil; _onLog = nil;
}

- (BOOL)isRunning { return atomic_load(&_running); }

@end

