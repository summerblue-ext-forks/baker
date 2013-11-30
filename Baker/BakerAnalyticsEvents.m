

/*
 |--------------------------------------------------------------------------
 | 事件统计, 方便做 Google 或者别的事件统计的集成
 |--------------------------------------------------------------------------
 |
 */


#import "BakerAnalyticsEvents.h"


@implementation BakerAnalyticsEvents


#pragma mark - Singleton

+ (BakerAnalyticsEvents *)sharedInstance {
    static dispatch_once_t once;
    static BakerAnalyticsEvents *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    
    self = [super init];
    
    // ****** Add here your analytics code
    // tracker = [[GAI sharedInstance] trackerWithTrackingId:@"ADD_HERE_YOUR_TRACKING_CODE"];
    
    
    // ****** 注册事件处理器
    [self registerEvents];
    
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Events

- (void)registerEvents {
    // Register the analytics event that are going to be tracked by Baker.
    
    NSArray *analyticEvents = @[@"BakerApplicationStart",
                               @"BakerIssueDownload",
                               @"BakerIssueOpen",
                               @"BakerIssueClose",
                               @"BakerIssuePurchase",
                               @"BakerIssueArchive",
                               @"BakerSubscriptionPurchase",
                               @"BakerViewPage",
                               @"BakerViewIndexOpen",
                               @"BakerViewModalBrowser"];
    
    // 批量注册时间
    for (NSString *eventName in analyticEvents) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(receiveEvent:)
                                                     name:eventName
                                                   object:nil];
    }
    

}

- (void)receiveEvent:(NSNotification *)notification {
    
    LogBaker(@"Analytics Events:-----> 收到来自 %@ 的消息通知.", [notification name]); // Uncomment this to debug
    
    // If you want, you can handle differently the various events
    if ([[notification name] isEqualToString:@"BakerApplicationStart"])
    {
        LogBaker(@"Analytics Events: Baker app opens. Baker App 启动 ");
        
    }
    else if ([[notification name] isEqualToString:@"BakerIssueDownload"])
    {
        LogBaker(@"Analytics Events: a issue download is requested 请求一锅下载");
    }
    else if ([[notification name] isEqualToString:@"BakerIssueOpen"])
    {
        LogBaker(@"Analytics Events: a issue is opened to be read 打开一本杂志");
    }
    else if ([[notification name] isEqualToString:@"BakerIssueClose"])
    {
        LogBaker(@"Analytics Events: a issue that was being read is closed 关闭一本正在阅读的杂志");
    }
    else if ([[notification name] isEqualToString:@"BakerIssuePurchase"])
    {
        LogBaker(@"Analytics Events: a issue purchase is requested 购买一期期刊");
    }
    else if ([[notification name] isEqualToString:@"BakerIssueArchive"])
    {
        LogBaker(@"Analytics Events: a issue archival is requested 用户删除本地保存的期刊");
    }
    else if ([[notification name] isEqualToString:@"BakerSubscriptionPurchase"])
    {
        LogBaker(@"Analytics Events: a subscription purchased is requested 用户购买订阅");
    }
    else if ([[notification name] isEqualToString:@"BakerViewPage"])
    {
        LogBaker(@"Analytics Events: a page is opened 用户正在查看期刊里面的某篇文章");
        // BakerViewController *bakerview = [notification object]; // Uncomment this to get the BakerViewController object and get its properties
        // LogBaker(@"- Tracking page %d", bakerview.currentPageNumber); // This is useful to check if it works
    }
    else if ([[notification name] isEqualToString:@"BakerViewIndexOpen"])
    {
        LogBaker(@"Analytics Events: opening of the index and status bar 用户双击打开顶部导航栏");
    }
    else if ([[notification name] isEqualToString:@"BakerViewModalBrowser"])
    {
        LogBaker(@"Analytics Events: opening of the modal view 打开内置 Web 浏览器");
    }
    else
    {
        
    }
}


@end
