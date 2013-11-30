

/*
 |--------------------------------------------------------------------------
 | 书架管理器, 用来管理 Issue 的, IssuesManager 管理 Issue, 注意单复数的关系. 
 | 每一个 Issue 是一期杂志 .
 |--------------------------------------------------------------------------
 |
 */


#import "IssuesManager.h"
#import "BakerIssue.h"
#import "Utils.h"
#import "BakerAPI.h"

@implementation IssuesManager

@synthesize issues;
@synthesize shelfManifestPath;

/**
 *  初始化 IssuesManager, 只被单例模式 sharedInstance 调用
 *
 *  @return IssuesManager 对象
 */
-(id)init {
    self = [super init];

    if (self) {
        self.issues = nil;

        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        self.shelfManifestPath = [cachePath stringByAppendingPathComponent:@"shelf.json"];
        LogBaker("shelf.json 缓存存放地: %@", self.shelfManifestPath);
    }

    return self;
}

#pragma mark - Singleton 单例模式

/**
 *  
 *  单例模式, 用于快速调用
 *
 *  IssuesManager *issuesManager = [IssuesManager sharedInstance];
 *
 *  @return IssuesManager 实例
 */
+ (IssuesManager *)sharedInstance {
    static dispatch_once_t once;
    static IssuesManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

/**
 *  下载最新的 shelf.json 文件, 并更新本地 NewsstandKit, 初始化 BakerIssue, 排序 self.issues
 *  首页杂志列表的时候调用
 *
 *  @return status(BOOL) 请求 json 是否成功
 */
-(void)refresh:(void (^)(BOOL)) callback
{
    [self getShelfJSON:^(NSData* json) {
        
        if (json)
        {
            // 如果有返回数据
            NSError* error = nil;
            
            // 开始解析原始的 json 数据为 NSArray
            NSArray* jsonArr = [NSJSONSerialization JSONObjectWithData:json
                                                               options:0
                                                                 error:&error];
            
            // 更新 NewsstandKit 下的 NKLibrary
            [self updateNewsstandIssuesList:jsonArr];
            
            NSMutableArray *tmpIssues = [NSMutableArray array];     // 用来排序的
            [jsonArr enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
            {
                // 循环的去实例, 初始化 BakerIssue
                BakerIssue *issue = [[BakerIssue alloc] initWithIssueData:obj];
                [tmpIssues addObject:issue];
            }];
            
            // 进行排序, 冒泡排序
            self.issues = [tmpIssues sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
            {
                NSDate *first = [Utils dateWithFormattedString:[(BakerIssue*)a date]];
                NSDate *second = [Utils dateWithFormattedString:[(BakerIssue*)b date]];
                return [second compare:first];
            }];
            
            // 调用回调函数, 并参入 status 状态, YES 为成功
            if (callback) {
                callback(YES);
            }
        }
        else
        {
            // 调用回调函数, 并参入 status 状态, YES 为成功
            if (callback) {
                callback(NO);
            }
        }
    }];
}

/**
 *  调用 BakerAPI 接口getShelfJSON 来获取 shelf.json 的数据, 并做本地缓存.
 *  @TODO 需要从新做下缓存逻辑, 提前判断下是否有网络, 如果没有的话, 就读本地的缓存数据.
 */
-(void)getShelfJSON:(void (^)(NSData*)) callback
{
    BakerAPI *api = [BakerAPI sharedInstance];
    [api getShelfJSON:^(NSData* json) {
        NSError *cachedShelfError = nil;
        
        if (json)
        {
            // Cache the shelf manifest
            [[NSFileManager defaultManager] createFileAtPath:self.shelfManifestPath contents:nil attributes:nil];
            NSError* error = nil;
            [json writeToFile:self.shelfManifestPath
                      options:NSDataWritingAtomic
                        error:&error];
            if (cachedShelfError) {
                LogAllTheTime(@"[BakerShelf] ERROR: Unable to cache 'shelf.json' manifest: %@", cachedShelfError);
            }
        }
        else
        {
            if ([[NSFileManager defaultManager] fileExistsAtPath:self.shelfManifestPath]) {
                LogBaker(@"准备把 'shelf.json' 缓存到本地路径: %@", cachedShelfError);
                json = [NSData dataWithContentsOfFile:self.shelfManifestPath options:NSDataReadingMappedIfSafe error:&cachedShelfError];
                if (cachedShelfError) {
                    LogAllTheTime(@"[BakerShelf] Error loading cached copy of 'shelf.json': %@", cachedShelfError);
                }
            } else {
                LogAllTheTime(@"[BakerShelf] No cached 'shelf.json' manifest found at %@", self.shelfManifestPath);
                json = nil;
            }
        }
        
        if (callback) {
            callback(json);
        };
    }];
}

/**
 *  更新 NewsstandKit 下的 NKLibrary 为最新的
 *
 *  @param issuesList 线上请求下来 issues 数组
 */
-(void)updateNewsstandIssuesList:(NSArray *)issuesList
{
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    
    // 此变量用来跟踪本地有但是线上没有的 issues, 先获取已知的 issues
    NSMutableArray *discardedIssues = [NSMutableArray arrayWithArray:[nkLib issues]];

    for (NSDictionary *issue in issuesList) {
        NSDate *date = [Utils dateWithFormattedString:issue[@"date"]];
        NSString *name = issue[@"name"];

        // 初始化 issue , 获取同 name 的 issue 对象, 如果之前存在的话
        NKIssue *nkIssue = [nkLib issueWithName:name];

        if(!nkIssue) // 如果是线上有, 但是本地没有的话
        {
            // Add issue to Newsstand Library
            @try {
                nkIssue = [nkLib addIssueWithName:name date:date];
                LogBaker(@"NKLibrary 增加新 Issues Succeed: Added %@ %@", name, date);
            } @catch (NSException *exception) {
                LogBaker(@"NKLibrary 增加新 ERROR: Exception %@", exception);
            }
        }
        else    // 如果是本地有, 线上也有的话
        {
            // Issue already in Newsstand Library
            [discardedIssues removeObject:nkIssue];
        }
    }

    // 此处去除本地有, 但是线上没有的 issues , 以最新的 shelf.json 为准
    for (NKIssue *discardedIssue in discardedIssues) {
        [nkLib removeIssue:discardedIssue];
        LogBaker(@"[BakerShelf] Newsstand - Removed %@", discardedIssue.name);
    }
}

-(NSSet *)productIDs {
    NSMutableSet *set = [NSMutableSet set];
    for (BakerIssue *issue in self.issues) {
        if (issue.productID) {
            [set addObject:issue.productID];
        }
    }
    return set;
}

- (BOOL)hasProductIDs {
    return [[self productIDs] count] > 0;
}

- (BakerIssue *)latestIssue {
    return issues[0];
}


+ (NSArray *)localBooksList {
    NSMutableArray *booksList = [NSMutableArray array];
    NSFileManager *localFileManager = [NSFileManager defaultManager];
    NSString *booksDir = [[NSBundle mainBundle] pathForResource:@"books" ofType:nil];

    NSArray *dirContents = [localFileManager contentsOfDirectoryAtPath:booksDir error:nil];
    for (NSString *file in dirContents) {
        NSString *manifestFile = [booksDir stringByAppendingPathComponent:[file stringByAppendingPathComponent:@"book.json"]];
        if ([localFileManager fileExistsAtPath:manifestFile]) {
            BakerBook *book = [[BakerBook alloc] initWithBookPath:[booksDir stringByAppendingPathComponent:file] bundled:YES];
            if (book) {
                BakerIssue *issue = [[BakerIssue alloc] initWithBakerBook:book];
                [booksList addObject:issue];
            } else {
                LogBaker(@"[BakerShelf] ERROR: Book %@ could not be initialized. Is 'book.json' correct and valid?", file);
            }
        } else {
            LogBaker(@"[BakerShelf] ERROR: Cannot find 'book.json'. Is it present? Should be here: %@", manifestFile);
        }
    }

    return [NSArray arrayWithArray:booksList];
}


@end
