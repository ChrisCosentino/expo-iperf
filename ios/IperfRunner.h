//
//  Header.h
//  ExpoIperf
//
//  Created by Chris Cosentino on 2025-09-30.
//

//#ifndef Header_h
//#define Header_h
//
//
//#endif /* Header_h */


#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef void (^IperfLogBlock)(NSString *line);

@interface IperfRunner : NSObject
+ (instancetype)shared;
- (void)startOnPort:(int)port json:(BOOL)json udp:(BOOL)udp onLog:(IperfLogBlock)onLog;
- (void)stop;
//@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) BOOL isRunning;
@end

NS_ASSUME_NONNULL_END
