

/*
 |--------------------------------------------------------------------------
 | 书架管理器, 用来管理 BakerIssue 的, IssuesManager 管理 BakerIssue, 注意单复数的关系.
 | 每一个 Issue 是一期杂志杂志 .
 |--------------------------------------------------------------------------
 |
 */

#import <Foundation/Foundation.h>
#import <NewsstandKit/NewsstandKit.h>
#import "BakerIssue.h"

@interface IssuesManager : NSObject

@property (copy, nonatomic) NSArray *issues;
@property (strong, nonatomic) NSString *shelfManifestPath;

#pragma mark - Singleton

+ (IssuesManager *)sharedInstance;

-(void)refresh:(void (^)(BOOL)) callback;
-(NSSet *)productIDs;
-(BOOL)hasProductIDs;
-(BakerIssue *)latestIssue;

+ (NSArray *)localBooksList;

@end
