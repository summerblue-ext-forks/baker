

/*
 |--------------------------------------------------------------------------
 | 内建浏览器, 提高用户体验, 不会让用户感觉跳来跳去的.
 |--------------------------------------------------------------------------
 |
 | 加载的是 hpub 包里面 index.html 文件.
 | 用户在查看文章的时候双击就会调出此视图.
 |
 |
 |
 | 使用方法: 
 |
 |
 |   In the header (.h), add to @interface:

    ModalViewController *modal;


 |  In the controller (.m) use this function:

    - (void)loadModalWebView:(NSURL *) url {
        // initialize
        myModalViewController = [[[ModalViewController alloc] initWithUrl:url] autorelease];
        myModalViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        myModalViewController.delegate = self;
        
        // hide the IndexView before opening modal web view
        [self hideStatusBar];
        
        // check if iOS4 or 5
        if ([self respondsToSelector:@selector(presentViewController:animated:completion:)])
        {
            // iOS 5
            [self presentViewController:myModalViewController animated:YES completion:nil];
        }
        else
        {
            // iOS 4
            [self presentModalViewController:myModalViewController animated:YES];
        }
        
    }
 

 |
 */



#import "ModalViewController.h"
#import "UIColor+Extensions.h"
#import "UIConstants.h"
#import "Utils.h"

#import "Constants.h"

@implementation ModalViewController

@synthesize delegate;
@synthesize webView;
@synthesize toolbar;
@synthesize btnGoBack;
@synthesize btnGoForward;
@synthesize btnReload;
@synthesize spinner;

#pragma mark - INIT
- (id)initWithUrl:(NSURL *)url {
    /****************************************************************************************************
     * This is the main way you'll be using this object.
     * Just create the object and call this function.
     */

    self = [super init];
    if (self) {
        myUrl = url;
    }
    return self;
}

#pragma mark - VIEW LIFECYCLE
- (void)loadView {
    /****************************************************************************************************
     * Creates the UI: buttons, toolbar, webview and container view.
     */

    [super loadView];


    // ****** Buttons
    UIBarButtonItem *btnClose  = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"WEB_MODAL_CLOSE_BUTTON_TEXT", nil)
                                                                   style:UIBarButtonItemStyleBordered
                                                                  target:self
                                                                  action:@selector(dismissAction)];

    UIBarButtonItem *btnAction = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openInSafari)];

    self.btnGoBack = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    btnGoBack.enabled = NO;
    btnGoBack.width = 30;

    self.btnGoForward = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"forward"] style:UIBarButtonItemStylePlain target:self action:@selector(goForward)];
    btnGoForward.enabled = NO;
    btnGoForward.width = 30;

    self.btnReload = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadPage)];
    btnReload.enabled = NO;
    btnGoForward.width = 30;

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        btnClose.tintColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];
        btnAction.tintColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];
        btnGoBack.tintColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];
        btnGoForward.tintColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];
        btnReload.tintColor = [UIColor colorWithHexString:ISSUES_ACTION_BUTTON_BACKGROUND_COLOR];
    }

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    spinner.frame = CGRectMake(3, 3, 25, 25);
    spinner.hidesWhenStopped = YES;

    [spinner startAnimating];

    UIBarButtonItem *btnSpinner = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    btnSpinner.width = 30;

    UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    // ****** Add Toolbar
    self.toolbar = [UIToolbar new];
    toolbar.barStyle = UIBarStyleDefault;


    // ****** Add items to toolbar
    NSArray *items = @[btnClose, btnGoBack, btnGoForward, btnReload, btnSpinner, spacer, btnAction];
    [toolbar setItems:items animated:NO];


    // ****** Add WebView
    self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 44, 1, 1)];
    webView.backgroundColor = [UIColor underPageBackgroundColor];
    webView.contentMode = UIViewContentModeScaleToFill;
    webView.scalesPageToFit = YES;
    webView.delegate = self;


    // ****** View
    self.view = [UIView new];


    // ****** Attach
    [self.view addSubview:toolbar];
    [self.view addSubview:webView];


    // ****** Set views starting frames according to current interface rotation
    [self willRotateToInterfaceOrientation:self.interfaceOrientation duration:0];
}
- (void)viewDidLoad {

    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    [webView loadRequest:[NSURLRequest requestWithURL:myUrl]];
}
- (void)dealloc {

    [self.webView stopLoading];
    [self.webView removeFromSuperview];
    self.webView.delegate = nil;




}
- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - WEBVIEW
- (void)webViewDidStartLoad:(UIWebView *)webViewIn {
    /****************************************************************************************************
     * Start loading a new page in the UIWebView.
     */

    // LogBaker(@"[Modal] Loading '%@'", [webViewIn.request.URL absoluteString]); <-- this isn't returning the URL correctly, check
    [spinner startAnimating];
}
- (void)webViewDidFinishLoad:(UIWebView *)webViewIn {
    /****************************************************************************************************
     * Triggered when the WebView finish.
     * We reset the button status here.
     */

    //LogBaker(@"[Modal] Finish loading.");
    [[self delegate] webView:webViewIn setCorrectOrientation:self.interfaceOrientation];

    // ****** Stop spinner
    [spinner stopAnimating];

    // ****** Update buttons
    btnGoBack.enabled    = [webViewIn canGoBack];
    btnGoForward.enabled = [webViewIn canGoForward];
    btnReload.enabled = YES;
}
- (void)webView:(UIWebView *)webViewIn didFailLoadWithError:(NSError *)error {
    LogBaker(@"[Modal] Failed to load '%@', error code %i", [webViewIn.request.URL absoluteString], [error code]);
    if ([error code] == -1009) {
        UILabel *errorLabel = [[UILabel alloc] initWithFrame:self.webView.frame];
        errorLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        errorLabel.textAlignment = NSTextAlignmentCenter;
        errorLabel.textColor = [UIColor grayColor];
        errorLabel.text = NSLocalizedString(@"WEB_MODAL_FAILURE_MESSAGE", nil);
        errorLabel.numberOfLines = 1;

        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        if (screenBounds.size.width < 768) {
            errorLabel.font = [UIFont fontWithName:@"Helvetica" size:14.0];
        } else {
            errorLabel.font = [UIFont fontWithName:@"Helvetica" size:18.0];
        }

        [self.view addSubview:errorLabel];
    }

    // ****** Stop spinner
    [spinner stopAnimating];
}

#pragma mark - ACTIONS
- (void)dismissAction {
    /****************************************************************************************************
     * Close action, it calls the delegate object to unload itself.
     */

    [[self delegate] closeModalWebView];
}
- (void)goBack {
    /****************************************************************************************************
     * WebView back button.
     */

    [webView goBack];
}
- (void)goForward {
    /****************************************************************************************************
     * WebView forward button.
     */

    [webView goForward];
}
- (void)reloadPage {
    /****************************************************************************************************
     * WebView reload button.
     */
    
    [webView reload];
}
- (void)openInSafari {
    /****************************************************************************************************
     * Open in Safari.
     * In the future this will trigger the panel to choose between different actions.
     */

    [[UIApplication sharedApplication] openURL:webView.request.URL];
}

#pragma mark - ORIENTATION
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    /****************************************************************************************************
     * We'll use our delegate object to check if we can autorotate or not.
     */

    return [[self delegate] shouldAutorotateToInterfaceOrientation:orientation];
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    uint screenWidth  = 0;
    uint screenHeight = 0;

    if (UIInterfaceOrientationIsPortrait(toInterfaceOrientation))
    {
        screenWidth  = [[UIScreen mainScreen] bounds].size.width;
        screenHeight = [[UIScreen mainScreen] bounds].size.height;
    }
    else if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation))
    {
        screenWidth  = [[UIScreen mainScreen] bounds].size.height;
        screenHeight = [[UIScreen mainScreen] bounds].size.width;
    }

    self.view.frame = CGRectMake(0, 0, screenWidth, screenHeight);
    toolbar.frame = CGRectMake(0, 0, screenWidth, 44);
    webView.frame = CGRectMake(0, 44, screenWidth, screenHeight - 44);

    [[self delegate] webView:webView setCorrectOrientation:toInterfaceOrientation];
}

@end
