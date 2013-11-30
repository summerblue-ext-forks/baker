

/*
 |--------------------------------------------------------------------------
 | Application Bootstrap 文件
 |--------------------------------------------------------------------------
 |
 | 程序开机启动, 进入后台, 返回前台, 内存警告, 注册消息通知等 App level 的事件在此文件
 | 中处理.
 |
 */

/** 常量定义 **/
#import "Constants.h"
#import "UIConstants.h"


#import "AppDelegate.h"
#import "UICustomNavigationController.h"
#import "UICustomNavigationBar.h"

#import "IssuesManager.h"
#import "BakerAPI.h"
#import "UIColor+Extensions.h"
#import "Utils.h"

#import "BakerViewController.h"
#import "BakerAnalyticsEvents.h"

@implementation AppDelegate

@synthesize window;
@synthesize rootViewController;
@synthesize rootNavigationController;

/**
 *  initialize是在类或者其子类的第一个方法被调用前调用, 并且此方法只会被调用一次.
 */
+ (void)initialize {
    // 设置 User Agent , 为啥要在这里设置, 必须是在 App 开始的时候设置才有用 见这里: http://stackoverflow.com/a/8666438/689832
    NSDictionary *userAgent = [[NSDictionary alloc] initWithObjectsAndKeys:@"Mozilla/5.0 (compatible; BakerFramework) AppleWebKit/533.00+ (KHTML, like Gecko) Mobile", @"UserAgent", nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:userAgent];
    [userAgent release];
}

- (void)dealloc
{
    [window release];
    [rootViewController release];
    [rootNavigationController release];

    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [BakerAPI generateUUIDOnce];

    LogBaker(@"注册 Newsstand Push Notification");
    [application registerForRemoteNotificationTypes:UIRemoteNotificationTypeNewsstandContentAvailability];

    // 24 小时内, 后台下载只能发生一次. 开启 `NKDontThrottleNewsstandContentNotifications` 能解除此约束
    #ifdef BAKERDEBUG
    LogBaker(@"注册 NKDontThrottleNewsstandContentNotifications ");
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NKDontThrottleNewsstandContentNotifications"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    #endif
    
    // 检查是否是从 Push Notification 启动 App 的
    NSDictionary *payload = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (payload) {
        NSDictionary *aps = payload[@"aps"];
        if (aps && aps[@"content-available"])
        {
            LogBaker(@"远程 Push Notification 唤醒");
            __block UIBackgroundTaskIdentifier backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
                [application endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
            }];

            // Credit where credit is due. This semaphore solution found here:
            // http://stackoverflow.com/a/4326754/2998
            dispatch_semaphore_t sema = NULL;
            sema = dispatch_semaphore_create(0);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self applicationWillHandleNewsstandNotificationOfContent:payload[@"content-name"]];
                [application endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
                dispatch_semaphore_signal(sema);
            });

            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
            dispatch_release(sema);
        }
    }

    self.rootViewController = [[[ShelfViewController alloc] init] autorelease];

    self.rootNavigationController = [[[UICustomNavigationController alloc] initWithRootViewController:self.rootViewController] autorelease];
    UICustomNavigationBar *navigationBar = (UICustomNavigationBar *)self.rootNavigationController.navigationBar;

    // iOS7 适配
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        // Background is 64px high: in iOS7, it will be used as the background for the status bar as well.
        [navigationBar setTintColor:[UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR]];
        [navigationBar setBarTintColor:[UIColor colorWithHexString:@"ffffff"]];
        [navigationBar setBackgroundImage:[UIImage imageNamed:@"navigation-bar-bg"] forBarMetrics:UIBarMetricsDefault];
        navigationBar.titleTextAttributes = @{UITextAttributeTextColor: [UIColor colorWithHexString:@"000000"]};
    }
    else
    {
        // Background is 44px: in iOS6 and below, a higher background image would make the navigation bar
        // appear higher than it should be.
        [navigationBar setBackgroundImage:[UIImage imageNamed:@"navigation-bar-bg-ios6"] forBarMetrics:UIBarMetricsDefault];
        [navigationBar setTintColor:[UIColor colorWithHexString:@"333333"]]; // black will not trigger a pushed status
    }

    self.window = [[[InterceptorWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    self.window.backgroundColor = [UIColor whiteColor];

    self.window.rootViewController = self.rootNavigationController;
    [self.window makeKeyAndVisible];

    
    // -------- 初始化用户事件 (event) 统计, 注册 notification
    [BakerAnalyticsEvents sharedInstance]; // Initialization
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerApplicationStart" object:self];
    
    return YES;
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
    NSString *apnsToken = [[deviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    apnsToken = [apnsToken stringByReplacingOccurrencesOfString:@" " withString:@""];

    LogBaker(@"Divice Token 获取成功 (as NSData) is: %@", deviceToken);
    LogBaker(@"Divice Token 获取成功 (as NSString) is: %@", apnsToken);

    [[NSUserDefaults standardUserDefaults] setObject:apnsToken forKey:@"apns_token"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    BakerAPI *api = [BakerAPI sharedInstance];
    [api postAPNSToken:apnsToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
	LogBaker(@"Divice Token 获取失败, error: %@", error);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    LogBaker(@"远程 Push Notification 接收成功: %@", userInfo);
    NSDictionary *aps = userInfo[@"aps"];
    if (aps && aps[@"content-available"])
    {
        [self applicationWillHandleNewsstandNotificationOfContent:userInfo[@"content-name"]];
    }
}

// iOS7 兼容
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))handler
{
    NSDictionary *aps = userInfo[@"aps"];
    if (aps && aps[@"content-available"])
    {
        [self applicationWillHandleNewsstandNotificationOfContent:userInfo[@"content-name"]];
    }
}

/**
 *  接收并处理 Remote Pushnotification , 3 个地方调用
 *
 *
 *  @param contentName payload[@"content-name"] 指定下载期刊的名字
 */
- (void)applicationWillHandleNewsstandNotificationOfContent:(NSString *)contentName
{
    IssuesManager *issuesManager = [IssuesManager sharedInstance];
    PurchasesManager *purchasesManager = [PurchasesManager sharedInstance];
    __block BakerIssue *targetIssue = nil;

    [issuesManager refresh:^(BOOL status)
    {
        // 如果指定了下载期刊的话, 指定目标 issue
        if (contentName)
        {
            for (BakerIssue *issue in issuesManager.issues) {
                if ([issue.ID isEqualToString:contentName]) {
                    targetIssue = issue;
                    break;
                }
            }
        }
        else
        {
            // 指定为最新一期
            targetIssue = (issuesManager.issues)[0];
        }

        [purchasesManager retrievePurchasesFor:[issuesManager productIDs] withCallback:^(NSDictionary *_purchases)
        {
            NSString *targetStatus = [targetIssue getStatus];
            LogBaker(@"Remote Push Notification - 目标杂志 (targetStatus) 的状态为: %@", targetStatus);

            if ([targetStatus isEqualToString:@"remote"] || [targetStatus isEqualToString:@"purchased"])
            {
                LogBaker(@"Remote Push Notification - 开始下载...... <%@> ", targetIssue.ID);
                [targetIssue download];
            }
            else if ([targetStatus isEqualToString:@"purchasable"] || [targetStatus isEqualToString:@"unpriced"])
            {
                LogBaker(@"Remote Push Notification - 没有权限下载 <%@>, 需要购买先", targetIssue.ID);
            }
            else if (![targetStatus isEqualToString:@"remote"])
            {
                LogBaker(@"Remote Push Notification - 杂志 <%@> 正在下载中 或者 已经下载. ", targetIssue.ID);
            }
        }];
    }];
}
- (void)applicationWillResignActive:(UIApplication *)application
{
    // 保存 page 和 scrolling-y坐标
    [[NSNotificationCenter defaultCenter] postNotificationName:@"applicationWillResignActiveNotification" object:nil];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

    // 清除 icon 上得角标, 用户关闭应用, 应该算查看过消息了
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (void)applicationWillEnterForeground:(UIApplication *)application{}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // 清除 icon 上得角标, 用户打开应用, 应该算查看过消息了
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (void)applicationWillTerminate:(UIApplication *)application{}

@end
