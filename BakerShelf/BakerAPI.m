

/*
 |--------------------------------------------------------------------------
 | 处理和服务器 API 请求, 获取 shelf.json, 获取 PurchasesJSON , 发送 Divice Token,
 | 基本网络请求的封装.
 |--------------------------------------------------------------------------
 |
 */

#import "BakerAPI.h"
#import "Constants.h"
#import "Utils.h"

#import "NSMutableURLRequest+WebServiceClient.h"
#import "NSURL+Extensions.h"
#import "NSString+UUID.h"

@implementation BakerAPI

#pragma mark - Singleton

+ (BakerAPI *)sharedInstance {
    static dispatch_once_t once;
    static BakerAPI *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Shelf

- (BOOL)canGetShelfJSON {
    return ([self manifestURL] != nil);
}

/**
 *  发起请求, 获取 shelf.json 里面的数据
 */
- (void)getShelfJSON:(void (^)(NSData*)) callback {

    if ([NSThread isMainThread]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [self getFromURL:[self manifestURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
            if (callback) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    callback(data);
                });
            }
        });
    } else {
        NSData *data = [self getFromURL:[self manifestURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
        if (callback) {
            callback(data);
        }
    }
}

#pragma mark - Purchases

- (BOOL)canGetPurchasesJSON {
    return ([self purchasesURL] != nil);
}

- (void)getPurchasesJSON:(void (^)(NSData*)) callback  {

    if ([self canGetPurchasesJSON]) {
        if ([NSThread isMainThread]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [self getFromURL:[self purchasesURL] cachePolicy:NSURLRequestUseProtocolCachePolicy];
                if (callback) {
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        callback(data);
                    });
                }
            });
        } else {
            NSData *data = [self getFromURL:[self purchasesURL] cachePolicy:NSURLRequestUseProtocolCachePolicy];
            if (callback) {
                callback(data);
            }
        }
    } else if (callback) {
        callback(nil);
    }
}

- (BOOL)canPostPurchaseReceipt {
    return ([self purchaseConfirmationURL] != nil);
}
- (BOOL)postPurchaseReceipt:(NSString *)receipt ofType:(NSString *)type {
    if ([self canPostPurchaseReceipt]) {
        NSDictionary *params = @{@"type": type,
                                @"receipt_data": receipt};

        return [self postParams:params toURL:[self purchaseConfirmationURL]];
    }
    return NO;
}

#pragma mark - APNS

- (BOOL)canPostAPNSToken {
    return ([self postAPNSTokenURL] != nil);
}

- (BOOL)postAPNSToken:(NSString *)apnsToken {
    
    LogBaker(@"Divice Token 获取成功, 发送给服务器记录 (as NSString) is: %@", apnsToken);
    
    if ([self canPostAPNSToken]) {
        NSDictionary *params = @{@"apns_token": apnsToken};

        return [self postParams:params toURL:[self postAPNSTokenURL]];
    }
    return NO;
}

#pragma mark - User ID

+ (BOOL)generateUUIDOnce {
    
    LogBaker(@"产生用户 UUID ");
    
    if (![self UUID]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSString uuid] forKey:@"UUID"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return YES;
    } else {
        return NO;
    }
}

+ (NSString *)UUID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"UUID"];
}

#pragma mark - Helpers

- (NSURLRequest *)requestForURL:(NSURL *)url method:(NSString *)method {
    return [self requestForURL:url parameters:@{} method:method cachePolicy:NSURLRequestUseProtocolCachePolicy];
}
- (NSURLRequest *)requestForURL:(NSURL *)url parameters:(NSDictionary *)parameters method:(NSString *)method cachePolicy:(NSURLRequestCachePolicy)cachePolicy {
    NSMutableDictionary *requestParams = [NSMutableDictionary dictionaryWithDictionary:parameters];
    requestParams[@"app_id"] = [Utils appID];
    requestParams[@"user_id"] = [BakerAPI UUID];

    #if DEBUG
        requestParams[@"environment"] = @"debug";
    #else
        [requestParams setObject:@"production" forKey:@"environment"];
    #endif

    NSURL *requestURL = [self replaceParameters:requestParams inURL:url];
    NSMutableURLRequest *request = nil;

    if ([method isEqualToString:@"GET"]) {
        NSString *queryString = [self queryStringFromParameters:requestParams];
        requestURL = [requestURL URLByAppendingQueryString:queryString];
        request = [NSURLRequest requestWithURL:requestURL cachePolicy:cachePolicy timeoutInterval:REQUEST_TIMEOUT];
    } else if ([method isEqualToString:@"POST"]) {
        request = [[NSMutableURLRequest alloc] initWithURL:requestURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:REQUEST_TIMEOUT];
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setFormPostParameters:requestParams];
    }

    return request;
}

- (BOOL)postParams:(NSDictionary *)params toURL:(NSURL *)url {
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSURLRequest *request = [self requestForURL:url parameters:params method:@"POST" cachePolicy:NSURLRequestUseProtocolCachePolicy];

    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (error) {
        LogBaker(@"[ERROR] Failed POST request to %@: %@", [request URL], [error localizedDescription]);
        return NO;
    } else if ([response statusCode] == 200) {
        return YES;
    } else {
        LogBaker(@"[ERROR] Failed POST request to %@: response was %d %@",
              [request URL],
              [response statusCode],
              [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]]);
        return NO;
    }
}

/**
 *  对 NSURLRequest 的封装, 发起 GET 请求
 *
 *  @param url         请求的链接地址
 *  @param cachePolicy 缓存策略
 *
 *  @return NSData | nil
 */
- (NSData *)getFromURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)cachePolicy {
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSURLRequest *request = [self requestForURL:url parameters:@{} method:@"GET" cachePolicy:cachePolicy];

    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (error) {
        LogBaker(@"[ERROR] Failed GET request to %@: %@", [request URL], [error localizedDescription]);
        return nil;
    } else if ([response statusCode] == 200) {
        return data;
    } else {
        LogBaker(@"[ERROR] Failed GET request to %@: response was %d %@",
              [request URL],
              [response statusCode],
              [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]]);
        return nil;
    }
}

- (NSURL *)replaceParameters:(NSMutableDictionary *)parameters inURL:(NSURL *)url {
    __block NSMutableString *urlString = [NSMutableString stringWithString:[url absoluteString]];
    NSDictionary *allParameters = [NSDictionary dictionaryWithDictionary:parameters];
    [allParameters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *keyToReplace = [@":" stringByAppendingString:key];
        NSRange range = [urlString rangeOfString:keyToReplace options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            [urlString replaceCharactersInRange:range withString:obj];
            [parameters removeObjectForKey:key];
        }
    }];
    return [NSURL URLWithString:urlString];
}

- (NSString *)queryStringFromParameters:(NSDictionary *)parameters {
    __block NSMutableString *queryString = [NSMutableString stringWithString:@""];
    if ([parameters count] > 0) {
        [parameters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSString *queryParameter = [NSString stringWithFormat:@"%@=%@&", key, obj];
            [queryString appendString:queryParameter];
        }];
        // Remove the last "&"
        [queryString deleteCharactersInRange:NSMakeRange([queryString length] - 1, 1)];
    }
    return queryString;
}

- (NSURL *)manifestURL {
    if ([NEWSSTAND_MANIFEST_URL length] > 0) {
        return [NSURL URLWithString:NEWSSTAND_MANIFEST_URL];
    }
    return nil;
}
- (NSURL *)purchasesURL {
    if ([PURCHASES_URL length] > 0) {
        return [NSURL URLWithString:PURCHASES_URL];
    }
    return nil;
}
- (NSURL *)purchaseConfirmationURL {
    if ([PURCHASE_CONFIRMATION_URL length] > 0) {
        return [NSURL URLWithString:PURCHASE_CONFIRMATION_URL];
    }
    return nil;
}
- (NSURL *)postAPNSTokenURL {
    if ([POST_APNS_TOKEN_URL length] > 0) {
        return [NSURL URLWithString:POST_APNS_TOKEN_URL];
    }
    return nil;
}

@end
