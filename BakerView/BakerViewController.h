

/*
 |--------------------------------------------------------------------------
 | 杂志的 View 控制器, 处理用户杂志的阅读.
 |--------------------------------------------------------------------------
 |
 | 文章的加载, 文章的上一页下一页跳转实现, 根据 BookerBook 里 hpub 的属性对 Book 的渲染;
 | 用户查看 Book 时候的交互, 用户点击 Book 里面链接的跳转逻辑处理, 用户触摸动作的识别.
 |
 */

#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import "IndexViewController.h"
#import "ModalViewController.h"
#import "BakerBook.h"
#import "BakerBookStatus.h"


@class Downloader;

@interface BakerViewController : UIViewController <UIWebViewDelegate, UIScrollViewDelegate, MFMailComposeViewControllerDelegate, modalWebViewDelegate> {

    CGRect screenBounds;

    NSArray *supportedOrientation;

    NSString *defaultScreeshotsPath;
    NSString *cachedScreenshotsPath;

    NSString *renderingType;

    NSMutableArray *pages;
    NSMutableArray *toLoad;

    NSMutableArray *pageDetails;
    NSMutableDictionary *attachedScreenshotPortrait;
    NSMutableDictionary *attachedScreenshotLandscape;

    UIImage *backgroundImageLandscape;
    UIImage *backgroundImagePortrait;

    NSString *pageNameFromURL;
    NSString *anchorFromURL;

    int tapNumber;
    int stackedScrollingAnimations;

    BOOL currentPageFirstLoading;
    BOOL currentPageIsDelayingLoading;
    BOOL currentPageHasChanged;
    BOOL currentPageIsLocked;
    BOOL currentPageWillAppearUnderModal;

    BOOL userIsScrolling;
    BOOL shouldPropagateInterceptedTouch;
    BOOL shouldForceOrientationUpdate;

    BOOL adjustViewsOnAppDidBecomeActive;

    UIScrollView *scrollView;
    UIWebView *prevPage;
    UIWebView *currPage;
    UIWebView *nextPage;

    UIColor *webViewBackground;

    CGRect upTapArea;
    CGRect downTapArea;
    CGRect leftTapArea;
    CGRect rightTapArea;

    int totalPages;
    int lastPageNumber;
    int currentPageNumber;

    int pageWidth;
    int pageHeight;
    int currentPageHeight;

    NSString *URLDownload;
    Downloader *downloader;
    UIAlertView *feedbackAlert;

    IndexViewController *indexViewController;
    ModalViewController *myModalViewController;

    BakerBookStatus *bookStatus;
}

#pragma mark - PROPERTIES
@property (strong, nonatomic) BakerBook *book;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIWebView *currPage;

@property int currentPageNumber;
@property BOOL barsHidden;

#pragma mark - INIT
- (id)initWithBook:(BakerBook *)bakerBook;
- (BOOL)loadBookWithBookPath:(NSString *)bookPath;
- (void)cleanupBookEnvironment;
- (void)resetPageSlots;
- (void)resetPageDetails;
- (void)buildPageArray;
- (void)startReading;
- (void)buildPageDetails;
- (void)setImageFor:(UIImageView *)view;
- (void)updateBookLayout;
- (void)adjustScrollViewPosition;
- (void)setPageSize:(NSString *)orientation;
- (void)setTappableAreaSize;
- (void)showPageDetails;
- (void)setFrame:(CGRect)frame forPage:(UIWebView *)page;
- (void)setupWebView:(UIWebView *)webView;
- (void)removeWebViewDoubleTapGestureRecognizer:(UIView *)view;

#pragma mark - LOADING
- (BOOL)changePage:(int)page;
- (void)gotoPageDelayer;
- (void)gotoPage;
- (void)lockPage:(NSNumber *)lock;
- (void)addPageLoading:(int)slot;
- (void)handlePageLoading;
- (void)loadSlot:(int)slot withPage:(int)page;
- (BOOL)loadWebView:(UIWebView *)webview withPage:(int)page;

#pragma mark - MODAL WEBVIEW
- (void)loadModalWebView:(NSURL *)url;
- (void)closeModalWebView;

#pragma mark - SCROLLVIEW
- (CGRect)frameForPage:(int)page;

#pragma mark - WEBVIEW
- (void)webView:(UIWebView *)webView hidden:(BOOL)status animating:(BOOL)animating;
- (void)webViewDidAppear:(UIWebView *)webView animating:(BOOL)animating;
- (void)webView:(UIWebView *)webView setCorrectOrientation:(UIInterfaceOrientation)interfaceOrientation;

#pragma mark - SCREENSHOTS
- (void)removeScreenshots;
- (void)updateScreenshots;
- (BOOL)checkScreeshotForPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation;
- (void)takeScreenshotFromView:(UIWebView *)webView forPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation;
- (void)placeScreenshotForView:(UIWebView *)webView andPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation;

#pragma mark - GESTURES
- (void)handleInterceptedTouch:(NSNotification *)notification;
- (void)userDidTap:(UITouch *)touch;
- (void)userDidScroll:(UITouch *)touch;

#pragma mark - PAGE SCROLLING
- (void)setCurrentPageHeight;
- (int)getCurrentPageOffset;
- (void)scrollUpCurrentPage:(int)offset animating:(BOOL)animating;
- (void)scrollDownCurrentPage:(int)offset animating:(BOOL)animating;
- (void)scrollPage:(UIWebView *)webView to:(NSString *)offset animating:(BOOL)animating;
- (void)handleAnchor:(BOOL)animating;

#pragma mark - BARS VISIBILITY
- (CGRect)getNewNavigationFrame:(BOOL)hidden;
- (void)toggleBars;
- (void)showBars;
- (void)showNavigationBar;
- (void)hideBars:(NSNumber *)animated;
- (void)handleBookProtocol:(NSURL *)url;

#pragma mark - ORIENTATION
- (NSString *)getCurrentInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;

#pragma mark - INDEX VIEW
- (BOOL)isIndexView:(UIWebView *)webView;

@end
