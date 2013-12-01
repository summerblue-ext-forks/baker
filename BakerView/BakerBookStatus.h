

/*
 |--------------------------------------------------------------------------
 | Book 的状态保存, 在 app 关闭的时候调用, 和 book 打开的时候启用, 用户友好. 
 | 记住用户的当前的页数, 还有用户在那一页页面的位置.
 |--------------------------------------------------------------------------
 |
 */

#import <Foundation/Foundation.h>
#import "JSONStatus.h"

@interface BakerBookStatus : JSONStatus

@property (copy, nonatomic) NSNumber *page;
@property (copy, nonatomic) NSString *scrollIndex;

- (id)initWithBookId:(NSString *)bookId;
- (void)save;

@end
