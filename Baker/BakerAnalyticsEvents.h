
/*
 |--------------------------------------------------------------------------
 | 事件统计, 方便做 Google 或者别的事件统计的集成
 |--------------------------------------------------------------------------
 |
 */

#import <Foundation/Foundation.h>

#import "BakerViewController.h"
#import "ShelfViewController.h"
#import "IssueViewController.h"

@interface BakerAnalyticsEvents : NSObject {

    id tracker; // Can be used to reference tracking libraries (i.e. Google Analytics, ...)
    
}

#pragma mark - Singleton

+ (BakerAnalyticsEvents *)sharedInstance;
- (id)init;

@end
