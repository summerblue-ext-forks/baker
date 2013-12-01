

/*
 |--------------------------------------------------------------------------
 | 书架里的每一个杂志的 View 管理器, 一本杂志对应一个 IssueViewController.
 | 视觉元素的构建, 相应用户事件, 用户点击下载, 用户点击 archive, 下载进度条...
 |--------------------------------------------------------------------------
 |
 */

#import <UIKit/UIKit.h>
#import "BakerIssue.h"
#import "PurchasesManager.h"

@interface IssueViewController : UIViewController {
    NSString *currentAction;
    BOOL purchaseDelayed;
    #ifdef BAKER_NEWSSTAND
    PurchasesManager *purchasesManager;
    #endif
}

@property (strong, nonatomic) BakerIssue *issue;
@property (strong, nonatomic) UIButton *actionButton;
@property (strong, nonatomic) UIButton *archiveButton;
@property (strong, nonatomic) UIProgressView *progressBar;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UILabel *loadingLabel;
@property (strong, nonatomic) UILabel *priceLabel;

@property (strong, nonatomic) UIButton *issueCover;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *infoLabel;

@property (copy, nonatomic) NSString *currentStatus;

#pragma mark - Structs
typedef struct {
    int cellPadding;
    int thumbWidth;
    int thumbHeight;
    int contentOffset;
} UI;

#pragma mark - Init
- (id)initWithBakerIssue:(BakerIssue *)bakerIssue;

#pragma mark - View Lifecycle
- (void)refresh;
- (void)refresh:(NSString *)status;
- (void)refreshContentWithCache:(bool)cache;
- (void)preferredContentSizeChanged:(NSNotification *)notification;

#pragma mark - Issue management
- (void)actionButtonPressed:(UIButton *)sender;
- (void)download;
- (void)setPrice:(NSString *)price;
- (void)buy;
- (void)read;

#pragma mark - Newsstand archive management
- (void)archiveButtonPressed:(UIButton *)sender;

#pragma mark - Helper methods
+ (UI)getIssueContentMeasures;
+ (int)getIssueCellHeight;
+ (CGSize)getIssueCellSize;

@end

@interface alertView: UIAlertView <UIActionSheetDelegate> {

}
@end
