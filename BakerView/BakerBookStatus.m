

/*
 |--------------------------------------------------------------------------
 | Book 的状态保存, 在 app 关闭的时候调用, 和 book 打开的时候启用, 用户友好. 
 | 记住用户的当前的页数, 还有用户在那一页页面的位置.
 |--------------------------------------------------------------------------
 |
 */


#import "BakerBookStatus.h"

@implementation BakerBookStatus

@synthesize page;
@synthesize scrollIndex;

- (id)initWithBookId:(NSString *)bookId {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    NSString *statusPath = [[[cachePath stringByAppendingPathComponent:@"statuses"] stringByAppendingPathComponent:bookId] stringByAppendingPathExtension:@"json"];

    return [super initWithJSONPath:statusPath];
}

- (NSDictionary *)load {
    NSDictionary *jsonDict = [super load];

    self.page        = jsonDict[@"page"];
    self.scrollIndex = jsonDict[@"scroll-index"];

    return jsonDict;
}

- (void)save {
    NSDictionary *jsonDict = @{@"page": page, @"scroll-index": scrollIndex};

    [super save:jsonDict];
}


@end
