

/*
 |--------------------------------------------------------------------------
 | 每一个 Issue 是一期杂志 .
 |--------------------------------------------------------------------------
 |
 */

#import "Constants.h"
#import <Foundation/Foundation.h>

#ifdef BAKER_NEWSSTAND
#import <NewsstandKit/NewsstandKit.h>
#import "PurchasesManager.h"
#endif

#import "BakerBook.h"

// 过渡的状态, 瞬时的状态
typedef enum transientStates {
    BakerIssueTransientStatusNone,
    BakerIssueTransientStatusDownloading,
    BakerIssueTransientStatusOpening,
    BakerIssueTransientStatusPurchasing,
    BakerIssueTransientStatusUnpriced
} BakerIssueTransientStatus;

#ifdef BAKER_NEWSSTAND
@interface BakerIssue : NSObject <NSURLConnectionDownloadDelegate> {
    PurchasesManager *purchasesManager;
}
#else
@interface BakerIssue : NSObject
#endif

@property (copy, nonatomic) NSString *ID;
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *info;
@property (copy, nonatomic) NSString *date;
@property (copy, nonatomic) NSURL *url;
@property (copy, nonatomic) NSString *path;

@property (copy, nonatomic) NSString *coverPath;
@property (copy, nonatomic) NSURL *coverURL;

@property (copy, nonatomic) NSString *productID;
@property (copy, nonatomic) NSString *price;

@property (retain, nonatomic) BakerBook *bakerBook;

@property (assign, nonatomic) BakerIssueTransientStatus transientStatus;

@property (copy, nonatomic) NSString *notificationDownloadStartedName;
@property (copy, nonatomic) NSString *notificationDownloadProgressingName;
@property (copy, nonatomic) NSString *notificationDownloadFinishedName;
@property (copy, nonatomic) NSString *notificationDownloadErrorName;
@property (copy, nonatomic) NSString *notificationUnzipErrorName;

-(id)initWithBakerBook:(BakerBook *)bakerBook;
-(void)getCoverWithCache:(bool)cache andBlock:(void(^)(UIImage *img))completionBlock;
-(NSString *)getStatus;

#ifdef BAKER_NEWSSTAND
-(id)initWithIssueData:(NSDictionary *)issueData;
-(void)download;
-(void)downloadWithAsset:(NKAssetDownload *)asset;
#endif

@end
