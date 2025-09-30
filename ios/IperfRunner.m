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
  atomic_bool _isRunning;
  NSThread *_thread;
  IperfLogBlock _onLog;
  struct iperf_test *_test;
}

// Static reference to the current runner for the C callback
static IperfRunner *s_currentRunner = nil;

// C callback for iperf JSON output
static void iperf_json_output_callback(struct iperf_test *test, char *json_string) {
  if (!json_string) return;
  
  IperfRunner *runner = s_currentRunner;
  if (runner) {
    NSString *output = [NSString stringWithUTF8String:json_string];
    // Call the log block on the main thread for thread safety
    dispatch_async(dispatch_get_main_queue(), ^{
      [runner invokeLogCallback:output];
    });
  }
}

// Helper method to invoke the log callback
- (void)invokeLogCallback:(NSString *)output {
  if (_onLog) {
    _onLog(output);
  }
}

+ (instancetype)shared {
  static IperfRunner *s; static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [IperfRunner new]; });
  return s;
}

- (void)startOnPort:(int)port json:(BOOL)json udp:(BOOL)udp onLog:(IperfLogBlock)onLog {
    if (self.isRunning) return;
  _onLog = [onLog copy];
  s_currentRunner = self;
  atomic_store(&_isRunning, true);

  _thread = [[NSThread alloc] initWithBlock:^{
    struct iperf_test *t = iperf_new_test();
    if (!t) { 
      if(self->_onLog) self->_onLog(@"iperf_new_test failed"); 
      atomic_store(&self->_isRunning, false);
      return; 
    }
    
    self->_test = t;
    iperf_defaults(t);
    iperf_set_test_role(t, 's');
    iperf_set_test_server_port(t, port);
    if (json) {
      iperf_set_test_json_output(t, 1);
      iperf_set_test_json_stream(t, 1);  // Enable JSON streaming for real-time updates
      // Set the callback to receive JSON output in real-time
      iperf_set_test_json_callback(t, iperf_json_output_callback);
    }
//    if (udp)  iperf_set_test_protocol(t, Pudp);

    // Run server loop - handle multiple clients
    while (atomic_load(&self->_isRunning)) {
      int rc = iperf_run_server(t);
      
      // Check if we should stop
      if (!atomic_load(&self->_isRunning)) break;
      
      if (rc < 0) {
        if (self->_onLog) {
          const char *err = iperf_strerror(i_errno);
          self->_onLog([NSString stringWithUTF8String: err ?: "iperf_run_server error"]);
        }
        // Most errors are fatal - stop the server
        // (binding failures, listen errors, etc)
        break;
      }
      
      // Reset for next client only if we're still running
      if (atomic_load(&self->_isRunning)) {
        iperf_reset_test(t);
      }
    }
    
    iperf_free_test(t);
    self->_test = NULL;
    atomic_store(&self->_isRunning, false);
  }];
  [_thread start];
}

- (void)stop {
    if (!self.isRunning) return;
  atomic_store(&_isRunning, false);
  
  // Wait for thread to finish with a timeout
  if (_thread && ![_thread isFinished]) {
    // Give it a moment to clean up (max 2 seconds)
    for (int i = 0; i < 20 && ![_thread isFinished]; i++) {
      [NSThread sleepForTimeInterval:0.1];
    }
  }
  
  _thread = nil; 
  _onLog = nil;
  _test = NULL;
  s_currentRunner = nil;
}

- (BOOL)isRunning { return atomic_load(&_isRunning); }

@end

