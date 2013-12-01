

/*
 |--------------------------------------------------------------------------
 | 通用常量定义
 |--------------------------------------------------------------------------
 |
 */

#import "LogHelper.h"

#ifndef Baker_Constants_h
#define Baker_Constants_h

    // ----------------------------------------------------------------------------------------------------
    // 开启 NEWSSTAND 模式, baker 代码中有大量的地方用了此常量, 用来区分是否使用 newsstand 模式
    // See: https://github.com/Simbul/baker/wiki/Newsstand-vs-Bundled-publications-support-in-Baker-4.0
    #define BAKER_NEWSSTAND

    #ifdef BAKER_NEWSSTAND

        // ----------------------------------------------------------------------------------------------------
        // 定义 shelf.json 文件的地址, 也就是书架的地址, App 在每一次启动的是都会去加载此文件, wiki 见:
        // https://github.com/Simbul/baker/wiki/Newsstand-shelf-JSON
        #define NEWSSTAND_MANIFEST_URL @"http://bakerframework.com/demo/shelf.json"

        // ----------------------------------------------------------------------------------------------------
        // Optional - This constant specifies the URL to ping back when a user purchases an issue or a subscription.
        // For more information, see: https://github.com/Simbul/baker/wiki/Baker-Server-API
        // E.g. @"http://example.com/purchased"
        #define PURCHASE_CONFIRMATION_URL @""

        // ----------------------------------------------------------------------------------------------------
        // Optional - This constant specifies a URL that will be used to retrieve the list of purchased issues.
        // For more information, see: https://github.com/Simbul/baker/wiki/Baker-Server-API
        // E.g. @"http://example.com/purchases"
        #define PURCHASES_URL @""

        // ----------------------------------------------------------------------------------------------------
        // Optional - This constant specifies the URL to ping back when a user enables push notifications.
        // For more information, see: https://github.com/Simbul/baker/wiki/Baker-Server-API
        // E.g. @"http://example.com/post_apns_token"
        #define POST_APNS_TOKEN_URL @""

        // ----------------------------------------------------------------------------------------------------
        // Mandatory - The following two constants identify the subscriptions you set up in iTunesConnect.
        // See: iTunes Connect -> Manage Your Application -> (Your application) -> Manage In App Purchases
        // You *have* to set at least one among FREE_SUBSCRIPTION_PRODUCT_ID and AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS.

        // This constant identifies a free subscription.
        // E.g. @"com.example.MyBook.subscription.free"
        #define FREE_SUBSCRIPTION_PRODUCT_ID @""

        // This constant identifies one or more auto-renewable subscriptions.
        // E.g.:
        // #define AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS [NSArray arrayWithObjects: \
        //     @"com.example.MyBook.subscription.3months", \
        //     @"com.example.MyBook.subscription.6months", \
        //     nil]
        #define AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS [NSArray arrayWithObjects: \
            nil]

    #endif

    // Timeout for most network requests (in seconds)
    #define REQUEST_TIMEOUT 15

#endif



// ------------------------------------ 各种自定义的 DEBUG, 用来替换 LogBaker 的 ---------------------------------

#ifdef DEBUG
#   define DLog(fmt, ...) BetterNSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

// Baker 的流程, 统一使用此 Micro 来 log
#define BAKERDEBUG

#ifdef BAKERDEBUG
#   define LogBaker(fmt, ...) BetterNSLog((@"Baker >> " fmt @" >>>>> %s [第 %d 行] "), ##__VA_ARGS__, __PRETTY_FUNCTION__, __LINE__ );
#else
#   define LogBaker(...)
#endif

// 永远都显示的内容
#define LogAllTheTime(fmt, ...) BetterNSLog((@" ------>>>>> %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);





