

/*
 |--------------------------------------------------------------------------
 | 内购买管理器.
 | 用于处理当前用户杂志购买的操作, 显示杂志是否已购买, 用户购买过的杂志...
 |--------------------------------------------------------------------------
 |
 */


#import "PurchasesManager.h"
#import "BakerAPI.h"

#import "NSData+Base64.h"
#import "NSMutableURLRequest+WebServiceClient.h"
#import "Utils.h"
#import "NSURL+Extensions.h"

@implementation PurchasesManager

@synthesize products;
@synthesize subscribed;

-(id)init {
    self = [super init];

    if (self) {
        self.products = [[NSMutableDictionary alloc] init];
        self.subscribed = NO;

        _purchases = [[NSMutableDictionary alloc] init];

        _numberFormatter = [[NSNumberFormatter alloc] init];
        [_numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
        [_numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];

        _enableProductRequestFailureNotifications = YES;
    }

    return self;
}

#pragma mark - Singleton

+ (PurchasesManager *)sharedInstance {
    static dispatch_once_t once;
    static PurchasesManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Purchased flag

- (BOOL)isMarkedAsPurchased:(NSString *)productID {
    return [[NSUserDefaults standardUserDefaults] boolForKey:productID];
}

- (void)markAsPurchased:(NSString *)productID {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:productID];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Prices

- (void)retrievePricesFor:(NSSet *)productIDs {
    [self retrievePricesFor:productIDs andEnableFailureNotifications:YES];
}
- (void)retrievePricesFor:(NSSet *)productIDs andEnableFailureNotifications:(BOOL)enable {
    if ([productIDs count] > 0) {
        _enableProductRequestFailureNotifications = enable;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:productIDs];
            productsRequest.delegate = self;
            [productsRequest start];
        });
    }
}

- (void)retrievePriceFor:(NSString *)productID {
    [self retrievePriceFor:productID andEnableFailureNotification:YES];
}
- (void)retrievePriceFor:(NSString *)productID andEnableFailureNotification:(BOOL)enable {
    NSSet *productIDs = [NSSet setWithObject:productID];
    [self retrievePricesFor:productIDs andEnableFailureNotifications:enable];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    [self logProducts:response.products];

    for (NSString *productID in response.invalidProductIdentifiers) {
        LogBaker(@"Invalid product identifier: %@", productID);
    }

    NSMutableSet *ids = [NSMutableSet setWithCapacity:response.products.count];
    for (SKProduct *skProduct in response.products) {
        (self.products)[skProduct.productIdentifier] = skProduct;
        [ids addObject:skProduct.productIdentifier];
    }

    NSDictionary *userInfo = @{@"ids": ids};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_products_retrieved" object:self userInfo:userInfo];

}

- (void)logProducts:(NSArray *)skProducts {
    LogBaker(@"Received %d products from App Store", [skProducts count]);
    for (SKProduct *skProduct in skProducts) {
        LogBaker(@"- %@", skProduct.productIdentifier);
    }
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    LogBaker(@"App Store request failure: %@", error);

    if (_enableProductRequestFailureNotifications) {
        NSDictionary *userInfo = @{@"error": error};
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_products_request_failed" object:self userInfo:userInfo];
    }

}

- (NSString *)priceFor:(NSString *)productID {
    SKProduct *product = products[productID];
    if (product) {
        [_numberFormatter setLocale:product.priceLocale];
        return [_numberFormatter stringFromNumber:product.price];
    }
    return nil;
}

#pragma mark - Purchases

- (BOOL)purchase:(NSString *)productID {
    SKProduct *product = [self productFor:productID];
    if (product) {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];

        return YES;
    } else {
        LogBaker(@"Trying to buy unavailable product %@", productID);

        return NO;
    }
}

- (BOOL)finishTransaction:(SKPaymentTransaction *)transaction {
    if ([self recordTransaction:transaction]) {
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)recordTransaction:(SKPaymentTransaction *)transaction {
    [[NSUserDefaults standardUserDefaults] setObject:transaction.transactionIdentifier forKey:@"receipt"];

    BakerAPI *api = [BakerAPI sharedInstance];
    if ([api canPostPurchaseReceipt]) {
        NSString *receipt = [transaction.transactionReceipt base64EncodedString];
        NSString *type = [self transactionType:transaction];

        return [api postPurchaseReceipt:receipt ofType:type];
    }

    return YES;
}

- (NSString *)transactionType:(SKPaymentTransaction *)transaction {
    NSString *productID = transaction.payment.productIdentifier;
    if ([productID isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID]) {
        return @"free-subscription";
    } else if ([@[] containsObject:productID]) {
        return @"auto-renewable-subscription";
    } else {
        return @"issue";
    }
}

/**
 *
 */
- (void)retrievePurchasesFor:(NSSet *)productIDs withCallback:(void (^)(NSDictionary*))callback {
    BakerAPI *api = [BakerAPI sharedInstance];

    /**
     *  获取用户购买过的 issues 列表, 以下是个例子:
     
     {
         "issues": ["com.example.MyBook.jan2013", "com.example.MyBook.feb2013", "com.example.MyBook.mar2013"],
         "subscribed": false
     }
     
     * issues 是购买过的, 属于用户的杂志, subscribed 当前是否订阅杂志
     */
    if ([api canGetPurchasesJSON])
    {
        LogBaker(@"获取 PurchasesJSON ");
        
        [api getPurchasesJSON:^(NSData* jsonResponse) {
            if (jsonResponse) {
                NSError* error = nil;
                NSDictionary *purchasesResponse = [NSJSONSerialization JSONObjectWithData:jsonResponse
                                                                                  options:0
                                                                                    error:&error];
                // TODO: handle error, 处理 json 解析的错误
                
                if (purchasesResponse)
                {
                    NSArray *purchasedIssues = purchasesResponse[@"issues"];
                    
                    // 设置 是否是订阅用户 的选项
                    self.subscribed = [purchasesResponse[@"subscribed"] boolValue];
                    
                    // 所有杂志列表, 过滤出用户购买过的, 注意, 这么做是为了跟 shelf.json 里面的数据同步 (杂志列表的增加修改)
                    [productIDs enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                        _purchases[obj] = @([purchasedIssues containsObject:obj]);
                    }];
                }
                else
                {
                    LogAllTheTime(@"ERROR: 无法解析 purchasesResponse JSON 数据 %@", jsonResponse);
                }
            }

            // 回调函数, 并把购买过的数组传递回去
            if (callback) {
                callback([NSDictionary dictionaryWithDictionary:_purchases]);
            }
        }];
    }
    else if (callback)
    {
        LogBaker(@"未设置 PURCHASES_URL 常量, 等于不开启 In App Purches 功能, 不需要获取 Purchases JSON ");
        callback(nil);
    }
}

- (BOOL)isPurchased:(NSString *)productID {
    id purchased = _purchases[productID];
    if (purchased) {
        return [purchased boolValue];
    } else {
        return [self isMarkedAsPurchased:productID];
    }
}

#pragma mark - Payment queue

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    [self logTransactions:transactions];

    BOOL isRestoring = NO;
    for(SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                // Nothing to do at the moment
                break;
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
            case SKPaymentTransactionStateRestored:
                isRestoring = YES;
                [self restoreTransaction:transaction];
                break;
            default:
                break;
        }
    }

    if (isRestoring) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_multiple_restores" object:self userInfo:nil];
    }
}

- (void)logTransactions:(NSArray *)transactions {
    LogBaker(@"Received %d transactions from App Store", [transactions count]);
    for(SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                LogBaker(@"- purchasing: %@", transaction.payment.productIdentifier);
                break;
            case SKPaymentTransactionStatePurchased:
                LogBaker(@"- purchased: %@", transaction.payment.productIdentifier);
                break;
            case SKPaymentTransactionStateFailed:
                LogBaker(@"- failed: %@", transaction.payment.productIdentifier);
                break;
            case SKPaymentTransactionStateRestored:
                LogBaker(@"- restored: %@", transaction.payment.productIdentifier);
                break;
            default:
                LogBaker(@"- unsupported transaction type: %@", transaction.payment.productIdentifier);
                break;
        }
    }
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    NSDictionary *userInfo = @{@"transaction": transaction};
    NSString *productId = transaction.payment.productIdentifier;

    if ([productId isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID] || [@[] containsObject:productId]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_subscription_purchased" object:self userInfo:userInfo];
    } else if ([self productFor:productId]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_issue_purchased" object:self userInfo:userInfo];
    } else {
        LogBaker(@"ERROR: Completed transaction for %@, which is not a Product ID this app recognises", productId);
    }
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    NSDictionary *userInfo = @{@"transaction": transaction};
    NSString *productId = transaction.payment.productIdentifier;

    if ([productId isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID] || [@[] containsObject:productId]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_subscription_restored" object:self userInfo:userInfo];
    } else if ([self productFor:productId]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_issue_restored" object:self userInfo:userInfo];
    } else {
        LogBaker(@"ERROR: Trying to restore %@, which is not a Product ID this app recognises", productId);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_restored_issue_not_recognised" object:self userInfo:userInfo];
    }
}

-(void)failedTransaction:(SKPaymentTransaction *)transaction {
    LogBaker(@"Payment transaction failure: %@", transaction.error);

    NSDictionary *userInfo = @{@"transaction": transaction};
    NSString *productId = transaction.payment.productIdentifier;

    if ([productId isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID] || [@[] containsObject:productId]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_subscription_failed" object:self userInfo:userInfo];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_issue_purchase_failed" object:self userInfo:userInfo];
    }

    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)restore {
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_restore_finished" object:self userInfo:nil];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    LogBaker(@"Transaction restore failure: %@", error);

    NSDictionary *userInfo = @{@"error": error};

    [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_restore_failed" object:self userInfo:userInfo];
}

#pragma mark - Products

- (SKProduct *)productFor:(NSString *)productID {
    return (self.products)[productID];
}

#pragma mark - Subscriptions

- (BOOL)hasSubscriptions {
    return [FREE_SUBSCRIPTION_PRODUCT_ID length] > 0 || [@[] count] > 0;
}

#pragma mark - Memory management


@end
