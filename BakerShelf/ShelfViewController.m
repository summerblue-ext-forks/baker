

/*
 |--------------------------------------------------------------------------
 | App 的 rootViewController , 书架列表
 |--------------------------------------------------------------------------
 |
 */


#import "ShelfViewController.h"
#import "UICustomNavigationBar.h"
#import "Constants.h"

#import "BakerViewController.h"
#import "IssueViewController.h"

#import "NSData+Base64.h"
#import "NSString+Extensions.h"
#import "Utils.h"

@implementation ShelfViewController

@synthesize issues;
@synthesize issueViewControllers;
@synthesize gridView;
@synthesize subscribeButton;
@synthesize refreshButton;
@synthesize shelfStatus;
@synthesize subscriptionsActionSheet;
@synthesize supportedOrientation;
@synthesize blockingProgressView;
@synthesize bookToBeProcessed;

#pragma mark - Init

- (id)init {
    self = [super init];
    
    if (self)
    {
        // 实例化内购买控制器, 注册消息通知
        purchasesManager = [PurchasesManager sharedInstance];
        [self addPurchaseObserver:@selector(handleProductsRetrieved:) name:@"notification_products_retrieved"];
        [self addPurchaseObserver:@selector(handleProductsRequestFailed:) name:@"notification_products_request_failed"];
        [self addPurchaseObserver:@selector(handleSubscriptionPurchased:) name:@"notification_subscription_purchased"];
        [self addPurchaseObserver:@selector(handleSubscriptionFailed:) name:@"notification_subscription_failed"];
        [self addPurchaseObserver:@selector(handleSubscriptionRestored:) name:@"notification_subscription_restored"];
        [self addPurchaseObserver:@selector(handleRestoreFailed:) name:@"notification_restore_failed"];
        [self addPurchaseObserver:@selector(handleMultipleRestores:) name:@"notification_multiple_restores"];
        [self addPurchaseObserver:@selector(handleRestoredIssueNotRecognised:) name:@"notification_restored_issue_not_recognised"];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(receiveBookProtocolNotification:)
                                                     name:@"notification_book_protocol"
                                                   object:nil];
        
        [[SKPaymentQueue defaultQueue] addTransactionObserver:purchasesManager];

        // 初始化 API 请求的接口
        api = [BakerAPI sharedInstance];
        issuesManager = [IssuesManager sharedInstance];
        notRecognisedTransactions = [[NSMutableArray alloc] init];

        self.shelfStatus = [[ShelfStatus alloc] init];
        self.issueViewControllers = [[NSMutableArray alloc] init];
        self.supportedOrientation = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
        self.bookToBeProcessed = nil;

        [self handleRefresh:nil];
    }
    return self;
}

- (id)initWithBooks:(NSArray *)currentBooks
{
    self = [self init];
    if (self) {
        self.issues = currentBooks;

        NSMutableArray *controllers = [NSMutableArray array];
        for (BakerIssue *issue in self.issues) {
            IssueViewController *controller = [self createIssueViewControllerWithIssue:issue];
            [controllers addObject:controller];
        }
        self.issueViewControllers = [NSMutableArray arrayWithArray:controllers];
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationItem.title = NSLocalizedString(@"SHELF_NAVIGATION_TITLE", nil);

    self.background = [[UIImageView alloc] init];

    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[[UICollectionViewFlowLayout alloc] init]];
    self.gridView.dataSource = self;
    self.gridView.delegate = self;
    self.gridView.backgroundColor = [UIColor clearColor];
    [self.gridView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cellIdentifier"];

    [self.view addSubview:self.background];
    [self.view addSubview:self.gridView];

    [self willRotateToInterfaceOrientation:self.interfaceOrientation duration:0];
    [self.gridView reloadData];
    
    self.refreshButton = [[UIBarButtonItem alloc]
                          initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                          target:self
                          action:@selector(handleRefresh:)];

    self.subscribeButton = [[UIBarButtonItem alloc]
                             initWithTitle: NSLocalizedString(@"SUBSCRIBE_BUTTON_TEXT", nil)
                             style:UIBarButtonItemStylePlain
                             target:self
                             action:@selector(handleSubscribeButtonPressed:)];

    self.blockingProgressView = [[UIAlertView alloc]
                                 initWithTitle:@"Processing..."
                                 message:@"\n"
                                 delegate:nil
                                 cancelButtonTitle:nil
                                 otherButtonTitles:nil];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(139.5, 75.5); // .5 so it doesn't blur
    [self.blockingProgressView addSubview:spinner];
    [spinner startAnimating];

    NSMutableSet *subscriptions = [NSMutableSet setWithArray:@[]];
    if ([FREE_SUBSCRIPTION_PRODUCT_ID length] > 0 && ![purchasesManager isPurchased:FREE_SUBSCRIPTION_PRODUCT_ID]) {
        [subscriptions addObject:FREE_SUBSCRIPTION_PRODUCT_ID];
    }
    [purchasesManager retrievePricesFor:subscriptions andEnableFailureNotifications:NO];
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController.navigationBar setTranslucent:NO];
    [self willRotateToInterfaceOrientation:self.interfaceOrientation duration:0];

    for (IssueViewController *controller in self.issueViewControllers) {
        controller.issue.transientStatus = BakerIssueTransientStatusNone;
        [controller refresh];
    }

    NSMutableArray *buttonItems = [NSMutableArray arrayWithObject:self.refreshButton];
    if ([purchasesManager hasSubscriptions] || [issuesManager hasProductIDs]) {
        [buttonItems addObject:self.subscribeButton];
    }
    self.navigationItem.leftBarButtonItems = buttonItems;
    
    UIBarButtonItem *infoButton = [[UIBarButtonItem alloc]
                                    initWithTitle: NSLocalizedString(@"INFO_BUTTON_TEXT", nil)
                                    style:UIBarButtonItemStylePlain
                                    target:self
                                    action:@selector(handleInfoButtonPressed:)];

    // Remove file info.html if you don't want the info button to be added to the shelf navigation bar
    NSString *infoPath = [[NSBundle mainBundle] pathForResource:@"info" ofType:@"html" inDirectory:@"info"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:infoPath]) {
        self.navigationItem.rightBarButtonItem = infoButton;
    }
}
- (void)viewDidAppear:(BOOL)animated
{
    if (self.bookToBeProcessed) {
        [self handleBookToBeProcessed];
    }
}
- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return [supportedOrientation indexOfObject:[NSString stringFromInterfaceOrientation:interfaceOrientation]] != NSNotFound;
}
- (BOOL)shouldAutorotate
{
    return YES;
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    int width  = 0;
    int height = 0;

    NSString *image = @"";
    CGSize size = [UIScreen mainScreen].bounds.size;
    int landscapePadding = 0;

    if (UIInterfaceOrientationIsPortrait(toInterfaceOrientation)) {
        width  = size.width;
        height = size.height - 64;
        image  = @"shelf-bg-portrait";
    } else if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
        width  = size.height;
        height = size.width - 64;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            height = height + 12;
        }
        image  = @"shelf-bg-landscape";
        CGFloat cellWidth = [IssueViewController getIssueCellSize].width;
        landscapePadding = width / 4 - cellWidth / 2;
    }

    // 兼容
    if (size.height == 568) {
        image = [NSString stringWithFormat:@"%@-568h", image];
    } else {
        image = [NSString stringWithFormat:@"%@", image];
    }

    int bannerHeight = [ShelfViewController getBannerHeight];

    self.background.frame = CGRectMake(0, 0, width, height);
    self.background.image = [UIImage imageNamed:image];

    self.gridView.frame = CGRectMake(landscapePadding, bannerHeight, width - 2 * landscapePadding, height - bannerHeight);
}
- (IssueViewController *)createIssueViewControllerWithIssue:(BakerIssue *)issue
{
    IssueViewController *controller = [[IssueViewController alloc] initWithBakerIssue:issue];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleReadIssue:) name:@"read_issue_request" object:controller];
    return controller;
}

#pragma mark - Shelf data source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [issueViewControllers count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize cellSize = [IssueViewController getIssueCellSize];
    CGRect cellFrame = CGRectMake(0, 0, cellSize.width, cellSize.height);

    static NSString *cellIdentifier = @"cellIdentifier";
    UICollectionViewCell* cell = [self.gridView dequeueReusableCellWithReuseIdentifier:cellIdentifier forIndexPath:indexPath];
	if (cell == nil)
	{
		UICollectionViewCell* cell = [[UICollectionViewCell alloc] initWithFrame:cellFrame];

        cell.contentView.backgroundColor = [UIColor clearColor];
        cell.backgroundColor = [UIColor clearColor];
	}

    IssueViewController *controller = (self.issueViewControllers)[indexPath.row];
    UIView *removableIssueView = [cell.contentView viewWithTag:42];
    if (removableIssueView) {
        [removableIssueView removeFromSuperview];
    }
    [cell.contentView addSubview:controller.view];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [IssueViewController getIssueCellSize];
}

- (void)handleRefresh:(NSNotification *)notification {
    [self setrefreshButtonEnabled:NO];

    [issuesManager refresh:^(BOOL status) {
        if(status) {
            self.issues = issuesManager.issues;

            [shelfStatus load];
            for (BakerIssue *issue in self.issues) {
                issue.price = [shelfStatus priceFor:issue.productID];
            }

            void (^updateIssues)() = ^{
                // Step 1: remove controllers for issues that no longer exist
                __weak NSMutableArray *discardedControllers = [NSMutableArray array];
                [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    IssueViewController *ivc = (IssueViewController *)obj;

                    if (![self bakerIssueWithID:ivc.issue.ID]) {
                        [discardedControllers addObject:ivc];
                        [self.gridView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:idx inSection:0]]];
                    }
                }];
                [self.issueViewControllers removeObjectsInArray:discardedControllers];

                // Step 2: add controllers for issues that did not yet exist (and refresh the ones that do exist)
                [self.issues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    // NOTE: this block changes the issueViewController array while looping
                    BakerIssue *issue = (BakerIssue *)obj;

                    IssueViewController *existingIvc = [self issueViewControllerWithID:issue.ID];

                    if (existingIvc) {
                        existingIvc.issue = issue;
                    } else {
                        IssueViewController *newIvc = [self createIssueViewControllerWithIssue:issue];
                        [self.issueViewControllers insertObject:newIvc atIndex:idx];
                        [self.gridView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:idx inSection:0]] ];
                    }
                }];

                [self.gridView reloadData];
            };

            // When first launched, the grid is not initialised, so we can't
            // call in the "batch update" method of the grid view
            if (self.gridView) {
                [self.gridView performBatchUpdates:updateIssues completion:nil];
            }
            else {
                updateIssues();
            }

            [purchasesManager retrievePurchasesFor:[issuesManager productIDs] withCallback:^(NSDictionary *purchases) {
                // List of purchases has been returned, so we can refresh all issues
                [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    [(IssueViewController *)obj refreshContentWithCache:NO];
                }];
                [self setrefreshButtonEnabled:YES];
            }];

            [purchasesManager retrievePricesFor:issuesManager.productIDs andEnableFailureNotifications:NO];
        } else {
            [Utils showAlertWithTitle:NSLocalizedString(@"INTERNET_CONNECTION_UNAVAILABLE_TITLE", nil)
                              message:NSLocalizedString(@"INTERNET_CONNECTION_UNAVAILABLE_MESSAGE", nil)
                          buttonTitle:NSLocalizedString(@"INTERNET_CONNECTION_UNAVAILABLE_CLOSE", nil)];
            [self setrefreshButtonEnabled:YES];
        }
    }];
}

- (IssueViewController *)issueViewControllerWithID:(NSString *)ID {
    __block IssueViewController* foundController = nil;
    [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        IssueViewController *ivc = (IssueViewController *)obj;
        if ([ivc.issue.ID isEqualToString:ID]) {
            foundController = ivc;
            *stop = YES;
        }
    }];
    return foundController;
}

- (BakerIssue *)bakerIssueWithID:(NSString *)ID {
    __block BakerIssue *foundIssue = nil;
    [self.issues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BakerIssue *issue = (BakerIssue *)obj;
        if ([issue.ID isEqualToString:ID]) {
            foundIssue = issue;
            *stop = YES;
        }
    }];
    return foundIssue;
}

#pragma mark - Store Kit
- (void)handleSubscribeButtonPressed:(NSNotification *)notification {
    if (subscriptionsActionSheet.visible) {
        [subscriptionsActionSheet dismissWithClickedButtonIndex:(subscriptionsActionSheet.numberOfButtons - 1) animated:YES];
    } else {
        self.subscriptionsActionSheet = [self buildSubscriptionsActionSheet];
        [subscriptionsActionSheet showFromBarButtonItem:self.subscribeButton animated:YES];
    }
}

- (UIActionSheet *)buildSubscriptionsActionSheet {
    NSString *title;
    if ([api canGetPurchasesJSON]) {
        if (purchasesManager.subscribed) {
            title = NSLocalizedString(@"SUBSCRIPTIONS_SHEET_SUBSCRIBED", nil);
        } else {
            title = NSLocalizedString(@"SUBSCRIPTIONS_SHEET_NOT_SUBSCRIBED", nil);
        }
    } else {
        title = NSLocalizedString(@"SUBSCRIPTIONS_SHEET_GENERIC", nil);
    }

    UIActionSheet *sheet = [[UIActionSheet alloc]initWithTitle:title
                                                      delegate:self
                                             cancelButtonTitle:nil
                                        destructiveButtonTitle:nil
                                             otherButtonTitles: nil];
    NSMutableArray *actions = [NSMutableArray array];

    if (!purchasesManager.subscribed) {
        if ([FREE_SUBSCRIPTION_PRODUCT_ID length] > 0 && ![purchasesManager isPurchased:FREE_SUBSCRIPTION_PRODUCT_ID]) {
            [sheet addButtonWithTitle:NSLocalizedString(@"SUBSCRIPTIONS_SHEET_FREE", nil)];
            [actions addObject:FREE_SUBSCRIPTION_PRODUCT_ID];
        }

        for (NSString *productId in @[]) {
            NSString *title = NSLocalizedString(productId, nil);
            NSString *price = [purchasesManager priceFor:productId];
            if (price) {
                [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@ %@", title, price]];
                [actions addObject:productId];
            }
        }
    }

    if ([issuesManager hasProductIDs]) {
        [sheet addButtonWithTitle:NSLocalizedString(@"SUBSCRIPTIONS_SHEET_RESTORE", nil)];
        [actions addObject:@"restore"];
    }

    [sheet addButtonWithTitle:NSLocalizedString(@"SUBSCRIPTIONS_SHEET_CLOSE", nil)];
    [actions addObject:@"cancel"];

    self.subscriptionsActionSheetActions = actions;

    sheet.cancelButtonIndex = sheet.numberOfButtons - 1;
    return sheet;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet == subscriptionsActionSheet) {
        NSString *action = (self.subscriptionsActionSheetActions)[buttonIndex];
        if ([action isEqualToString:@"cancel"]) {
            LogBaker(@"Action sheet: cancel");
            [self setSubscribeButtonEnabled:YES];
        } else if ([action isEqualToString:@"restore"]) {
            [self.blockingProgressView show];
            [purchasesManager restore];
            LogBaker(@"Action sheet: restore");
        } else {
            LogBaker(@"Action sheet: %@", action);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerSubscriptionPurchase" object:self]; // -> Baker Analytics Event
            [self setSubscribeButtonEnabled:NO];
            if (![purchasesManager purchase:action]){
                [Utils showAlertWithTitle:NSLocalizedString(@"SUBSCRIPTION_FAILED_TITLE", nil)
                                  message:nil
                              buttonTitle:NSLocalizedString(@"SUBSCRIPTION_FAILED_CLOSE", nil)];
                [self setSubscribeButtonEnabled:YES];
            }
        }
    }
}

- (void)handleRestoreFailed:(NSNotification *)notification {
    NSError *error = (notification.userInfo)[@"error"];
    [Utils showAlertWithTitle:NSLocalizedString(@"RESTORE_FAILED_TITLE", nil)
                      message:[error localizedDescription]
                  buttonTitle:NSLocalizedString(@"RESTORE_FAILED_CLOSE", nil)];

    [self.blockingProgressView dismissWithClickedButtonIndex:0 animated:YES];

}

- (void)handleMultipleRestores:(NSNotification *)notification {
    if ([notRecognisedTransactions count] > 0) {
        NSSet *productIDs = [NSSet setWithArray:[[notRecognisedTransactions valueForKey:@"payment"] valueForKey:@"productIdentifier"]];
        NSString *productsList = [[productIDs allObjects] componentsJoinedByString:@", "];

        [Utils showAlertWithTitle:NSLocalizedString(@"RESTORED_ISSUE_NOT_RECOGNISED_TITLE", nil)
                          message:[NSString stringWithFormat:NSLocalizedString(@"RESTORED_ISSUE_NOT_RECOGNISED_MESSAGE", nil), productsList]
                      buttonTitle:NSLocalizedString(@"RESTORED_ISSUE_NOT_RECOGNISED_CLOSE", nil)];

        for (SKPaymentTransaction *transaction in notRecognisedTransactions) {
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        }
        [notRecognisedTransactions removeAllObjects];
    }

    [self handleRefresh:nil];
    [self.blockingProgressView dismissWithClickedButtonIndex:0 animated:YES];
}

- (void)handleRestoredIssueNotRecognised:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];
    [notRecognisedTransactions addObject:transaction];
}

// TODO: this can probably be removed
- (void)handleSubscription:(NSNotification *)notification {
    [self setSubscribeButtonEnabled:NO];
    [purchasesManager purchase:FREE_SUBSCRIPTION_PRODUCT_ID];
}

- (void)handleSubscriptionPurchased:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    [purchasesManager markAsPurchased:transaction.payment.productIdentifier];
    [self setSubscribeButtonEnabled:YES];

    if ([purchasesManager finishTransaction:transaction]) {
        if (!purchasesManager.subscribed) {
            [Utils showAlertWithTitle:NSLocalizedString(@"SUBSCRIPTION_SUCCESSFUL_TITLE", nil)
                              message:NSLocalizedString(@"SUBSCRIPTION_SUCCESSFUL_MESSAGE", nil)
                          buttonTitle:NSLocalizedString(@"SUBSCRIPTION_SUCCESSFUL_CLOSE", nil)];

            [self handleRefresh:nil];
        }
    } else {
        [Utils showAlertWithTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_TITLE", nil)
                          message:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_MESSAGE", nil)
                      buttonTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_CLOSE", nil)];
    }
}

- (void)handleSubscriptionFailed:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    // Show an error, unless it was the user who cancelled the transaction
    if (transaction.error.code != SKErrorPaymentCancelled) {
        [Utils showAlertWithTitle:NSLocalizedString(@"SUBSCRIPTION_FAILED_TITLE", nil)
                          message:[transaction.error localizedDescription]
                      buttonTitle:NSLocalizedString(@"SUBSCRIPTION_FAILED_CLOSE", nil)];
    }

    [self setSubscribeButtonEnabled:YES];
}

- (void)handleSubscriptionRestored:(NSNotification *)notification {
    SKPaymentTransaction *transaction = (notification.userInfo)[@"transaction"];

    [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

    if (![purchasesManager finishTransaction:transaction]) {
        LogBaker(@"Could not confirm purchase restore with remote server for %@", transaction.payment.productIdentifier);
    }
}

- (void)handleProductsRetrieved:(NSNotification *)notification {
    NSSet *ids = (notification.userInfo)[@"ids"];
    BOOL issuesRetrieved = NO;

    for (NSString *productId in ids) {
        if ([productId isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID]) {
            // ID is for a free subscription
            [self setSubscribeButtonEnabled:YES];
        } else if ([@[] containsObject:productId]) {
            // ID is for an auto-renewable subscription
            [self setSubscribeButtonEnabled:YES];
        } else {
            // ID is for an issue
            issuesRetrieved = YES;
        }
    }

    if (issuesRetrieved) {
        NSString *price;
        for (IssueViewController *controller in self.issueViewControllers) {
            price = [purchasesManager priceFor:controller.issue.productID];
            if (price) {
                [controller setPrice:price];
                [shelfStatus setPrice:price for:controller.issue.productID];
            }
        }
        [shelfStatus save];
    }
}

- (void)handleProductsRequestFailed:(NSNotification *)notification {
    NSError *error = (notification.userInfo)[@"error"];

    [Utils showAlertWithTitle:NSLocalizedString(@"PRODUCTS_REQUEST_FAILED_TITLE", nil)
                      message:[error localizedDescription]
                  buttonTitle:NSLocalizedString(@"PRODUCTS_REQUEST_FAILED_CLOSE", nil)];
}

#pragma mark - Navigation management

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (void)readIssue:(BakerIssue *)issue
{
    BakerBook *book = nil;
    NSString *status = [issue getStatus];

    if ([status isEqual:@"opening"]) {
        book = [[BakerBook alloc] initWithBookPath:issue.path bundled:NO];
        if (book) {
            [self pushViewControllerWithBook:book];
        } else {
            LogBaker(@"[ERROR] Book %@ could not be initialized", issue.ID);
            issue.transientStatus = BakerIssueTransientStatusNone;
            // Let's refresh everything as it's easier. This is an edge case anyway ;)
            for (IssueViewController *controller in issueViewControllers) {
                [controller refresh];
            }
            [Utils showAlertWithTitle:NSLocalizedString(@"ISSUE_OPENING_FAILED_TITLE", nil)
                              message:NSLocalizedString(@"ISSUE_OPENING_FAILED_MESSAGE", nil)
                          buttonTitle:NSLocalizedString(@"ISSUE_OPENING_FAILED_CLOSE", nil)];
        }
    }
}
- (void)handleReadIssue:(NSNotification *)notification
{
    IssueViewController *controller = notification.object;
    [self readIssue:controller.issue];
}
- (void)receiveBookProtocolNotification:(NSNotification *)notification
{
    self.bookToBeProcessed = (notification.userInfo)[@"ID"];
    [self.navigationController popToRootViewControllerAnimated:YES];
}
- (void)handleBookToBeProcessed
{
    for (IssueViewController *issueViewController in self.issueViewControllers) {
        if ([issueViewController.issue.ID isEqualToString:self.bookToBeProcessed]) {
            [issueViewController actionButtonPressed:nil];
            break;
        }
    }

    self.bookToBeProcessed = nil;
}
- (void)pushViewControllerWithBook:(BakerBook *)book
{
    BakerViewController *bakerViewController = [[BakerViewController alloc] initWithBook:book];
    [self.navigationController pushViewController:bakerViewController animated:YES];
}

#pragma mark - Buttons management

-(void)setrefreshButtonEnabled:(BOOL)enabled {
    self.refreshButton.enabled = enabled;
}

-(void)setSubscribeButtonEnabled:(BOOL)enabled {
    self.subscribeButton.enabled = enabled;
    if (enabled) {
        self.subscribeButton.title = NSLocalizedString(@"SUBSCRIBE_BUTTON_TEXT", nil);
    } else {
        self.subscribeButton.title = NSLocalizedString(@"SUBSCRIBE_BUTTON_DISABLED_TEXT", nil);
    }
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    // Inject user_id
    [Utils webView:webView dispatchHTMLEvent:@"init" withParams:@{@"user_id": [BakerAPI UUID],
                                                                @"app_id": [Utils appID]}];
}

- (void)handleInfoButtonPressed:(id)sender {
    
    // Prepare new view
    UIViewController *popoverContent = [[UIViewController alloc] init];
    UIWebView *popoverView = [[UIWebView alloc] init];
    popoverView.backgroundColor = [UIColor blackColor];
    popoverView.delegate = self;
    popoverContent.view = popoverView;
    
    // Load HTML file
    NSString *path = [[NSBundle mainBundle] pathForResource:@"info" ofType:@"html" inDirectory:@"info"];
    [popoverView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:path]]];
    
    
    // On iPhone push the view controller to the navigation
    [self.navigationController pushViewController:popoverContent animated:YES];
    
}

#pragma mark - Helper methods

- (void)addPurchaseObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:purchasesManager];
}

+ (int)getBannerHeight
{
    return 104;
}

@end
