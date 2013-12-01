

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


#import <UIKit/UIKit.h>

@protocol modalWebViewDelegate;

@interface ModalViewController : UIViewController <UIWebViewDelegate>
{
    id <modalWebViewDelegate> __weak delegate;
    NSURL *myUrl;
}

@property (weak, nonatomic) id <modalWebViewDelegate> delegate;
@property (strong, nonatomic) UIWebView *webView;
@property (strong, nonatomic) UIToolbar *toolbar;
@property (strong, nonatomic) UIBarButtonItem *btnGoBack;
@property (strong, nonatomic) UIBarButtonItem *btnGoForward;
@property (strong, nonatomic) UIBarButtonItem *btnReload;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

- (id)initWithUrl:(NSURL *)url;
- (void)dismissAction;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)openInSafari;

@end

@protocol modalWebViewDelegate <NSObject>

- (void)closeModalWebView;
- (void)webView:(UIWebView *)webView setCorrectOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;

@end