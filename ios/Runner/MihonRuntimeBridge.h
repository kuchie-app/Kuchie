#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MihonRuntimeBridge : NSObject
+ (void)startOnPort:(NSInteger)port
              token:(NSString *)token
         completion:(void (^)(NSInteger, NSError * _Nullable))completion
    NS_SWIFT_NAME(start(onPort:token:completion:));
+ (void)stopWithCompletion:(void (^)(NSError * _Nullable))completion
    NS_SWIFT_NAME(stop(completion:));
@end

NS_ASSUME_NONNULL_END
