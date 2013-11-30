

/*
 |--------------------------------------------------------------------------
 | 每一个 Issue 是一期杂志 .
 |--------------------------------------------------------------------------
 |
 */


#import "BakerIssue.h"
#import "BakerAPI.h"

#import "SSZipArchive.h"
#import "Reachability.h"
#import "Utils.h"
#import "NSURL+Extensions.h"

@implementation BakerIssue

@synthesize ID;
@synthesize title;
@synthesize info;
@synthesize date;
@synthesize url;
@synthesize path;
@synthesize bakerBook;
@synthesize coverPath;
@synthesize coverURL;
@synthesize productID;
@synthesize price;
@synthesize transientStatus;

@synthesize notificationDownloadStartedName;
@synthesize notificationDownloadProgressingName;
@synthesize notificationDownloadFinishedName;
@synthesize notificationDownloadErrorName;
@synthesize notificationUnzipErrorName;

-(id)initWithBakerBook:(BakerBook *)book {
    self = [super init];
    if (self) {
        self.ID = book.ID;
        self.title = book.title;
        self.info = @"";
        self.date = book.date;
        self.url = [NSURL URLWithString:book.url];
        self.path = book.path;
        self.productID = @"";
        self.price = nil;

        self.bakerBook = book;

        self.coverPath = @"";
        if (book.cover == nil) {
            // TODO: set path to a default cover (right now a blank box will be displayed)
            LogBaker(@"Cover not specified for %@, probably missing from book.json", book.ID);
        } else {
            self.coverPath = [book.path stringByAppendingPathComponent:book.cover];
        }

        self.transientStatus = BakerIssueTransientStatusNone;

        [self setNotificationDownloadNames];
    }
    return self;
}

/**
 *  动态设置 Notification 的 KEY 为 issue 的 id, 防止重写, 允许多个 issue 同时下载.
 */
- (void)setNotificationDownloadNames
{
    self.notificationDownloadStartedName = [NSString stringWithFormat:@"notification_download_started_%@", self.ID];
    self.notificationDownloadProgressingName = [NSString stringWithFormat:@"notification_download_progressing_%@", self.ID];
    self.notificationDownloadFinishedName = [NSString stringWithFormat:@"notification_download_finished_%@", self.ID];
    self.notificationDownloadErrorName = [NSString stringWithFormat:@"notification_download_error_%@", self.ID];
    self.notificationUnzipErrorName = [NSString stringWithFormat:@"notification_unzip_error_%@", self.ID];
}

/**
 *  使用 shelf.json 里面的一个单元, 也就是一本杂志的信息, 来初始化此类, 
 *  只在 IssuesManager 的 refresh 方法中调用.
 *  请求 shelf.json 数据成功后, 会解析 issues 数组, 并一个个传数据实例化.
 *
 *  @param issueData self.json 里面的二级单元内容
 *
 *  @return  self
 */
-(id)initWithIssueData:(NSDictionary *)issueData
{
    self = [super init];
    if (self)
    {
        // 赋值属性
        self.ID = issueData[@"name"];
        self.title = issueData[@"title"];
        self.info = issueData[@"info"];
        self.date = issueData[@"date"];
        self.coverURL = [NSURL URLWithString:issueData[@"cover"]];
        self.url = [NSURL URLWithString:issueData[@"url"]];
        if (issueData[@"product_id"] != [NSNull null])
        {   // 作为内置购买使用的
            self.productID = issueData[@"product_id"];
        }
        self.price = nil;

        // 初始化 purchasesManager
        purchasesManager = [PurchasesManager sharedInstance];

        // 设置缓存的路径
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        self.coverPath = [cachePath stringByAppendingPathComponent:self.ID];
        LogBaker(@"缓存杂志 <%@> 的封面到本地, 路径为: %@", self.ID, self.coverPath);

        // 获取 Newsstand Kit 里面的 NKIssue 的 path
        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.ID];
        if (nkIssue) {
            self.path = [[nkIssue contentURL] path];
        } else {
            self.path = nil;
        }

        self.bakerBook = nil;

        // 初始化 过渡的状态, 瞬时的状态
        self.transientStatus = BakerIssueTransientStatusNone;

        [self setNotificationDownloadNames];
    }
    return self;
}

/**
 *  判断 NKIssueContentStatus 的状态, NK 只提供三种状态
 *
 *  @param contentStatus NKIssueContentStatus
 *
 *  @return NSString
 */
-(NSString *)nkIssueContentStatusToString:(NKIssueContentStatus) contentStatus
{
    if (contentStatus == NKIssueContentStatusNone) {
        return @"remote";
    } else if (contentStatus == NKIssueContentStatusDownloading) {
        return @"connecting";
    } else if (contentStatus == NKIssueContentStatusAvailable) {
        return @"downloaded";
    }
    return @"";
}

/**
 *  下载 Issue , 估计 self.url 的值, 使用 get 方式请求.
 */
- (void)download {

    // 使用 Google 来判断是否有网络, Not a good idea ...@TODO 修改为一个合理的域名, 如 baidu.com
    Reachability* reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    if ([reach isReachable])
    {
        LogBaker(@"开始发起下载请求, 目标的 URL 为 : %@", self.url);
        BakerAPI *api = [BakerAPI sharedInstance];
        NSURLRequest *req = [api requestForURL:self.url method:@"GET"];

        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.ID];

        NKAssetDownload *assetDownload = [nkIssue addAssetWithRequest:req];
        [self downloadWithAsset:assetDownload];
    }
    else
    {
        LogBaker(@"下载失败, 无法发送请求, 目标的 URL 为 : %@", self.url);
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadErrorName object:self userInfo:nil];
    }
}
- (void)downloadWithAsset:(NKAssetDownload *)asset
{
    [asset downloadWithDelegate:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadStartedName object:self userInfo:nil];
}

#pragma mark - Newsstand download management

/**
 *  下载进行中, 发送消息, 更新进度条, 来自 NSURLConnection 的 Delegate
 *
 *  @param connection
 *  @param bytesWritten       这一次下载了多少
 *  @param totalBytesWritten  下载完成全部大小
 *  @param expectedTotalBytes  预计需要下载的大小
 */
- (void)connection:(NSURLConnection *)connection
      didWriteData:(long long)bytesWritten
 totalBytesWritten:(long long)totalBytesWritten
expectedTotalBytes:(long long)expectedTotalBytes
{
    NSDictionary *userInfo = @{@"totalBytesWritten": @(totalBytesWritten),
                              @"expectedTotalBytes": @(expectedTotalBytes)};
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadProgressingName object:self userInfo:userInfo];
}

/**
 *  来自 NSURLConnection 的 Delegate, 下载完成, 调用负责解压的方法进行解压处理
 *
 *  @param connection     链接
 *  @param destinationURL 下载的 URL
 */
- (void)connectionDidFinishDownloading:(NSURLConnection *)connection destinationURL:(NSURL *)destinationURL
{
    [self unpackAssetDownload:connection.newsstandAssetDownload toURL:destinationURL];
}

/**
 *  解压下载下来的压缩文件, 并移到目标目录
 *
 *  @param newsstandAssetDownload NKAssetDownload 实例
 *  @param destinationURL         下载目标的 URL
 */
- (void)unpackAssetDownload:(NKAssetDownload *)newsstandAssetDownload toURL:(NSURL *)destinationURL {

    UIApplication *application = [UIApplication sharedApplication];
    NKIssue *nkIssue = newsstandAssetDownload.issue;
    NSString *destinationPath = [[nkIssue contentURL] path];

    // 处理错误异常
    __block UIBackgroundTaskIdentifier backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        LogBaker(@"解压文件中.... 目标文件夹 %@", destinationPath);
        BOOL unzipSuccessful = NO;
        unzipSuccessful = [SSZipArchive unzipFileAtPath:[destinationURL path] toDestination:destinationPath];
        if (!unzipSuccessful) {
            LogBaker(@"解压文件出现错误.... 请确定文件是合法的 phub 文件, 下载临时存放地: %@ ", [destinationURL path]);
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [[NSNotificationCenter defaultCenter] postNotificationName:notificationUnzipErrorName object:self userInfo:nil];
            });
        }

        LogBaker(@"解压文件成功, 并成功解压到目标文件夹, 清除临时下载文件: %@", [destinationURL path]);
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSError *error;
        if ([fileMgr removeItemAtPath:[destinationURL path] error:&error] != YES){
            LogBaker(@"删除临时文件出现错误, 错误信息: %@", [error localizedDescription]);
        }

        if (unzipSuccessful)
        {
            // 通知主线程的 UI 变更.
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadFinishedName object:self userInfo:nil];
            });
        }

        [self updateNewsstandIcon];

        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    });
}

/**
 *  设置 Newsstand App 的封面为最新下载的一期的封面
 */
- (void)updateNewsstandIcon {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];

    UIImage *coverImage = [UIImage imageWithContentsOfFile:self.coverPath];
    if (coverImage) {
        [[UIApplication sharedApplication] setNewsstandIconImage:coverImage];
    }
}

/**
 *  断点续传的 delegate, 重新开始下载之前被挂起的下载任务, NSURLConnection 在调用此方法后还会调用
 *  'connection:didWriteData:totalBytesWritten:expectedTotalBytes: ', 在那个方法里面, 我们已经做了
 *  下载进度的视觉效果, 所有此 delegate 不需要做别的处理.
 */
- (void)connectionDidResumeDownloading:(NSURLConnection *)connection totalBytesWritten:(long long)totalBytesWritten expectedTotalBytes:(long long)expectedTotalBytes {
    // Nothing to do for now
}

/**
 *  下载出错, 来自 NSURLConnection 的 Delegate
 */
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    LogBaker(@"Connection error when trying to download %@: %@", [connection currentRequest].URL, [error localizedDescription]);

    [connection cancel];

    NSDictionary *userInfo = @{@"error": error};
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadErrorName object:self userInfo:userInfo];
}

-(void)getCoverWithCache:(bool)cache andBlock:(void(^)(UIImage *img))completionBlock {
    UIImage *image = [UIImage imageWithContentsOfFile:self.coverPath];
    if (cache && image) {
        completionBlock(image);
    } else {
        if (self.coverURL) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
                NSData *imageData = [NSData dataWithContentsOfURL:self.coverURL];
                UIImage *image = [UIImage imageWithData:imageData];
                if (image) {
                    [imageData writeToFile:self.coverPath atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        completionBlock(image);
                    });
                }
            });
        }
    }
}

/**
 *  获取当前 issue 的状态
 *
 *
 *  @return 有以下状态: 
 
 remote => 还未下载
 connecting => 下载中
 downloading => 下载中
 downloaded => 已经下载
 opening => 正在查看中
 purchasing => 购买中
 
 purchased => 已经购买
 purchasable => 未购买
 unpriced => 未标价
 
 bundled => 和 remote 状态相同, baker 提供一个剔除了 newsstand 功能逻辑版本
 
 */
-(NSString *)getStatus
{
    switch (self.transientStatus) {
        case BakerIssueTransientStatusDownloading:
            return @"downloading";
            break;
        case BakerIssueTransientStatusOpening:
            return @"opening";
            break;
        case BakerIssueTransientStatusPurchasing:
            return @"purchasing";
            break;
        default:
            break;
    }

    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    NKIssue *nkIssue = [nkLib issueWithName:self.ID];
    NSString *nkIssueStatus = [self nkIssueContentStatusToString:[nkIssue status]];
    if ([nkIssueStatus isEqualToString:@"remote"] && self.productID)
    { // 如果是还未下载, 并且是设置过 productID 的话
        if ([purchasesManager isPurchased:self.productID])
        {
            return @"purchased";
        }
        else if (self.price)
        {
            return @"purchasable";
        }
        else
        {
            return @"unpriced";
        }
    }
    else
    {
        return nkIssueStatus;
    }
}


@end
