

/*
 |--------------------------------------------------------------------------
 | 每一个 product 在获取到价格之后, 都把价格先缓存在本地, 这里就是缓存的实现.
 |--------------------------------------------------------------------------
 |
 */

#import "ShelfStatus.h"

@implementation ShelfStatus

@synthesize prices;

- (id)init {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    NSString *statusPath = [[cachePath stringByAppendingPathComponent:@"shelf-status"] stringByAppendingPathExtension:@"json"];

    self = [super initWithJSONPath:statusPath];
    if (self) {
        self.prices = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSDictionary *)load {
    NSDictionary *jsonDict = [super load];

    NSDictionary *jsonPrices = jsonDict[@"prices"];
    [jsonPrices enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setPrice:obj for:key];
    }];

    return jsonDict;
}

- (void)save {
    NSDictionary *jsonDict = @{@"prices": prices};

    [super save:jsonDict];
}

- (NSString *)priceFor:(NSString *)productID {
    return prices[productID];
}

- (void)setPrice:(NSString *)price for:(NSString *)productID {
    prices[productID] = price;
}


@end
