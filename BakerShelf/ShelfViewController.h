

/*
 |--------------------------------------------------------------------------
 | App 的 rootViewController , 书架列表
 |--------------------------------------------------------------------------
 |
 */


#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>

#import "BakerIssue.h"
#import "IssuesManager.h"
#import "ShelfStatus.h"
#import "BakerAPI.h"
#import "PurchasesManager.h"

@interface ShelfViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate, UIActionSheetDelegate, UIWebViewDelegate> {
    BakerAPI *api;
    IssuesManager *issuesManager;
    NSMutableArray *notRecognisedTransactions;
    __weak UIPopoverController *infoPopover;

    #ifdef BAKER_NEWSSTAND
    PurchasesManager *purchasesManager;
    #endif
}

@property (copy, nonatomic) NSArray *issues;
@property (copy, nonatomic) NSArray *supportedOrientation;

@property (retain, nonatomic) NSMutableArray *issueViewControllers;
@property (retain, nonatomic) ShelfStatus *shelfStatus;

@property (strong, nonatomic) UICollectionView *gridView;
@property (strong, nonatomic) UIImageView *background;
@property (strong, nonatomic) UIBarButtonItem *refreshButton;
@property (strong, nonatomic) UIBarButtonItem *subscribeButton;

@property (strong, nonatomic) UIActionSheet *subscriptionsActionSheet;
@property (strong, nonatomic) NSArray *subscriptionsActionSheetActions;
@property (strong, nonatomic) UIAlertView *blockingProgressView;

@property (copy, nonatomic) NSString *bookToBeProcessed;

#pragma mark - Init
- (id)init;
- (id)initWithBooks:(NSArray *)currentBooks;

#pragma mark - Shelf data source
#ifdef BAKER_NEWSSTAND
- (void)handleRefresh:(NSNotification *)notification;

#pragma mark - Store Kit
- (void)handleSubscription:(NSNotification *)notification;
#endif

#pragma mark - Navigation management
- (void)readIssue:(BakerIssue *)issue;
- (void)handleReadIssue:(NSNotification *)notification;
- (void)receiveBookProtocolNotification:(NSNotification *)notification;
- (void)handleBookToBeProcessed;
- (void)pushViewControllerWithBook:(BakerBook *)book;

#pragma mark - Buttons management
-(void)setrefreshButtonEnabled:(BOOL)enabled;
-(void)setSubscribeButtonEnabled:(BOOL)enabled;

#pragma mark - Helper methods
+ (int)getBannerHeight;

@end
