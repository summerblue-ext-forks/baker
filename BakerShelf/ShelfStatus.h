

/*
 |--------------------------------------------------------------------------
 | 每一个 product 在获取到价格之后, 都把价格先缓存在本地, 这里就是缓存的实现.
 |--------------------------------------------------------------------------
 |
 */


#import <Foundation/Foundation.h>
#import "JSONStatus.h"

@interface ShelfStatus : JSONStatus

@property (strong, nonatomic) NSMutableDictionary *prices;

- (id)init;
- (void)save;
- (NSString *)priceFor:(NSString *)productID;
- (void)setPrice:(NSString *)price for:(NSString *)productID;

@end
