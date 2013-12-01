

/*
 |--------------------------------------------------------------------------
 | 书架里的每一个杂志的 View 管理器, 一本杂志对应一个 IssueViewController.
 | 视觉元素的构建, 相应用户事件, 用户点击下载, 用户点击 archive, 下载进度条...
 |--------------------------------------------------------------------------
 |
 */

#import <QuartzCore/QuartzCore.h>

#import "IssueViewController.h"
#import "SSZipArchive.h"
#import "UIConstants.h"
#import "PurchasesManager.h"

#import "UIColor+Extensions.h"
#import "Utils.h"

@implementation IssueViewController

#pragma mark - Synthesis

@synthesize issue;
@synthesize actionButton;
@synthesize archiveButton;
@synthesize progressBar;
@synthesize spinner;
@synthesize loadingLabel;
@synthesize priceLabel;

@synthesize issueCover;
@synthesize titleLabel;
@synthesize infoLabel;

@synthesize currentStatus;

#pragma mark - Init

- (id)initWithBakerIssue:(BakerIssue *)bakerIssue
{
    self = [super init];
    if (self) {
        self.issue = bakerIssue;
        self.currentStatus = nil;

        purchaseDelayed = NO;


        purchasesManager = [PurchasesManager sharedInstance];
        [self addPurchaseObserver:@selector(handleIssueRestored:) name:@"notification_issue_restored"];

        // 注册消息通知
        [self addIssueObserver:@selector(handleDownloadStarted:) name:self.issue.notificationDownloadStartedName];
        [self addIssueObserver:@selector(handleDownloadProgressing:) name:self.issue.notificationDownloadProgressingName];
        [self addIssueObserver:@selector(handleDownloadFinished:) name:self.issue.notificationDownloadFinishedName];
        [self addIssueObserver:@selector(handleDownloadError:) name:self.issue.notificationDownloadErrorName];
        [self addIssueObserver:@selector(handleUnzipError:) name:self.issue.notificationUnzipErrorName];

    }
    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    CGSize cellSize = [IssueViewController getIssueCellSize];

    self.view.frame = CGRectMake(0, 0, cellSize.width, cellSize.height);
    self.view.backgroundColor = [UIColor clearColor];
    self.view.tag = 42;

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferredContentSizeChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    }

    UI ui = [IssueViewController getIssueContentMeasures];

    self.issueCover = [UIButton buttonWithType:UIButtonTypeCustom];
    issueCover.frame = CGRectMake(ui.cellPadding, ui.cellPadding, ui.thumbWidth, ui.thumbHeight);

    issueCover.backgroundColor = [UIColor colorWithHexString:ISSUES_COVER_BACKGROUND_COLOR];
    issueCover.adjustsImageWhenHighlighted = NO;
    issueCover.adjustsImageWhenDisabled = NO;

    issueCover.layer.shadowOpacity = 0.5;
    issueCover.layer.shadowOffset = CGSizeMake(0, 2);
    issueCover.layer.shouldRasterize = YES;
    issueCover.layer.rasterizationScale = [UIScreen mainScreen].scale;

    [issueCover addTarget:self action:@selector(actionButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:issueCover];

    // SETUP TITLE LABEL
    self.titleLabel = [[UILabel alloc] init];
    titleLabel.textColor = [UIColor colorWithHexString:ISSUES_TITLE_COLOR];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    titleLabel.textAlignment = NSTextAlignmentLeft;

    [self.view addSubview:titleLabel];

    // SETUP INFO LABEL
    self.infoLabel = [[UILabel alloc] init];
    infoLabel.textColor = [UIColor colorWithHexString:ISSUES_INFO_COLOR];
    infoLabel.backgroundColor = [UIColor clearColor];
    infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    infoLabel.textAlignment = NSTextAlignmentLeft;

    [self.view addSubview:infoLabel];

    // SETUP PRICE LABEL
    self.priceLabel = [[UILabel alloc] init];
    priceLabel.textColor = [UIColor colorWithHexString:ISSUES_PRICE_COLOR];
    priceLabel.backgroundColor = [UIColor clearColor];
    priceLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    priceLabel.textAlignment = NSTextAlignmentLeft;

    [self.view addSubview:priceLabel];

    // SETUP ACTION BUTTON
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    actionButton.backgroundColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];

    [actionButton setTitle:NSLocalizedString(@"ACTION_DOWNLOADED_TEXT", nil) forState:UIControlStateNormal];
    [actionButton setTitleColor:[UIColor colorWithHexString:ISSUES_ACTION_BUTTON_COLOR] forState:UIControlStateNormal];
    [actionButton addTarget:self action:@selector(actionButtonPressed:) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:actionButton];

    // SETUP ARCHIVE BUTTON
    self.archiveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    archiveButton.backgroundColor = [UIColor colorWithHexString:ISSUES_ARCHIVE_BUTTON_BACKGROUND_COLOR];

    [archiveButton setTitle:NSLocalizedString(@"ARCHIVE_TEXT", nil) forState:UIControlStateNormal];
    [archiveButton setTitleColor:[UIColor colorWithHexString:ISSUES_ARCHIVE_BUTTON_COLOR] forState:UIControlStateNormal];

    [archiveButton addTarget:self action:@selector(archiveButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:archiveButton];

    // SETUP DOWN/LOADING SPINNER AND LABEL
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    spinner.color = [UIColor colorWithHexString:ISSUES_LOADING_SPINNER_COLOR];
    spinner.backgroundColor = [UIColor clearColor];
    spinner.hidesWhenStopped = YES;

    self.loadingLabel = [[UILabel alloc] init];
    loadingLabel.textColor = [UIColor colorWithHexString:ISSUES_LOADING_LABEL_COLOR];
    loadingLabel.backgroundColor = [UIColor clearColor];
    loadingLabel.textAlignment = NSTextAlignmentLeft;
    loadingLabel.text = NSLocalizedString(@"DOWNLOADING_TEXT", nil);

    [self.view addSubview:spinner];
    [self.view addSubview:loadingLabel];

    // SETUP PROGRESS BAR
    self.progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressBar.progressTintColor = [UIColor colorWithHexString:ISSUES_PROGRESSBAR_TINT_COLOR];

    [self.view addSubview:progressBar];

    // RESUME PENDING NEWSSTAND DOWNLOAD 断点续传被挂起的下载
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    for (NKAssetDownload *asset in [nkLib downloadingAssets]) {
        if ([asset.issue.name isEqualToString:self.issue.ID]) {
            LogBaker(@"[BakerShelf] Resuming abandoned Newsstand download: %@", asset.issue.name);
            [self.issue downloadWithAsset:asset];
        }
    }

    [self refreshContentWithCache:NO];
}
- (void)refreshContentWithCache:(bool)cache {
    UIFont *titleFont;
    UIFont *infoFont;
    UIFont *actionFont;
    UIFont *archiveFont;

    #if defined(ISSUES_TITLE_FONT) && defined(ISSUES_TITLE_FONT_SIZE)
        titleFont = [UIFont fontWithName:ISSUES_TITLE_FONT size:ISSUES_TITLE_FONT_SIZE];
    #else
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            titleFont = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        } else {
            titleFont = [UIFont fontWithName:@"Helvetica" size:15];
        }
    #endif

    #if defined(ISSUES_INFO_FONT) && defined(ISSUES_INFO_FONT_SIZE)
        infoFont = [UIFont fontWithName:ISSUES_INFO_FONT size:ISSUES_INFO_FONT_SIZE];
    #else
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            infoFont = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        } else {
            infoFont = [UIFont fontWithName:@"Helvetica" size:15];
        }
    #endif

    #if defined(ISSUES_ACTION_BUTTON_FONT) && defined(ISSUES_ACTION_BUTTON_FONT_SIZE)
        actionFont = [UIFont fontWithName:ISSUES_ACTION_BUTTON_FONT size:ISSUES_ACTION_BUTTON_FONT_SIZE];
    #else
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            actionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        } else {
            actionFont = [UIFont fontWithName:@"Helvetica-Bold" size:11];
        }
    #endif

    #if defined(ISSUES_ARCHIVE_BUTTON_FONT) && defined(ISSUES_ARCHIVE_BUTTON_FONT_SIZE)
        archiveFont = [UIFont fontWithName:ISSUES_ARCHIVE_BUTTON_FONT size:ISSUES_ARCHIVE_BUTTON_FONT_SIZE];
    #else
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            archiveFont = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        } else {
            archiveFont = [UIFont fontWithName:@"Helvetica-Bold" size:11];
        }
    #endif

    UI ui = [IssueViewController getIssueContentMeasures];
    int heightOffset = ui.cellPadding;
    uint textLineheight = [@"The brown fox jumps over the lazy dog" sizeWithFont:infoFont constrainedToSize:CGSizeMake(MAXFLOAT, MAXFLOAT)].height;

    // SETUP COVER IMAGE
    [self.issue getCoverWithCache:cache andBlock:^(UIImage *image) {
        [issueCover setBackgroundImage:image forState:UIControlStateNormal];
    }];

    // SETUP TITLE LABEL
    titleLabel.font = titleFont;
    titleLabel.frame = CGRectMake(ui.contentOffset, heightOffset, 170, 60);
    titleLabel.numberOfLines = 3;
    titleLabel.text = self.issue.title;
    [titleLabel sizeToFit];

    heightOffset = heightOffset + titleLabel.frame.size.height + 5;

    // SETUP INFO LABEL
    infoLabel.font = infoFont;
    infoLabel.frame = CGRectMake(ui.contentOffset, heightOffset, 170, 60);
    infoLabel.numberOfLines = 3;
    infoLabel.text = self.issue.info;
    [infoLabel sizeToFit];

    heightOffset = heightOffset + infoLabel.frame.size.height + 5;

    // SETUP PRICE LABEL
    self.priceLabel.frame = CGRectMake(ui.contentOffset, heightOffset, 170, textLineheight);
    priceLabel.font = infoFont;

    heightOffset = heightOffset + priceLabel.frame.size.height + 10;

    // SETUP ACTION BUTTON
    NSString *status = [self.issue getStatus];
    if ([status isEqualToString:@"remote"] || [status isEqualToString:@"purchasable"] || [status isEqualToString:@"purchased"]) {
        actionButton.frame = CGRectMake(ui.contentOffset, heightOffset, 110, 30);
    } else if ([status isEqualToString:@"downloaded"] || [status isEqualToString:@"bundled"]) {
        actionButton.frame = CGRectMake(ui.contentOffset, heightOffset, 80, 30);
    }
    actionButton.titleLabel.font = actionFont;

    // SETUP ARCHIVE BUTTON
    archiveButton.frame = CGRectMake(ui.contentOffset + 80 + 10, heightOffset, 80, 30);
    archiveButton.titleLabel.font = archiveFont;

    // SETUP DOWN/LOADING SPINNER AND LABEL
    spinner.frame = CGRectMake(ui.contentOffset, heightOffset, 30, 30);
    self.loadingLabel.frame = CGRectMake(ui.contentOffset + self.spinner.frame.size.width + 10, heightOffset, 135, 30);
    loadingLabel.font = actionFont;

    heightOffset = heightOffset + self.loadingLabel.frame.size.height + 5;

    // SETUP PROGRESS BAR
    self.progressBar.frame = CGRectMake(ui.contentOffset, heightOffset, 170, 30);
}

- (void)preferredContentSizeChanged:(NSNotification *)notification {
    [self refreshContentWithCache:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refresh];
}
- (void)refresh
{
    [self refresh:[self.issue getStatus]];
}
- (void)refresh:(NSString *)status
{
    
    LogBaker(@"杂志 Cell 视觉状态更新 --> 杂志名称 <%@> 状态从  <%@> 更新为 <%@>", self.issue.ID, self.currentStatus, status);
    
    if ([status isEqualToString:@"remote"])
    {
        LogBaker(@"杂志状态  <%@> 还未下载. ", self.issue.ID);
        
        [self.priceLabel setText:NSLocalizedString(@"FREE_TEXT", nil)];

        [self.actionButton setTitle:NSLocalizedString(@"ACTION_REMOTE_TEXT", nil) forState:UIControlStateNormal];
        [self.spinner stopAnimating];

        self.actionButton.hidden = NO;
        self.archiveButton.hidden = YES;
        self.progressBar.hidden = YES;
        self.loadingLabel.hidden = YES;
        self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"connecting"])
    {
        LogBaker(@"杂志状态  <%@> 连接中... 请稍后! ", self.issue.ID);
        
        [self.spinner startAnimating];

        self.actionButton.hidden = YES;
        self.archiveButton.hidden = YES;
        self.progressBar.progress = 0;
        self.loadingLabel.text = NSLocalizedString(@"CONNECTING_TEXT", nil);
        self.loadingLabel.hidden = NO;
        self.progressBar.hidden = YES;
        self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"downloading"])
    {
        LogBaker(@"杂志状态  <%@> 下载中... 请稍后! ", self.issue.ID);
        [self.spinner startAnimating];

        self.actionButton.hidden = YES;
        self.archiveButton.hidden = YES;
        self.progressBar.progress = 0;
        self.loadingLabel.text = NSLocalizedString(@"DOWNLOADING_TEXT", nil);
        self.loadingLabel.hidden = NO;
        self.progressBar.hidden = NO;
        self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"downloaded"])
    {
        LogBaker(@"杂志状态  <%@> 已经下载到本地, 可提供阅读. ", self.issue.ID);
        [self.actionButton setTitle:NSLocalizedString(@"ACTION_DOWNLOADED_TEXT", nil) forState:UIControlStateNormal];
        [self.spinner stopAnimating];

        self.actionButton.hidden = NO;
        self.archiveButton.hidden = NO;
        self.loadingLabel.hidden = YES;
        self.progressBar.hidden = YES;
        self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"bundled"])
    {
        LogBaker(@"杂志状态  <%@> 还未下载. ", self.issue.ID);
        
        [self.actionButton setTitle:NSLocalizedString(@"ACTION_DOWNLOADED_TEXT", nil) forState:UIControlStateNormal];
        [self.spinner stopAnimating];

        self.actionButton.hidden = NO;
        self.archiveButton.hidden = YES;
        self.loadingLabel.hidden = YES;
        self.progressBar.hidden = YES;
        self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"opening"])
    {
        LogBaker(@"杂志状态  <%@> 打开状态.  ", self.issue.ID);
        
        [self.spinner startAnimating];

        self.actionButton.hidden = YES;
        self.archiveButton.hidden = YES;
        self.loadingLabel.text = NSLocalizedString(@"OPENING_TEXT", nil);
        self.loadingLabel.hidden = NO;
        self.progressBar.hidden = YES;
        self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"purchasable"])
    {
        LogBaker(@"杂志状态  <%@> 可购买. ", self.issue.ID);
        
        [self.actionButton setTitle:NSLocalizedString(@"ACTION_BUY_TEXT", nil) forState:UIControlStateNormal];
        [self.spinner stopAnimating];

        if (self.issue.price) {
            [self.priceLabel setText:self.issue.price];
        }

        self.actionButton.hidden = NO;
        self.archiveButton.hidden = YES;
        self.progressBar.hidden = YES;
        self.loadingLabel.hidden = YES;
        self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"purchasing"])
    {
        LogBaker(@"杂志状态  <%@> 购买中. ", self.issue.ID);
        [self.spinner startAnimating];

        self.loadingLabel.text = NSLocalizedString(@"BUYING_TEXT", nil);

        self.actionButton.hidden = YES;
        self.archiveButton.hidden = YES;
        self.progressBar.hidden = YES;
        self.loadingLabel.hidden = NO;
        self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"purchased"])
    {
        LogBaker(@"杂志状态  <%@> 已经购买过了. ", self.issue.ID);
        [self.priceLabel setText:NSLocalizedString(@"PURCHASED_TEXT", nil)];

        [self.actionButton setTitle:NSLocalizedString(@"ACTION_REMOTE_TEXT", nil) forState:UIControlStateNormal];
        [self.spinner stopAnimating];

        self.actionButton.hidden = NO;
        self.archiveButton.hidden = YES;
        self.progressBar.hidden = YES;
        self.loadingLabel.hidden = YES;
        self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"unpriced"])
    {
        LogBaker(@"杂志状态  <%@> 未标价. ", self.issue.ID);
        
        [self.spinner startAnimating];

        self.loadingLabel.text = NSLocalizedString(@"RETRIEVING_TEXT", nil);

        self.actionButton.hidden = YES;
        self.archiveButton.hidden = YES;
        self.progressBar.hidden = YES;
        self.loadingLabel.hidden = NO;
        self.priceLabel.hidden = YES;
    }

    [self refreshContentWithCache:YES];

    self.currentStatus = status;
}

#pragma mark - Issue management

- (void)actionButtonPressed:(UIButton *)sender
{
    NSString *status = [self.issue getStatus];
    if ([status isEqualToString:@"remote"] || [status isEqualToString:@"purchased"])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueDownload" object:self]; // -> Baker Analytics Event
        [self download];
    }
    else if ([status isEqualToString:@"downloaded"] || [status isEqualToString:@"bundled"])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueOpen" object:self]; // -> Baker Analytics Event
        [self read];
    }
    else if ([status isEqualToString:@"downloading"])
    {
        // TODO: assuming it is supported by NewsstandKit, implement a "Cancel" operation
    }
    else if ([status isEqualToString:@"purchasable"])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssuePurchase" object:self]; // -> Baker Analytics Event
        [self buy];
    }
}

- (void)download
{
    [self.issue download];
}

#pragma mark - 内购买管理

- (void)buy {
    [self addPurchaseObserver:@selector(handleIssuePurchased:) name:@"notification_issue_purchased"];
    [self addPurchaseObserver:@selector(handleIssuePurchaseFailed:) name:@"notification_issue_purchase_failed"];

    if (![purchasesManager purchase:self.issue.productID]) {
        // Still retrieving SKProduct: delay purchase
        purchaseDelayed = YES;

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        [purchasesManager retrievePriceFor:self.issue.productID];

        self.issue.transientStatus = BakerIssueTransientStatusUnpriced;
        [self refresh];
    } else {
        self.issue.transientStatus = BakerIssueTransientStatusPurchasing;
        [self refresh];
    }
}
- (void)handleIssuePurchased:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

        if ([purchasesManager finishTransaction:transaction]) {
            if (!transaction.originalTransaction) {
                // Do not show alert on restoring a transaction
                [Utils showAlertWithTitle:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_TITLE", nil)
                                  message:[NSString stringWithFormat:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_MESSAGE", nil), self.issue.title]
                              buttonTitle:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_CLOSE", nil)];
            }
        } else {
            [Utils showAlertWithTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_TITLE", nil)
                              message:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_MESSAGE", nil)
                          buttonTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_CLOSE", nil)];
        }

        self.issue.transientStatus = BakerIssueTransientStatusNone;

        [purchasesManager retrievePurchasesFor:[NSSet setWithObject:self.issue.productID] withCallback:^(NSDictionary *purchases) {
            [self refresh];
        }];
    }
}
- (void)handleIssuePurchaseFailed:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {
        // Show an error, unless it was the user who cancelled the transaction
        if (transaction.error.code != SKErrorPaymentCancelled) {
            [Utils showAlertWithTitle:NSLocalizedString(@"ISSUE_PURCHASE_FAILED_TITLE", nil)
                              message:[transaction.error localizedDescription]
                          buttonTitle:NSLocalizedString(@"ISSUE_PURCHASE_FAILED_CLOSE", nil)];
        }

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        self.issue.transientStatus = BakerIssueTransientStatusNone;
        [self refresh];
    }
}

- (void)handleIssueRestored:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {
        [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

        if (![purchasesManager finishTransaction:transaction]) {
            LogBaker(@"[BakerShelf] Could not confirm purchase restore with remote server for %@", transaction.payment.productIdentifier);
        }

        self.issue.transientStatus = BakerIssueTransientStatusNone;
        [self refresh];
    }
}

- (void)setPrice:(NSString *)price {
    self.issue.price = price;
    if (purchaseDelayed) {
        purchaseDelayed = NO;
        [self buy];
    } else {
        [self refresh];
    }
}

- (void)read
{
    self.issue.transientStatus = BakerIssueTransientStatusOpening;
    [self refresh];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"read_issue_request" object:self];
}

#pragma mark - Newsstand download management

- (void)handleDownloadStarted:(NSNotification *)notification
{
    [self refresh];
}
- (void)handleDownloadProgressing:(NSNotification *)notification {
    float bytesWritten = [(notification.userInfo)[@"totalBytesWritten"] floatValue];
    float bytesExpected = [(notification.userInfo)[@"expectedTotalBytes"] floatValue];

    if ([self.currentStatus isEqualToString:@"connecting"])
    {
        self.issue.transientStatus = BakerIssueTransientStatusDownloading;
        [self refresh];
    }
    
    LogBaker(@"下载进行中........... 当前进度 百分之 %f", (bytesWritten / bytesExpected)*100 );
    
    [self.progressBar setProgress:(bytesWritten / bytesExpected) animated:YES];
}
- (void)handleDownloadFinished:(NSNotification *)notification
{
    LogBaker(@"下载完成!!!! ");
    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}
- (void)handleDownloadError:(NSNotification *)notification
{
    LogBaker(@"下载中断, 有错误发生. ");
    [Utils showAlertWithTitle:NSLocalizedString(@"DOWNLOAD_FAILED_TITLE", nil)
                      message:NSLocalizedString(@"DOWNLOAD_FAILED_MESSAGE", nil)
                  buttonTitle:NSLocalizedString(@"DOWNLOAD_FAILED_CLOSE", nil)];

    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}
- (void)handleUnzipError:(NSNotification *)notification
{
    LogBaker(@"解压文件发生错误.");
    [Utils showAlertWithTitle:NSLocalizedString(@"UNZIP_FAILED_TITLE", nil)
                      message:NSLocalizedString(@"UNZIP_FAILED_MESSAGE", nil)
                  buttonTitle:NSLocalizedString(@"UNZIP_FAILED_CLOSE", nil)];

    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}

#pragma mark - Newsstand archive management

- (void)archiveButtonPressed:(UIButton *)sender
{
    UIAlertView *updateAlert = [[UIAlertView alloc]
                                initWithTitle: NSLocalizedString(@"ARCHIVE_ALERT_TITLE", nil)
                                message: NSLocalizedString(@"ARCHIVE_ALERT_MESSAGE", nil)
                                delegate: self
                                cancelButtonTitle: NSLocalizedString(@"ARCHIVE_ALERT_BUTTON_CANCEL", nil)
                                otherButtonTitles: NSLocalizedString(@"ARCHIVE_ALERT_BUTTON_OK", nil), nil];
    [updateAlert show];
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(buttonIndex == 1){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueArchive" object:self]; // -> Baker Analytics Event
        
        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.issue.ID];
        NSString *name = nkIssue.name;
        NSDate *date = nkIssue.date;

        // 先删除, 会清空 Cache
        [nkLib removeIssue:nkIssue];

        // 重新加入
        nkIssue = [nkLib addIssueWithName:name date:date];
        self.issue.path = [[nkIssue contentURL] path];

        [self refresh];
    }
}

#pragma mark - Helper methods

- (void)addPurchaseObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:purchasesManager];
}

- (void)removePurchaseObserver:(NSString *)notificationName {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:notificationName
                                                  object:purchasesManager];
}

- (void)addIssueObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:nil];
}

+ (UI)getIssueContentMeasures
{
    UI iPhone = {
        .cellPadding   = 22,
        .thumbWidth    = 87,
        .thumbHeight   = 116,
        .contentOffset = 128
    };
    return iPhone;
}

+ (int)getIssueCellHeight
{
    return 240;
}
+ (CGSize)getIssueCellSize
{
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    return CGSizeMake(screenRect.size.width - 10, [IssueViewController getIssueCellHeight]);
}

@end
