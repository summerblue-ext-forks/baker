

/*
 |--------------------------------------------------------------------------
 | 处理和服务器 API 请求, 获取 shelf.json, 获取 PurchasesJSON , 发送 Divice Token,
 | 基本网络请求的封装.
 |--------------------------------------------------------------------------
 |
 */

#import <Foundation/Foundation.h>

@interface BakerAPI : NSObject

#pragma mark - Singleton

+ (BakerAPI *)sharedInstance;

#pragma mark - Shelf

- (BOOL)canGetShelfJSON;
- (void)getShelfJSON:(void (^)(NSData*)) callback ;

#pragma mark - Purchases

- (BOOL)canGetPurchasesJSON;
- (void)getPurchasesJSON:(void (^)(NSData*)) callback ;

- (BOOL)canPostPurchaseReceipt;
- (BOOL)postPurchaseReceipt:(NSString *)receipt ofType:(NSString *)type;

#pragma mark - APNS

- (BOOL)canPostAPNSToken;
- (BOOL)postAPNSToken:(NSString *)apnsToken;

#pragma mark - User ID

+ (BOOL)generateUUIDOnce;
+ (NSString *)UUID;

#pragma mark - Helpers

- (NSURLRequest *)requestForURL:(NSURL *)url method:(NSString *)method;
- (NSURLRequest *)requestForURL:(NSURL *)url parameters:(NSDictionary *)parameters method:(NSString *)method cachePolicy:(NSURLRequestCachePolicy)cachePolicy;

@end
