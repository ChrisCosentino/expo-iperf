//
//  IperfRunner.m
//  ExpoIperf
//
//  Created by Chris Cosentino on 2025-09-30.
//

#import "IperfRunner.h"
#import "iperf_api.h"      // from ios/iperf3/src
#import "iperf.h"          // for struct iperf_test definition
#import <stdatomic.h>
#import <unistd.h>

@implementation IperfRunner {
  atomic_bool _isRunning;
  NSThread *_thread;
  IperfLogBlock _onLog;
  struct iperf_test *_test;  // Only access from worker thread
  atomic_int _listenerSocket;  // Store listener socket for safe access from main thread
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
  atomic_store(&_listenerSocket, -1);

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
    
    // Set a short idle timeout so the server checks for stop more frequently
    // This is in seconds - set to 1 second so we can stop quickly
    t->settings->idle_timeout = 1;
    
    if (json) {
      iperf_set_test_json_output(t, 1);
      iperf_set_test_json_stream(t, 1);  // Enable JSON streaming for real-time updates
      // Set the callback to receive JSON output in real-time
      iperf_set_test_json_callback(t, iperf_json_output_callback);
    }
//    if (udp)  iperf_set_test_protocol(t, Pudp);

    // Run server loop - handle multiple clients
    while (atomic_load(&self->_isRunning)) {
      // Store listener socket for safe access from main thread
      if (t->listener > -1) {
        atomic_store(&self->_listenerSocket, t->listener);
      }
      
      // Check if we should stop before calling iperf_run_server
      if (!atomic_load(&self->_isRunning)) {
        t->done = 1;
        iperf_set_test_state(t, IPERF_DONE);  // Tell iperf to stop
        if (t->listener > -1) {
          close(t->listener);
          t->listener = -1;
        }
        break;
      }
      
      int rc = iperf_run_server(t);
      
      // Store listener socket again after iperf_run_server() in case it was just created
      if (t->listener > -1) {
        atomic_store(&self->_listenerSocket, t->listener);
      }
      
      // Check if we should stop
      if (!atomic_load(&self->_isRunning)) {
        t->done = 1;
        iperf_set_test_state(t, IPERF_DONE);
        if (t->listener > -1) {
          close(t->listener);
          t->listener = -1;
        }
        break;
      }
      
      if (rc < 0) {
        // Only log errors if we didn't intentionally stop the server
        if (atomic_load(&self->_isRunning) && self->_onLog) {
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
    
    // Cleanup
    iperf_free_test(t);
    self->_test = NULL;
    atomic_store(&self->_listenerSocket, -1);
    atomic_store(&self->_isRunning, false);
    
    // Clear references on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_thread = nil;
      self->_onLog = nil;
      s_currentRunner = nil;
    });
  }];
  [_thread start];
}

- (void)stop {
    if (!self.isRunning) return;
  
  // Signal the worker thread to stop
  atomic_store(&_isRunning, false);
  
  // Shutdown the listener socket to interrupt the blocking select() call
  // shutdown() is more reliable than close() for interrupting blocking I/O
  // This is thread-safe because we're using the atomic copy of the socket descriptor
  int listener = atomic_load(&_listenerSocket);
  if (listener > -1) {
    // Shutdown both reading and writing to force select() to return
    shutdown(listener, SHUT_RDWR);
    close(listener);
    atomic_store(&_listenerSocket, -1);
  }
  
  // Let the thread clean itself up asynchronously (don't block the UI)
  // The thread will exit when it detects _isRunning is false
}

- (BOOL)isRunning { return atomic_load(&_isRunning); }

@end

