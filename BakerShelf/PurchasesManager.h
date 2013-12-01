

/*
 |--------------------------------------------------------------------------
 | 内购买管理器.
 | 用于处理当前用户杂志购买的操作, 显示杂志是否已购买, 用户购买过的杂志...
 |--------------------------------------------------------------------------
 |
 */


#import "Constants.h"
#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@interface PurchasesManager : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver> {
    NSMutableDictionary *_purchases;
    BOOL _enableProductRequestFailureNotifications;
}

@property (strong, nonatomic) NSMutableDictionary *products;
@property (strong, nonatomic) NSNumberFormatter *numberFormatter;
@property (nonatomic) BOOL subscribed;

#pragma mark - Singleton

+ (PurchasesManager *)sharedInstance;

#pragma mark - Purchased flag

- (BOOL)isMarkedAsPurchased:(NSString *)productID;
- (void)markAsPurchased:(NSString *)productID;

#pragma mark - Prices

- (void)retrievePricesFor:(NSSet *)productIDs;
- (void)retrievePricesFor:(NSSet *)productIDs andEnableFailureNotifications:(BOOL)enable;

- (void)retrievePriceFor:(NSString *)productID;
- (void)retrievePriceFor:(NSString *)productID andEnableFailureNotification:(BOOL)enable;

- (NSString *)priceFor:(NSString *)productID;

#pragma mark - Purchases

- (BOOL)purchase:(NSString *)productID;
- (BOOL)finishTransaction:(SKPaymentTransaction *)transaction;
- (void)restore;
- (void)retrievePurchasesFor:(NSSet *)productIDs withCallback:(void (^)(NSDictionary*))callback;
- (BOOL)isPurchased:(NSString *)productID;

#pragma mark - Products

- (SKProduct *)productFor:(NSString *)productID;

#pragma mark - Subscriptions

- (BOOL)hasSubscriptions;

@end
