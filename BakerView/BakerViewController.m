

/*
 |--------------------------------------------------------------------------
 | 杂志的 View 控制器, 处理用户杂志的阅读.
 |--------------------------------------------------------------------------
 |
 | 文章的加载, 文章的上一页下一页跳转实现, 根据 BookerBook 里 hpub 的属性对 Book 的渲染;
 | 用户查看 Book 时候的交互, 用户点击 Book 里面链接的跳转逻辑处理, 用户触摸动作的识别.
 |
 */


#import <QuartzCore/QuartzCore.h>
#import <sys/xattr.h>
#import <AVFoundation/AVFoundation.h>

#import "BakerViewController.h"
#import "SSZipArchive.h"
#import "PageTitleLabel.h"
#import "Utils.h"
#import "Constants.h"

#define INDEX_FILE_NAME         @"index.html"

#define URL_OPEN_MODALLY        @"referrer=Baker"
#define URL_OPEN_EXTERNAL       @"referrer=Safari"


// SCREENSHOT
#define MAX_SCREENSHOT_AFTER_CP  10
#define MAX_SCREENSHOT_BEFORE_CP 10

@implementation BakerViewController

#pragma mark - SYNTHESIS
@synthesize book;
@synthesize scrollView;
@synthesize currPage;
@synthesize currentPageNumber;
@synthesize barsHidden;

#pragma mark - INIT
- (id)initWithBook:(BakerBook *)bakerBook {

    self = [super init];
    if (self) {
        LogBaker(@"[BakerView] Init book view...");
        self.book = bakerBook;

        if ([self respondsToSelector:@selector(automaticallyAdjustsScrollViewInsets)]) {
            // Only available in iOS 7 +
            self.automaticallyAdjustsScrollViewInsets = NO;
        }


        // ****** DEVICE SCREEN BOUNDS
        screenBounds = [[UIScreen mainScreen] bounds];
        LogBaker(@"[BakerView]     Device Screen (WxH): %fx%f.", screenBounds.size.width, screenBounds.size.height);


        // ****** SUPPORTED ORIENTATION FROM PLIST
        supportedOrientation = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];


        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
        }


        // ****** SCREENSHOTS DIRECTORY //TODO: set in load book only if is necessary
        defaultScreeshotsPath = [[cachePath stringByAppendingPathComponent:@"screenshots"] stringByAppendingPathComponent:book.ID];


        // ****** STATUS FILE
        bookStatus = [[BakerBookStatus alloc] initWithBookId:book.ID];
        LogBaker(@"[BakerView]     Status: page %@ @ scrollIndex %@px.", bookStatus.page, bookStatus.scrollIndex);


        // ****** Initialize audio session for html5 audio
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        BOOL ok;
        NSError *setCategoryError = nil;
        ok = [audioSession setCategory:AVAudioSessionCategoryPlayback
                                 error:&setCategoryError];
        if (!ok) {
            LogBaker(@"[BakerView]     AudioSession - %s setCategoryError=%@", __PRETTY_FUNCTION__, setCategoryError);
        }

        // ****** BOOK ENVIRONMENT
        pages  = [NSMutableArray array];
        toLoad = [NSMutableArray array];

        pageDetails = [NSMutableArray array];

        attachedScreenshotPortrait  = [NSMutableDictionary dictionary];
        attachedScreenshotLandscape = [NSMutableDictionary dictionary];

        tapNumber = 0;
        stackedScrollingAnimations = 0; // TODO: CHECK IF STILL USED!

        currentPageFirstLoading = YES;
        currentPageIsDelayingLoading = YES;
        currentPageHasChanged = NO;
        currentPageIsLocked = NO;
        currentPageWillAppearUnderModal = NO;

        userIsScrolling = NO;
        shouldPropagateInterceptedTouch = YES;
        shouldForceOrientationUpdate = YES;

        adjustViewsOnAppDidBecomeActive = NO;
        barsHidden = NO;

        webViewBackground = nil;

        pageNameFromURL = nil;
        anchorFromURL = nil;

        // TODO: LOAD BOOK METHOD IN VIEW DID LOAD
        [self loadBookWithBookPath:book.path];
    }
    return self;
}
- (void)viewDidLoad {

    [super viewDidLoad];
    self.navigationItem.title = book.title;
    
    
    // ****** SET THE INITIAL SIZE FOR EVERYTHING
    // Avoids strange animations when opening
    [self setPageSize:[self getCurrentInterfaceOrientation:self.interfaceOrientation]];


    // ****** SCROLLVIEW INIT
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, pageWidth, pageHeight)];
    scrollView.showsHorizontalScrollIndicator = YES;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.delaysContentTouches = NO;
    scrollView.pagingEnabled = YES;
    scrollView.delegate = self;

    scrollView.scrollEnabled = [book.bakerPageTurnSwipe boolValue];
    scrollView.backgroundColor = [Utils colorWithHexString:book.bakerBackground];

    [self.view addSubview:scrollView];


    // ****** BAKER BACKGROUND
    backgroundImageLandscape   = nil;
    backgroundImagePortrait    = nil;

    NSString *backgroundPathLandscape = book.bakerBackgroundImageLandscape;
    if (backgroundPathLandscape != nil) {
        backgroundPathLandscape  = [book.path stringByAppendingPathComponent:backgroundPathLandscape];
        backgroundImageLandscape = [UIImage imageWithContentsOfFile:backgroundPathLandscape];
    }

    NSString *backgroundPathPortrait = book.bakerBackgroundImagePortrait;
    if (backgroundPathPortrait != nil) {
        backgroundPathPortrait  = [book.path stringByAppendingPathComponent:backgroundPathPortrait];
        backgroundImagePortrait = [UIImage imageWithContentsOfFile:backgroundPathPortrait];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    
    if (!currentPageWillAppearUnderModal) {

        [super viewWillAppear:animated];
        [self.navigationController.navigationBar setTranslucent:YES];

        // Prevent duplicate observers
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"notification_touch_intercepted" object:nil];

        // ****** LISTENER FOR INTERCEPTOR WINDOW NOTIFICATION
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterceptedTouch:) name:@"notification_touch_intercepted" object:nil];

        // ****** Application Will ResignActive 的时候调用, 保存用户的浏览状态 page 和 scrolling-y坐标
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationWillResignActive:) name:@"applicationWillResignActiveNotification" object:nil];

    } else {

        // In case the orientation changed while being in modal view, restore the
        // webview and stuff to the current orientation
        [self willRotateToInterfaceOrientation:self.interfaceOrientation duration:0];
        [self didRotateFromInterfaceOrientation:self.interfaceOrientation];
    }
}

/**
 *  保存当前的状态, page 和 scrolling-y坐标 的信息, 需要保存此信息是因为 HTML 是无状态的.
 *
 */
- (void)handleApplicationWillResignActive:(NSNotification *)notification
{
    LogBaker(@"程序即将进入后台, 不在活跃, 保存状态中..... ");
    [self saveBookStatusWithScrollIndex];
    adjustViewsOnAppDidBecomeActive = YES;
}

- (void)viewDidAppear:(BOOL)animated {

    if (!currentPageWillAppearUnderModal) {

        [super viewDidAppear:animated];

        if (![self forceOrientationUpdate]) {
            [self willRotateToInterfaceOrientation:self.interfaceOrientation duration:0];
            [self performSelector:@selector(hideBars:) withObject:@YES afterDelay:0.5];

            // Condition to make sure we only call startReading the first time this callback is invoked
            // Fixes page reload on coming back from fullscreen video (#611)
            if (currPage == nil) {
                [self startReading];
            }

            [self didRotateFromInterfaceOrientation:self.interfaceOrientation];
        }
    }

    currentPageWillAppearUnderModal = NO;
}

- (void)viewDidLayoutSubviews {
    // UINavigationController likes to mess with subviews when app becomes active
    // viewDidLayoutSubviews is called after UINavigationController is already done,
    // so we can adjust the views
    if (adjustViewsOnAppDidBecomeActive) {
        LogBaker(@"[BakerView] Adjusting views on appDidBecomeActive");
        [self adjustScrollViewPosition];
        if (indexViewController != nil) {
            [indexViewController adjustIndexView];
        }
        adjustViewsOnAppDidBecomeActive = NO;
    }
}

- (BOOL)loadBookWithBookPath:(NSString *)bookPath {
    LogBaker(@"[BakerView] Loading book from path: %@", bookPath);

    // ****** CLEANUP PREVIOUS BOOK
    [self cleanupBookEnvironment];

    // ****** LOAD CONTENTS
    [self buildPageArray];

    // ****** SET STARTING PAGE
    int lastPageViewed = [bookStatus.page intValue];
    int bakerStartAtPage = [book.bakerStartAtPage intValue];
    currentPageNumber = 1;

    if (currentPageFirstLoading && lastPageViewed != 0) {
        currentPageNumber = lastPageViewed;
    } else if (bakerStartAtPage < 0) {
        currentPageNumber = MAX(1, totalPages + bakerStartAtPage + 1);
    } else if (bakerStartAtPage > 0) {
        currentPageNumber = MIN(totalPages, bakerStartAtPage);
    }
    bookStatus.page = @(currentPageNumber);

    // ****** SET SCREENSHOTS FOLDER
    NSString *screenshotFolder = book.bakerPageScreenshots;
    if (screenshotFolder) {
        // When a screenshots folder is specified in book.json
        cachedScreenshotsPath = [bookPath stringByAppendingPathComponent:screenshotFolder];
    }

    if (!screenshotFolder || ![[NSFileManager defaultManager] fileExistsAtPath:cachedScreenshotsPath]) {
        // When a screenshot folder is not specified in book.json, or is specified but not actually existing
        cachedScreenshotsPath = defaultScreeshotsPath;
    }
    LogBaker(@"[BakerView] Screenshots stored at: %@", cachedScreenshotsPath);


    return YES;
}
- (void)cleanupBookEnvironment {

    [self resetPageSlots];
    [self resetPageDetails];

    [pages removeAllObjects];
    [toLoad removeAllObjects];
}
- (void)resetPageSlots {
    //LogBaker(@"[BakerView] Reset leftover page slot");

    if (currPage) {
        [currPage setDelegate:nil];
        [currPage removeFromSuperview];
    }
    if (nextPage) {
        [nextPage setDelegate:nil];
        [nextPage removeFromSuperview];
    }
    if (prevPage) {
        [prevPage setDelegate:nil];
        [prevPage removeFromSuperview];
    }

    currPage = nil;
    nextPage = nil;
    prevPage = nil;
}
- (void)resetPageDetails {
    //LogBaker(@"[BakerView] Reset page details array and empty screenshot directory");

    for (NSMutableDictionary *details in pageDetails) {
        for (NSString *key in details) {
            UIView *value = details[key];
            [value removeFromSuperview];
        }
    }

    [pageDetails removeAllObjects];
}
- (void)buildPageArray {
    for (id page in book.contents) {

        NSString *pageFile = nil;
        if ([page isKindOfClass:[NSString class]]) {
            pageFile = [book.path stringByAppendingPathComponent:page];
        } else if ([page isKindOfClass:[NSDictionary class]]) {
            pageFile = [book.path stringByAppendingPathComponent:page[@"url"]];
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:pageFile]) {
            [pages addObject:pageFile];
        } else {
            LogBaker(@"[BakerView] ERROR: Page %@ does not exist in %@.", page, book.path);
        }
    }

    totalPages = [pages count];
    LogBaker(@"[BakerView]     Pages in this book: %d", totalPages);
}
- (void)startReading {

    //[self setPageSize:[self getCurrentInterfaceOrientation:self.interfaceOrientation]];
    [self buildPageDetails];
    //[self updateBookLayout];

    // ****** INDEX WEBVIEW INIT
    // we move it here to make it more clear and clean

    if (indexViewController != nil) {
        // first of all, we need to clean the indexview if it exists.
        [indexViewController.view removeFromSuperview];
    }
    indexViewController = [[IndexViewController alloc] initWithBook:book fileName:INDEX_FILE_NAME webViewDelegate:self];
    [self.view addSubview:indexViewController.view];
    [indexViewController loadContent];

    currentPageIsDelayingLoading = YES;

    [self addPageLoading:0];

    if ([book.bakerRendering isEqualToString:@"three-cards"]) {
        if (currentPageNumber != totalPages) {
            [self addPageLoading:+1];
        }

        if (currentPageNumber != 1) {
            [self addPageLoading:-1];
        }
    }

    [self handlePageLoading];
}
- (void)buildPageDetails {
    //LogBaker(@"[BakerView] Init page details for the book pages");

    for (int i = 0; i < totalPages; i++) {

        UIColor *foregroundColor = [Utils colorWithHexString:book.bakerPageNumbersColor];


        // ****** Background
        UIImageView *backgroundView = [[UIImageView alloc] initWithFrame:CGRectMake(pageWidth * i, 0, pageWidth, pageHeight)];
        [self setImageFor:backgroundView];
        [scrollView addSubview:backgroundView];


        // ****** Spinners
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        spinner.backgroundColor = [UIColor clearColor];
        spinner.color = foregroundColor;
        spinner.alpha = [book.bakerPageNumbersAlpha floatValue];

        CGRect frame = spinner.frame;
        frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
        frame.origin.y = (pageHeight - frame.size.height) / 2;
        spinner.frame = frame;

        [scrollView addSubview:spinner];
        [spinner startAnimating];


        // ****** Numbers
        UILabel *number = [[UILabel alloc] initWithFrame:CGRectMake(pageWidth * i + (pageWidth - 115) / 2, pageHeight / 2 - 55, 115, 30)];
        number.backgroundColor = [UIColor clearColor];
        number.font = [UIFont fontWithName:@"Helvetica" size:40.0];
        number.textColor = foregroundColor;
        number.textAlignment = NSTextAlignmentCenter;
        number.alpha = [book.bakerPageNumbersAlpha floatValue];

        number.text = [NSString stringWithFormat:@"%d", i + 1];
        if ([book.bakerStartAtPage intValue] < 0) {
            number.text = [NSString stringWithFormat:@"%d", totalPages - i];
        }

        [scrollView addSubview:number];


        // ****** Title
        PageTitleLabel *title = [[PageTitleLabel alloc]initWithFile:pages[i] color:foregroundColor alpha:[book.bakerPageNumbersAlpha floatValue]];
        [title setX:(pageWidth * i + ((pageWidth - title.frame.size.width) / 2)) Y:(pageHeight / 2 + 20)];
        [scrollView addSubview:title];


        // ****** Store instances for later use
        NSMutableDictionary *details = [NSMutableDictionary dictionaryWithObjectsAndKeys:spinner, @"spinner", number, @"number", title, @"title", backgroundView, @"background", nil];
        [pageDetails insertObject:details atIndex:i];
    }
}
- (void)setImageFor:(UIImageView *)view {
    if (pageWidth > pageHeight && backgroundImageLandscape != NULL) {
        // Landscape
        view.image = backgroundImageLandscape;
    } else if (pageWidth < pageHeight && backgroundImagePortrait != NULL) {
        // Portrait
        view.image = backgroundImagePortrait;
    } else {
        view.image = NULL;
    }
}
- (void)updateBookLayout {
    //LogBaker(@"[BakerView]     Prevent page from changing until layout is updated");
    [self lockPage:@YES];
    [self showPageDetails];

    if ([book.bakerRendering isEqualToString:@"screenshots"]) {
        // TODO: BE SURE TO KNOW THE CORRECT CURRENT PAGE!
        [self removeScreenshots];
        [self updateScreenshots];
    }

    [self adjustScrollViewPosition];

    [self setFrame:[self frameForPage:currentPageNumber] forPage:currPage];
    [self setFrame:[self frameForPage:currentPageNumber + 1] forPage:nextPage];
    [self setFrame:[self frameForPage:currentPageNumber - 1] forPage:prevPage];

    [scrollView scrollRectToVisible:[self frameForPage:currentPageNumber] animated:NO];

    //LogBaker(@"[BakerView]     Unlock page changing");
    [self lockPage:@NO];
}
- (void)adjustScrollViewPosition {
    int scrollViewY = 0;
    
    if (SYSTEM_VERSION_LESS_THAN(@"7.0") && !barsHidden) {
        scrollViewY = -20;
    }

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration
                     animations:^{ scrollView.frame = CGRectMake(0, scrollViewY, pageWidth, pageHeight); }
                     completion:^(BOOL finished) {}];
}
- (void)setPageSize:(NSString *)orientation {
    LogBaker(@"[BakerView] Set size for orientation: %@", orientation);

    pageWidth  = screenBounds.size.width;
    pageHeight = screenBounds.size.height;

    if ([orientation isEqualToString:@"landscape"]) {
        pageWidth  = screenBounds.size.height;
        pageHeight = screenBounds.size.width;
    }

    [self setTappableAreaSize];

    scrollView.contentSize = CGSizeMake(pageWidth * totalPages, pageHeight);
}
- (void)setTappableAreaSize {
    //LogBaker(@"[BakerView] Set tappable area size");

    int tappableAreaSize = screenBounds.size.width/16;
    if (screenBounds.size.width < 768) {
        tappableAreaSize = screenBounds.size.width/8;
    }

    upTapArea    = CGRectMake(tappableAreaSize, 0, pageWidth - (tappableAreaSize * 2), tappableAreaSize);
    downTapArea  = CGRectMake(tappableAreaSize, pageHeight - tappableAreaSize, pageWidth - (tappableAreaSize * 2), tappableAreaSize);
    leftTapArea  = CGRectMake(0, tappableAreaSize, tappableAreaSize, pageHeight - (tappableAreaSize * 2));
    rightTapArea = CGRectMake(pageWidth - tappableAreaSize, tappableAreaSize, tappableAreaSize, pageHeight - (tappableAreaSize * 2));
}
- (void)showPageDetails {
    //LogBaker(@"[BakerView] Show page details for the book pages");

    // TODO: IS THIS NEEDED ?
    for (NSMutableDictionary *details in pageDetails) {
        for (NSString *key in details) {
            UIView *value = details[key];
            value.hidden = YES;
        }
    }

    for (int i = 0; i < totalPages; i++) {

        if (pageDetails.count > i && pageDetails[i] != nil) {

            NSDictionary *details = [NSDictionary dictionaryWithDictionary:pageDetails[i]];

            for (NSString *key in details) {
                UIView *value = details[key];
                if (value != nil) {

                    CGRect frame = value.frame;
                    if ([key isEqualToString:@"spinner"]) {

                        frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
                        frame.origin.y = (pageHeight - frame.size.height) / 2;
                        value.frame = frame;
                        value.hidden = NO;

                    } else if ([key isEqualToString:@"number"]) {

                        frame.origin.x = pageWidth * i + (pageWidth - 115) / 2;
                        frame.origin.y = pageHeight / 2 - 55;
                        value.frame = frame;
                        value.hidden = NO;

                    } else if ([key isEqualToString:@"title"]) {

                        frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
                        frame.origin.y = pageHeight / 2 + 20;
                        value.frame = frame;
                        value.hidden = NO;

                    } else if ([key isEqualToString:@"background"]) {

                        [self setImageFor:(UIImageView *)value];

                        frame.origin.x = pageWidth * i;
                        frame.size.width = pageWidth;
                        frame.size.height = pageHeight;
                        value.frame = frame;
                        value.hidden = NO;

                    } else {

                        value.hidden = YES;
                    }
                }
            }
        }
    }
}
- (void)setFrame:(CGRect)frame forPage:(UIWebView *)page {
    if (page && [page.superview isEqual:scrollView]) {
        page.frame = frame;
        [scrollView bringSubviewToFront:page];
    }
}

- (void)setupWebView:(UIWebView *)webView {
    //LogBaker(@"[BakerView] Setup webView");

    if (webViewBackground == nil)
    {
        webViewBackground = webView.backgroundColor;
    }

    webView.backgroundColor = [UIColor clearColor];
    webView.opaque = NO;

    webView.delegate = self;

    webView.mediaPlaybackRequiresUserAction = ![book.bakerMediaAutoplay boolValue];
    webView.scalesPageToFit = [book.zoomable boolValue];
    BOOL verticalBounce = [book.bakerVerticalBounce boolValue];

    for (UIView *subview in webView.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            ((UIScrollView *)subview).bounces = verticalBounce;
        }
    }

    if (!webView.scalesPageToFit) {
        [self removeWebViewDoubleTapGestureRecognizer:webView];
    }
}
- (void)removeWebViewDoubleTapGestureRecognizer:(UIView *)view
{
    for (UIGestureRecognizer *recognizer in [view gestureRecognizers]) {
        if ([recognizer isKindOfClass:[UITapGestureRecognizer class]] && [(UITapGestureRecognizer *)recognizer numberOfTapsRequired] == 2) {
            [view removeGestureRecognizer:recognizer];
        }
    }
    for (UIView *subview in view.subviews) {
        [self removeWebViewDoubleTapGestureRecognizer:subview];
    }
}

#pragma mark - LOADING
- (BOOL)changePage:(int)page {
    //LogBaker(@"[BakerView] Check if page has changed");

    BOOL pageChanged = NO;

    if (page < 1)
    {
        currentPageNumber = 1;
    }
    else if (page > totalPages)
    {
        currentPageNumber = totalPages;
    }
    else if (page != currentPageNumber)
    {
        // While we are tapping, we don't want scrolling event to get in the way
        scrollView.scrollEnabled = NO;
        stackedScrollingAnimations++;

        lastPageNumber = currentPageNumber;
        currentPageNumber = page;

        tapNumber = tapNumber + (lastPageNumber - currentPageNumber);

        [self hideBars:@YES];
        [scrollView scrollRectToVisible:[self frameForPage:currentPageNumber] animated:YES];

        [self gotoPageDelayer];

        pageChanged = YES;
    }
    bookStatus.page = @(currentPageNumber);

    return pageChanged;
}
- (void)gotoPageDelayer {
    // This delay is required in order to avoid stuttering when the animation runs.
    // The animation lasts 0.5 seconds: so we start loading after that.

    if (currentPageIsDelayingLoading) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(gotoPage) object:nil];
    }

    currentPageIsDelayingLoading = YES;
    [self performSelector:@selector(gotoPage) withObject:nil afterDelay:0.5];
}
- (void)gotoPage {

    NSString *path = [NSString stringWithString:pages[currentPageNumber - 1]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] && tapNumber != 0) {

        //LogBaker(@"[BakerView] Goto page -> %@", [[NSFileManager defaultManager] displayNameAtPath:path]);

        if ([book.bakerRendering isEqualToString:@"three-cards"])
        {
            // ****** THREE CARD VIEW METHOD

            // Dispatch blur event on old current page
            [Utils webView:currPage dispatchHTMLEvent:@"blur"];

            // Calculate move direction and normalize tapNumber
            int direction = 1;
            if (tapNumber < 0) {
                direction = -direction;
                tapNumber = -tapNumber;
            }
            LogBaker(@"[BakerView]     Tap number: %d", tapNumber);

            if (tapNumber > 2) {
                tapNumber = 0;

                // Moved away for more than 2 pages: RELOAD ALL pages
                [toLoad removeAllObjects];

                [currPage removeFromSuperview];
                [nextPage removeFromSuperview];
                [prevPage removeFromSuperview];

                [self addPageLoading:0];
                if (currentPageNumber < totalPages)
                    [self addPageLoading:+1];
                if (currentPageNumber > 1)
                    [self addPageLoading:-1];

            } else {

                int tmpSlot = 0;
                if (tapNumber == 2) {

                    // Moved away for 2 pages: RELOAD CURRENT page
                    if (direction < 0) {
                        // Move LEFT <<<
                        [prevPage removeFromSuperview];
                        UIWebView *tmpView = prevPage;
                        prevPage = nextPage;
                        nextPage = tmpView;
                    } else {
                        // Move RIGHT >>>
                        [nextPage removeFromSuperview];
                        UIWebView *tmpView = nextPage;
                        nextPage = prevPage;
                        prevPage = tmpView;
                    }

                    // Adjust pages slot in the stack to reflect the webviews pointer change
                    for (int i = 0; i < [toLoad count]; i++) {
                        tmpSlot =  -1 * [[toLoad[i] valueForKey:@"slot"] intValue];
                        toLoad[i][@"slot"] = @(tmpSlot);
                    }

                    [currPage removeFromSuperview];
                    [self addPageLoading:0];

                } else if (tapNumber == 1) {

                    if (direction < 0) {
                        // ****** Move LEFT <<<
                        [prevPage removeFromSuperview];
                        UIWebView *tmpView = prevPage;
                        prevPage = currPage;
                        currPage = nextPage;
                        nextPage = tmpView;

                    } else {
                        // ****** Move RIGHT >>>
                        [nextPage removeFromSuperview];
                        UIWebView *tmpView = nextPage;
                        nextPage = currPage;
                        currPage = prevPage;
                        prevPage = tmpView;
                    }

                    // Adjust pages slot in the stack to reflect the webviews pointer change
                    for (int i = 0; i < [toLoad count]; i++) {
                        tmpSlot = [[toLoad[i] valueForKey:@"slot"] intValue];
                        if (direction < 0) {
                            if (tmpSlot == +1) {
                                tmpSlot = 0;
                            } else if (tmpSlot == 0) {
                                tmpSlot = -1;
                            } else if (tmpSlot == -1) {
                                tmpSlot = +1;
                            }
                        } else {
                            if (tmpSlot == -1) {
                                tmpSlot = 0;
                            } else if (tmpSlot == 0) {
                                tmpSlot = +1;
                            } else if (tmpSlot == +1) {
                                tmpSlot = -1;
                            }
                        }
                        toLoad[i][@"slot"] = @(tmpSlot);
                    }

                    // Since we are not loading anything we have to reset the delayer flag
                    currentPageIsDelayingLoading = NO;

                    // Dispatch focus event on new current page
                    [Utils webView:currPage dispatchHTMLEvent:@"focus"];

                    // Dispatch BakerViewPage analytics event
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerViewPage" object:self]; // -> Baker Analytics Event
                }

                [self setCurrentPageHeight];

                tapNumber = 0;
                if (direction < 0) {

                    // REMOVE OTHER NEXT page from toLoad stack
                    for (int i = 0; i < [toLoad count]; i++) {
                        if ([[toLoad[i] valueForKey:@"slot"] intValue] == +1) {
                            [toLoad removeObjectAtIndex:i];
                        }
                    }

                    // PRELOAD NEXT page
                    if (currentPageNumber < totalPages) {
                        [self addPageLoading:+1];
                    }

                } else {

                    // REMOVE OTHER PREV page from toLoad stack
                    for (int i = 0; i < [toLoad count]; i++) {
                        if ([[toLoad[i] valueForKey:@"slot"] intValue] == -1) {
                            [toLoad removeObjectAtIndex:i];
                        }
                    }

                    // PRELOAD PREV page
                    if (currentPageNumber > 1) {
                        [self addPageLoading:-1];
                    }
                }
            }

            [self handlePageLoading];
        }
        else
        {
            tapNumber = 0;

            [toLoad removeAllObjects];
            [currPage removeFromSuperview];

            [self updateScreenshots];

            if (![self checkScreeshotForPage:currentPageNumber andOrientation:[self getCurrentInterfaceOrientation:self.interfaceOrientation]]) {
                [self lockPage:@YES];
            }

            [self addPageLoading:0];
            [self handlePageLoading];
        }
    }
}
- (void)lockPage:(NSNumber *)lock {
    if ([lock boolValue])
    {
        if (scrollView.scrollEnabled) {
            scrollView.scrollEnabled = NO;
        }
        currentPageIsLocked = YES;
    }
    else
    {
        if (stackedScrollingAnimations == 0) {
            scrollView.scrollEnabled = [book.bakerPageTurnSwipe boolValue]; // YES by default, NO if specified
        }
        currentPageIsLocked = NO;
    }
}
- (void)addPageLoading:(int)slot {
    //LogBaker(@"[BakerView] Add page to the loding queue");

    NSArray *objs = @[@(slot), @(currentPageNumber + slot)];
    NSArray *keys = @[@"slot", @"page"];

    if (slot == 0) {
        [toLoad insertObject:[NSMutableDictionary dictionaryWithObjects:objs forKeys:keys] atIndex:0];
    } else {
        [toLoad addObject:[NSMutableDictionary dictionaryWithObjects:objs forKeys:keys]];
    }
}
- (void)handlePageLoading {
    if ([toLoad count] != 0) {

        int slot = [[toLoad[0] valueForKey:@"slot"] intValue];
        int page = [[toLoad[0] valueForKey:@"page"] intValue];

        //LogBaker(@"[BakerView] Handle loading of slot %d with page %d", slot, page);

        [toLoad removeObjectAtIndex:0];
        [self loadSlot:slot withPage:page];
    }
}
- (void)loadSlot:(int)slot withPage:(int)page {
    //LogBaker(@"[BakerView] Setting up slot %d with page %d.", slot, page);

    UIWebView *webView = [[UIWebView alloc] init];
    [self setupWebView:webView];

    webView.frame = [self frameForPage:page];
    webView.hidden = YES;

    // ****** SELECT
    // Since pointers can change at any time we've got to handle them directly on a slot basis.
    // Save the page pointer to a temp view to avoid code redundancy make Baker go apeshit.
    if (slot == 0) {
        if (page == currentPageNumber)
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerViewPage" object:self]; // -> Baker Analytics Event

        if (currPage) {
            currPage.delegate = nil;
            if ([currPage isLoading]) {
                [currPage stopLoading];
            }
        }
        currPage = webView;
        currentPageHasChanged = YES;

    } else if (slot == +1) {

        if (nextPage) {
            nextPage.delegate = nil;
            if ([nextPage isLoading]) {
                [nextPage stopLoading];
            }
        }
        nextPage = webView;

    } else if (slot == -1) {

        if (prevPage) {
            prevPage.delegate = nil;
            if ([prevPage isLoading]) {
                [prevPage stopLoading];
            }
        }
        prevPage = webView;
    }


    ((UIScrollView *)[webView subviews][0]).pagingEnabled = [book.bakerVerticalPagination boolValue];

    [scrollView addSubview:webView];
    [self loadWebView:webView withPage:page];
}
- (BOOL)loadWebView:(UIWebView*)webView withPage:(int)page {

    NSString *path = [NSString stringWithString:pages[page - 1]];

    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        LogBaker(@"[BakerView] Loading: %@", [[NSFileManager defaultManager] displayNameAtPath:path]);
        [webView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:path]]];
        return YES;
    }
    return NO;
}

#pragma mark - MODAL WEBVIEW
- (void)loadModalWebView:(NSURL *)url {
    /****************************************************************************************************
     * Initializes the modal view and opens the requested url.
     * It contains a fix to avoid an overlapping status bar.
     */

    //LogBaker(@"[BakerView] Loading a Modal WebView with URL: %@", url.absoluteString);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerViewModalBrowser" object:self]; // -> Baker Analytics Event

    myModalViewController = [[ModalViewController alloc] initWithUrl:url];
    myModalViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    myModalViewController.delegate = self;

    // Hide the IndexView before opening modal web view
    [self hideBars:@YES];

    [self presentViewController:myModalViewController animated:YES completion:nil];

    currentPageWillAppearUnderModal = YES;
}
- (void)closeModalWebView {
    /****************************************************************************************************
     * This function is called from inside the modal view to close itself (delegate).
     */

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - SCROLLVIEW
- (CGRect)frameForPage:(int)page {
    return CGRectMake(pageWidth * (page - 1), 0, pageWidth, pageHeight);
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll {
    //LogBaker(@"[BakerView] Scrollview will begin dragging");
    [self hideBars:@YES];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate {
    //LogBaker(@"[BakerView] Scrollview did end dragging");
}
- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scroll {
    //LogBaker(@"[BakerView] Scrollview will begin decelerating");
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll {

    int page = (int)(scroll.contentOffset.x / pageWidth) + 1;
    LogBaker(@"[BakerView] Swiping to page: %d", page);

    if (currentPageNumber != page) {

        lastPageNumber = currentPageNumber;
        currentPageNumber = page;

        tapNumber = tapNumber + (lastPageNumber - currentPageNumber);

        currentPageIsDelayingLoading = YES;
        [self gotoPage];
    }
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scroll {
    //LogBaker(@"[BakerView] Scrollview did end scrolling animation");

    stackedScrollingAnimations--;
    if (stackedScrollingAnimations == 0) {
        //LogBaker(@"[BakerView]     Scroll enabled");
        scroll.scrollEnabled = [book.bakerPageTurnSwipe boolValue]; // YES by default, NO if specified
    }
}

#pragma mark - WEBVIEW
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {

    // Sent before a web view begins loading content, useful to trigger actions before the WebView.
    NSURL *url = [request URL];

    if ([webView isEqual:prevPage])
    {
        //LogBaker(@"[BakerView]     Page is prev page --> load page");
        return YES;
    }
    else if ([webView isEqual:nextPage])
    {
        //LogBaker(@"[BakerView]     Page is next page --> load page");
        return YES;
    }
    else if (currentPageIsDelayingLoading)
    {
        //LogBaker(@"[BakerView]     Page is current page and current page IS delaying loading --> load page");
        currentPageIsDelayingLoading = NO;
        return ![self isIndexView:webView];
    }
    else
    {
        // ****** Handle URI schemes
        if (url)
        {
            // Existing, checking if index...
            if([[url relativePath] isEqualToString:[indexViewController indexPath]])
            {
                //LogBaker(@"[BakerView]     Page is index --> load index");
                return YES;
            }
            else
            {
                //LogBaker(@"[BakerView]     Page is current page and current page IS NOT delaying loading --> handle clicked link: %@", [url absoluteString]);

                // Not index, checking scheme...
                if ([[url scheme] isEqualToString:@"file"])
                {
                    // ****** Handle: file://
                    LogBaker(@"[BakerView]     Page is a link with scheme file:// --> load internal link");

                    anchorFromURL  = [url fragment];
                    NSString *file = [[url relativePath] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

                    int page = [pages indexOfObject:file];
                    if (page == NSNotFound)
                    {
                        // ****** Internal link, but not one of the book pages --> load page anyway
                        return YES;
                    }

                    page = page + 1;
                    if (![self changePage:page] && ![webView isEqual:indexViewController.view])
                    {
                        if (anchorFromURL == nil) {
                            return YES;
                        }

                        [self handleAnchor:YES];
                    }
                }
                else if ([[url scheme] isEqualToString:@"book"])
                {
                    [self toggleBars];
                    [self performSelector:@selector(handleBookProtocol:) withObject:url afterDelay:0.4];
                }
                else if ([[url scheme] isEqualToString:@"mailto"])
                {
                    // Handle mailto links using MessageUI framework
                    LogBaker(@"[BakerView]     Page is a link with scheme mailto: --> handle mail link");

                    // Build temp array and dictionary
                    NSArray *tempArray = [[url absoluteString] componentsSeparatedByString:@"?"];
                    NSMutableDictionary *queryDictionary = [[NSMutableDictionary alloc] init];

                    // Check array count to see if we have parameters to query
                    if ([tempArray count] == 2)
                    {
                        NSArray *keyValuePairs = [tempArray[1] componentsSeparatedByString:@"&"];

                        for (NSString *queryString in keyValuePairs) {
                            NSArray *keyValuePair = [queryString componentsSeparatedByString:@"="];
                            if (keyValuePair.count == 2) {
                                queryDictionary[keyValuePair[0]] = keyValuePair[1];
                            }
                        }
                    }

                    NSString *email = (tempArray[0]) ? tempArray[0] : [url resourceSpecifier];
                    NSString *subject = queryDictionary[@"subject"];
                    NSString *body = queryDictionary[@"body"];


                    if ([MFMailComposeViewController canSendMail])
                    {
                        MFMailComposeViewController *mailer = [[MFMailComposeViewController alloc] init];

                        mailer.mailComposeDelegate = self;
                        mailer.modalPresentationStyle = UIModalPresentationPageSheet;

                        [mailer setToRecipients:@[[email stringByReplacingOccurrencesOfString:@"mailto:" withString:@""]]];
                        [mailer setSubject:[subject stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
                        [mailer setMessageBody:[body stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] isHTML:NO];

                        // Show the view
                        [self presentViewController:mailer animated:YES completion:nil];

                        currentPageWillAppearUnderModal = YES;

                    }
                    else
                    {
                        // Check if the system can handle a mailto link
                        if ([[UIApplication sharedApplication] canOpenURL:url])
                        {
                            // Go for it and open the URL within the respective app
                            [[UIApplication sharedApplication] openURL: url];
                        }
                        else
                        {
                            // Display error message
                            [Utils showAlertWithTitle:NSLocalizedString(@"MAILTO_ALERT_TITLE", nil)
                                              message:NSLocalizedString(@"MAILTO_ALERT_MESSAGE", nil)
                                          buttonTitle:NSLocalizedString(@"MAILTO_ALERT_CLOSE", nil)];
                        }
                    }

                    return NO;
                }
                else if (![[url scheme] isEqualToString:@""] && ![[url scheme] isEqualToString:@"http"] && ![[url scheme] isEqualToString:@"https"])
                {
                    if ([[UIApplication sharedApplication] canOpenURL:url]) {
                        [[UIApplication sharedApplication] openURL:url];
                    } else {
                        LogBaker(@"[BakerView] ERROR: No installed application to open '%@'. An application to handle the '%@' URL scheme is required.", url, [url scheme]);
                        [Utils webView:currPage dispatchHTMLEvent:@"urlnothandled" withParams:@{@"url": url}];
                    }

                    return NO;
                }
                else
                {
                    // **************************************************************************************************** OPEN OUTSIDE BAKER
                    // * This is required since the inclusion of external libraries (like Google Maps) requires
                    // * direct opening of external pages within Baker. So we have to handle when you want to actually
                    // * open a page outside of Baker.

                    NSString *params = [url query];
                    //LogBaker(@"[BakerView]     Opening absolute URL: %@", [url absoluteString]);

                    if (params != nil)
                    {
                        NSRegularExpression *referrerExternalRegex = [NSRegularExpression regularExpressionWithPattern:URL_OPEN_EXTERNAL options:NSRegularExpressionCaseInsensitive error:NULL];
                        NSUInteger matches = [referrerExternalRegex numberOfMatchesInString:params options:0 range:NSMakeRange(0, [params length])];

                        NSRegularExpression *referrerModalRegex = [NSRegularExpression regularExpressionWithPattern:URL_OPEN_MODALLY options:NSRegularExpressionCaseInsensitive error:NULL];
                        NSUInteger matchesModal = [referrerModalRegex numberOfMatchesInString:params options:0 range:NSMakeRange(0, [params length])];

                        if (matches > 0)
                        {
                            //LogBaker(@"[BakerView]     Link contain param '%@' --> open link in Safari", URL_OPEN_EXTERNAL);

                            // Generate new URL without
                            // We are regexp-ing three things: the string alone, the string first with other content, the string with other content in any other position
                            NSString *pattern = [[NSString alloc] initWithFormat:@"\\?%@$|(?<=\\?)%@&?|()&?%@", URL_OPEN_EXTERNAL, URL_OPEN_EXTERNAL, URL_OPEN_EXTERNAL];
                            NSRegularExpression *replacerRegexp = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
                            NSString *oldURL = [url absoluteString];
                            //LogBaker(@"[BakerView]     replacement pattern: %@", [replacerRegexp pattern]);
                            NSString *newURL = [replacerRegexp stringByReplacingMatchesInString:oldURL options:0 range:NSMakeRange(0, [oldURL length]) withTemplate:@""];

                            LogBaker(@"[BakerView]     Opening in Safari with URL: %@", newURL);
                            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:newURL]];

                            return NO;
                        }
                        else if (matchesModal)
                        {
                            //LogBaker(@"[BakerView]     Link contain param '%@' --> open link modally", URL_OPEN_MODALLY);

                            // Generate new URL without
                            // We are regexp-ing three things: the string alone, the string first with other content, the string with other content in any other position
                            NSString *pattern = [[NSString alloc] initWithFormat:@"\\?%@$|(?<=\\?)%@&?|()&?%@", URL_OPEN_MODALLY, URL_OPEN_MODALLY, URL_OPEN_MODALLY];
                            NSRegularExpression *replacerRegexp = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
                            NSString *oldURL = [url absoluteString];
                            //LogBaker(@"[BakerView]     replacement pattern: %@", [replacerRegexp pattern]);
                            NSString *newURL = [replacerRegexp stringByReplacingMatchesInString:oldURL options:0 range:NSMakeRange(0, [oldURL length]) withTemplate:@""];

                            LogBaker(@"[BakerView]     Opening in Modal Panel with URL: %@", newURL);
                            [self loadModalWebView:[NSURL URLWithString:newURL]];

                            return NO;
                        }
                    }

                    LogBaker(@"[BakerView]     Opening absolute link in page (no parameter specified). URL: %@", [url absoluteString]);

                    return YES;
                }
            }
        }

        return NO;
    }
}
- (void)webViewDidStartLoad:(UIWebView *)webView {
    //LogBaker(@"[BakerView] Page did start load");
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    // Sent if a web view failed to load content.
    if ([webView isEqual:currPage]) {
        LogBaker(@"[BakerView] ERROR: CurrPage failed to load content with error: %@", error);
    } else if ([webView isEqual:prevPage]) {
        LogBaker(@"[BakerView] ERROR: PrevPage failed to load content with error: %@", error);
    } else if ([webView isEqual:nextPage]) {
        LogBaker(@"[BakerView] ERROR: NextPage failed to load content with error: %@", error);
    }
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    //LogBaker(@"[BakerView] Page did finish load");
    [self webView:webView setCorrectOrientation:self.interfaceOrientation];

    if (webView.hidden == YES)
    {
        if ([webView isEqual:currPage]) {
            currentPageHasChanged = NO;
            [self setCurrentPageHeight];
        }

        [webView removeFromSuperview];
        webView.hidden = NO;

        if ([book.bakerRendering isEqualToString:@"three-cards"]) {
            [self webView:webView hidden:NO animating:YES];
        } else {
            [self takeScreenshotFromView:webView forPage:currentPageNumber andOrientation:[self getCurrentInterfaceOrientation:self.interfaceOrientation]];
        }

        [self handlePageLoading];
    }

    /** CHECK IF META TAG SAYS HTML FILE SHOULD BE PAGED **/
    [webView.scrollView setPagingEnabled:[Utils webViewShouldBePaged:webView forBook:book]];
}
- (void)webView:(UIWebView *)webView hidden:(BOOL)status animating:(BOOL)animating {

    //LogBaker(@"[BakerView] webView hidden: %d animating: %d", status, animating);

    if (animating) {

        webView.hidden = NO;
        webView.alpha = 0.0;

        [scrollView addSubview:webView];
        [UIView animateWithDuration:0.5
                         animations:^{ webView.alpha = 1.0; }
                         completion:^(BOOL finished) { [self webViewDidAppear:webView animating:animating]; }];
    } else {

        [scrollView addSubview:webView];
        [self webViewDidAppear:webView animating:animating];
    }
}
- (void)webViewDidAppear:(UIWebView *)webView animating:(BOOL)animating {

    if ([webView isEqual:currPage])
    {
        [Utils webView:webView dispatchHTMLEvent:@"focus"];

        // If is the first time i load something in the currPage web view...
        if (currentPageFirstLoading)
        {
            // ... check if there is a saved starting scroll index and set it
            //LogBaker(@"[BakerView]     Handle last scroll index if necessary");
            NSString *currPageScrollIndex = bookStatus.scrollIndex;
            if (currPageScrollIndex != nil) {
                [self scrollDownCurrentPage:[currPageScrollIndex intValue] animating:YES];
            }
            currentPageFirstLoading = NO;
        }
        else
        {
            //LogBaker(@"[BakerView]     Handle saved hash reference if necessary");
            [self handleAnchor:YES];
        }
    }
}

- (void)webView:(UIWebView *)webView setCorrectOrientation:(UIInterfaceOrientation)interfaceOrientation {

    // Since the UIWebView doesn't handle orientationchange events correctly we have to set the correct value for window.orientation property ourselves
    NSString *jsOrientationGetter;
    switch (interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 0; });";
            break;
        case UIInterfaceOrientationLandscapeLeft:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 90; });";
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 180; });";
            break;
        case UIInterfaceOrientationLandscapeRight:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return -90; });";
            break;
        default:
            break;
    }

    [webView stringByEvaluatingJavaScriptFromString:jsOrientationGetter];
}

#pragma mark - SCREENSHOTS
- (void)removeScreenshots {

    for (NSNumber *key in attachedScreenshotLandscape) {
        UIView *value = attachedScreenshotLandscape[key];
        [value removeFromSuperview];
    }

    for (NSNumber *key in attachedScreenshotPortrait) {
        UIView *value = attachedScreenshotPortrait[key];
        [value removeFromSuperview];
    }

    [attachedScreenshotLandscape removeAllObjects];
    [attachedScreenshotPortrait removeAllObjects];
}
- (void)updateScreenshots {

    NSMutableSet *completeSet = [NSMutableSet new];
    NSMutableSet *supportSet  = [NSMutableSet new];

    NSString *interfaceOrientation = nil;
    NSMutableDictionary *attachedScreenshot = nil;

    if (pageWidth < pageHeight) {
        interfaceOrientation = @"portrait";
        attachedScreenshot = attachedScreenshotPortrait;
    } else if (pageWidth > pageHeight) {
        interfaceOrientation = @"landscape";
        attachedScreenshot = attachedScreenshotLandscape;
    }

    /*
    DEPRECATED - Won't work if called during rotation
    if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
    {
        interfaceOrientation = @"portrait";
        attachedScreenshot = attachedScreenshotPortrait;
    }
    else if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation))
    {
        interfaceOrientation = @"landscape";
        attachedScreenshot = attachedScreenshotLandscape;
    }
    */

    for (NSNumber *num in attachedScreenshot) [completeSet addObject:num];

    for (int i = MAX(1, currentPageNumber - MAX_SCREENSHOT_BEFORE_CP); i <= MIN(totalPages, currentPageNumber + MAX_SCREENSHOT_AFTER_CP); i++)
    {
        NSNumber *num = @(i);
        [supportSet addObject:num];

        if ([self checkScreeshotForPage:i andOrientation:interfaceOrientation] && !attachedScreenshot[num]) {
            [self placeScreenshotForView:nil andPage:i andOrientation:interfaceOrientation];
            [completeSet addObject:num];
        }
    }

    [completeSet minusSet:supportSet];

    for (NSNumber *num in completeSet) {
        [attachedScreenshot[num] removeFromSuperview];
        [attachedScreenshot removeObjectForKey:num];
    }

}
- (BOOL)checkScreeshotForPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation {

    if (![[NSFileManager defaultManager] fileExistsAtPath:cachedScreenshotsPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cachedScreenshotsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *screenshotFile = [cachedScreenshotsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"screenshot-%@-%i.jpg", interfaceOrientation, pageNumber]];
    return [[NSFileManager defaultManager] fileExistsAtPath:screenshotFile];
}
- (void)takeScreenshotFromView:(UIWebView *)webView forPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation {

    BOOL shouldRevealWebView = YES;
    BOOL animating = YES;

    if (![self checkScreeshotForPage:pageNumber andOrientation:interfaceOrientation])
    {
        //LogBaker(@"[BakerView] Taking screenshot of page %d", pageNumber);

        NSString *screenshotFile = [cachedScreenshotsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"screenshot-%@-%i.jpg", interfaceOrientation, pageNumber]];
        UIImage *screenshot = nil;

        if ([interfaceOrientation isEqualToString:[self getCurrentInterfaceOrientation:self.interfaceOrientation]] && !currentPageHasChanged) {

            UIGraphicsBeginImageContextWithOptions(webView.frame.size, NO, [[UIScreen mainScreen] scale]);
            [webView.layer renderInContext:UIGraphicsGetCurrentContext()];
            screenshot = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (screenshot) {
                BOOL saved = [UIImageJPEGRepresentation(screenshot, 0.6) writeToFile:screenshotFile options:NSDataWritingAtomic error:nil];
                if (saved) {
                    LogBaker(@"[BakerView] Screenshot succesfully saved to file %@", screenshotFile);
                    [self placeScreenshotForView:webView andPage:pageNumber andOrientation:interfaceOrientation];
                    shouldRevealWebView = NO;
                }
            }
        }

        [self performSelector:@selector(lockPage:) withObject:@NO afterDelay:0.1];
    }

    if (!currentPageHasChanged && shouldRevealWebView) {
        [self webView:webView hidden:NO animating:animating];
    }
}
- (void)placeScreenshotForView:(UIWebView *)webView andPage:(int)pageNumber andOrientation:(NSString *)interfaceOrientation {

    int i = pageNumber - 1;
    NSNumber *num = @(pageNumber);

    NSString    *screenshotFile = [cachedScreenshotsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"screenshot-%@-%i.jpg", interfaceOrientation, pageNumber]];
    UIImageView *screenshotView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:screenshotFile]];

    NSMutableDictionary *attachedScreenshot = attachedScreenshotPortrait;
    CGSize pageSize = CGSizeMake(screenBounds.size.width, screenBounds.size.height);

    if ([interfaceOrientation isEqualToString:@"landscape"]) {
        attachedScreenshot = attachedScreenshotLandscape;
        pageSize = CGSizeMake(screenBounds.size.height, screenBounds.size.width);
    }

    screenshotView.frame = CGRectMake(pageSize.width * i, 0, pageSize.width, pageSize.height);

    BOOL alreadyPlaced = NO;
    UIImageView *oldScreenshot = attachedScreenshot[num];

    if (oldScreenshot) {
        [scrollView addSubview:screenshotView];
        [attachedScreenshot removeObjectForKey:num];
        [oldScreenshot removeFromSuperview];

        alreadyPlaced = YES;
    }

    attachedScreenshot[num] = screenshotView;

    if (webView == nil)
    {
        screenshotView.alpha = 0.0;

        [scrollView addSubview:screenshotView];
        [UIView animateWithDuration:0.5 animations:^{ screenshotView.alpha = 1.0; }];
    }
    else if (webView != nil)
    {
        if (alreadyPlaced)
        {
            [self webView:webView hidden:NO animating:NO];
        }
        else if ([interfaceOrientation isEqualToString:[self getCurrentInterfaceOrientation:self.interfaceOrientation]] && !currentPageHasChanged)
        {
            screenshotView.alpha = 0.0;

            [scrollView addSubview:screenshotView];
            [UIView animateWithDuration:0.5
                             animations:^{ screenshotView.alpha = 1.0; }
                             completion:^(BOOL finished) { if (!currentPageHasChanged) { [self webView:webView hidden:NO animating:NO]; }}];
        }
    }

}

#pragma mark - GESTURES
- (void)handleInterceptedTouch:(NSNotification *)notification {

    NSDictionary *userInfo = notification.userInfo;
    UITouch *touch = userInfo[@"touch"];
    BOOL shouldPropagateIndexInterceptedTouch = NO;

    if (touch.phase == UITouchPhaseBegan) {
        userIsScrolling = NO;
        shouldPropagateInterceptedTouch = ([touch.view isDescendantOfView:scrollView]);
        shouldPropagateIndexInterceptedTouch = [touch.view isDescendantOfView:indexViewController.view];
    } else if (touch.phase == UITouchPhaseMoved) {
        userIsScrolling = YES;
    }

    if (shouldPropagateInterceptedTouch) {
        if (userIsScrolling) {
            [self userDidScroll:touch];
        } else if (touch.phase == UITouchPhaseEnded) {
            [self userDidTap:touch];
        }
    } else if (shouldPropagateIndexInterceptedTouch) {
        if (touch.tapCount == 2) {
            //LogBaker(@"[BakerView]     Index Double Tap: Bars Toggled");
            [self toggleBars];
        }
    }
}
- (void)userDidTap:(UITouch *)touch {
    /****************************************************************************************************
     * This function handles all the possible user navigation taps:
     * up, down, left, right and double-tap.
     */

    CGPoint tapPoint = [touch locationInView:self.view];
    //LogBaker(@"[BakerView] User tap at [%f, %f]", tapPoint.x, tapPoint.y);

    // Swipe or scroll the page.
    if (!currentPageIsLocked)
    {
        if (CGRectContainsPoint(upTapArea, tapPoint)) {
            LogBaker(@"[BakerView]    Tap UP /\\!");
            [self scrollUpCurrentPage:([self getCurrentPageOffset] - pageHeight + 50) animating:YES];
        } else if (CGRectContainsPoint(downTapArea, tapPoint)) {
            LogBaker(@"[BakerView]    Tap DOWN \\/");
            [self scrollDownCurrentPage:([self getCurrentPageOffset] + pageHeight - 50) animating:YES];
        } else if (CGRectContainsPoint(leftTapArea, tapPoint) || CGRectContainsPoint(rightTapArea, tapPoint)) {
            int page = 0;
            if (CGRectContainsPoint(leftTapArea, tapPoint)) {
                LogBaker(@"[BakerView]    Tap LEFT >>>");
                page = currentPageNumber - 1;
            } else if (CGRectContainsPoint(rightTapArea, tapPoint)) {
                LogBaker(@"[BakerView]    Tap RIGHT <<<");
                page = currentPageNumber + 1;
            }

            if ([book.bakerPageTurnTap boolValue]) [self changePage:page];
        }
        else if (touch.tapCount == 2) {
            //LogBaker(@"[BakerView]     Index Double Tap: Bars Toggled");
            [self toggleBars];
        }
    }
}
- (void)userDidScroll:(UITouch *)touch {
    //LogBaker(@"[BakerView] User scroll");
    [self hideBars:@YES];

    currPage.backgroundColor = webViewBackground;
    currPage.opaque = YES;
}

#pragma mark - PAGE SCROLLING
- (void)setCurrentPageHeight {
    for (UIView *subview in currPage.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            CGSize size = ((UIScrollView *)subview).contentSize;
            //LogBaker(@"[BakerView] Setting current page height from %d to %f", currentPageHeight, size.height);
            currentPageHeight = size.height;
        }
    }
}
- (int)getCurrentPageOffset {

    int currentPageOffset = [[currPage stringByEvaluatingJavaScriptFromString:@"window.scrollY;"] intValue];
    if (currentPageOffset < 0) return 0;

    int currentPageMaxScroll = currentPageHeight - pageHeight;
    if (currentPageOffset > currentPageMaxScroll) return currentPageMaxScroll;

    return currentPageOffset;
}
- (void)scrollUpCurrentPage:(int)targetOffset animating:(BOOL)animating {

    if ([self getCurrentPageOffset] > 0)
    {
        if (targetOffset < 0) targetOffset = 0;

        //LogBaker(@"[BakerView] Scrolling page up to %d", targetOffset);
        [self scrollPage:currPage to:[NSString stringWithFormat:@"%d", targetOffset] animating:animating];
    }
}
- (void)scrollDownCurrentPage:(int)targetOffset animating:(BOOL)animating {

    int currentPageMaxScroll = currentPageHeight - pageHeight;
    if ([self getCurrentPageOffset] < currentPageMaxScroll)
    {
        if (targetOffset > currentPageMaxScroll) targetOffset = currentPageMaxScroll;

        //LogBaker(@"[BakerView] Scrolling page down to %d", targetOffset);
        [self scrollPage:currPage to:[NSString stringWithFormat:@"%d", targetOffset] animating:animating];
    }

}
- (void)scrollPage:(UIWebView *)webView to:(NSString *)offset animating:(BOOL)animating {
    [self hideBars:@YES];

    NSString *jsCommand = [NSString stringWithFormat:@"window.scrollTo(0,%@);", offset];
    if (animating) {
        [UIView animateWithDuration:0.35 animations:^{ [webView stringByEvaluatingJavaScriptFromString:jsCommand]; }];
    } else {
        [webView stringByEvaluatingJavaScriptFromString:jsCommand];
    }
}
- (void)handleAnchor:(BOOL)animating {
    if (anchorFromURL != nil) {
        NSString *jsAnchorHandler = [NSString stringWithFormat:@"(function() {\
                                     var target = '%@';\
                                     var elem = document.getElementById(target);\
                                     if (!elem) elem = document.getElementsByName(target)[0];\
                                     return elem.offsetTop;\
                                     })();", anchorFromURL];

        NSString *offsetString = [currPage stringByEvaluatingJavaScriptFromString:jsAnchorHandler];
        if (![offsetString isEqualToString:@""])
        {
            int offset = [offsetString intValue];
            int currentPageOffset = [self getCurrentPageOffset];

            if (offset > currentPageOffset) {
                [self scrollDownCurrentPage:offset animating:animating];
            } else if (offset < currentPageOffset) {
                [self scrollUpCurrentPage:offset animating:animating];
            }
        }

        anchorFromURL = nil;
    }
}

#pragma mark - BARS VISIBILITY
- (CGRect)getNewNavigationFrame:(BOOL)hidden {
    UINavigationBar *navigationBar = self.navigationController.navigationBar;

    int navX = navigationBar.frame.origin.x;
    int navW = navigationBar.frame.size.width;
    int navH = navigationBar.frame.size.height;

    if (hidden) {
        return CGRectMake(navX, -44, navW, navH);
    } else {
        return CGRectMake(navX, 20, navW, navH);
    }
}
- (BOOL)prefersStatusBarHidden {
    return barsHidden;
}
- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
    return UIStatusBarAnimationSlide;
}
- (void)toggleBars {
    // if modal view is up, don't toggle.
    if (!self.presentedViewController) {
        LogBaker(@"[BakerView] Toggle bars visibility");

        if (barsHidden) {
            [self showBars];
        } else {
            [self hideBars:@YES];
        }
    }
}
- (void)showBars {

    barsHidden = NO;

    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationSlide];
        [self performSelector:@selector(showNavigationBar) withObject:nil afterDelay:0.1];
    } else {
        [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
            [self setNeedsStatusBarAppearanceUpdate];
        }];
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    }

    if(![indexViewController isDisabled]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerViewIndexOpen" object:self]; // -> Baker Analytics Event
        [indexViewController setIndexViewHidden:NO withAnimation:YES];
    }
}
- (void)showNavigationBar {

    CGRect newNavigationFrame = [self getNewNavigationFrame:NO];
    UINavigationBar *navigationBar = self.navigationController.navigationBar;

    navigationBar.frame = CGRectMake(newNavigationFrame.origin.x, -24, newNavigationFrame.size.width, newNavigationFrame.size.height);
    navigationBar.hidden = NO;

    [UIView animateWithDuration:0.3
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         navigationBar.frame = newNavigationFrame;
                     }
                     completion:nil];
}
- (void)hideBars:(NSNumber *)animated {

    barsHidden = YES;

    BOOL animateHiding = [animated boolValue];

    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {

        CGRect newNavigationFrame = [self getNewNavigationFrame:YES];
        UINavigationBar *navigationBar = self.navigationController.navigationBar;

        if (animateHiding) {
            [UIView animateWithDuration:0.3
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 navigationBar.frame = newNavigationFrame;
                             }
                             completion:^(BOOL finished) {
                                 navigationBar.hidden = YES;
                             }];
        } else {
            navigationBar.frame = newNavigationFrame;
            navigationBar.hidden = YES;
        }

        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];

    } else {

        if (animateHiding) {
            [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
                [self setNeedsStatusBarAppearanceUpdate];
            }];
        } else {
           [self setNeedsStatusBarAppearanceUpdate];
        }

        [self.navigationController setNavigationBarHidden:YES animated:animateHiding];
    }

    if(![indexViewController isDisabled]) {
        [indexViewController setIndexViewHidden:YES withAnimation:YES];
    }
}
- (void)handleBookProtocol:(NSURL *)url
{
    // ****** Handle: book://
    LogBaker(@"[BakerView]     Page is a link with scheme book:// --> download new book");
    if ([[url pathExtension] isEqualToString:@"html"]) {
        // page   --> [[url lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
        // anchor --> [url fragment];

        url = [url URLByDeletingLastPathComponent];
    }
    NSString *bookName = [[url lastPathComponent] stringByReplacingOccurrencesOfString:@".hpub" withString:@""];
    NSDictionary *userInfo = @{@"ID": bookName};

    [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_book_protocol" object:nil userInfo:userInfo];
}

#pragma mark - ORIENTATION
- (NSString *)getCurrentInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ([book.orientation isEqualToString:@"portrait"] || [book.orientation isEqualToString:@"landscape"]) {
        return book.orientation;
    } else {
        if (UIInterfaceOrientationIsLandscape(interfaceOrientation)) {
            return @"landscape";
        } else {
            return @"portrait";
        }
    }
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {

    BOOL appOrientation = [supportedOrientation indexOfObject:[Utils stringFromInterfaceOrientation:interfaceOrientation]] != NSNotFound;

    if ([book.orientation isEqualToString:@"portrait"]) {
        return appOrientation && UIInterfaceOrientationIsPortrait(interfaceOrientation);
    } else if ([book.orientation isEqualToString:@"landscape"]) {
        return appOrientation && UIInterfaceOrientationIsLandscape(interfaceOrientation);
    } else {
        return appOrientation;
    }
}
- (BOOL)shouldAutorotate {
    return YES;
}
- (NSUInteger)supportedInterfaceOrientations {
    if ([book.orientation isEqualToString:@"portrait"]) {
        return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
    } else if ([book.orientation isEqualToString:@"landscape"]) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        return UIInterfaceOrientationMaskAll;
    }
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    // Notify the index view
    [indexViewController willRotate];

    // Notify the current loaded views
    [self webView:currPage setCorrectOrientation:toInterfaceOrientation];
    if (nextPage) [self webView:nextPage setCorrectOrientation:toInterfaceOrientation];
    if (prevPage) [self webView:prevPage setCorrectOrientation:toInterfaceOrientation];

    [self setPageSize:[self getCurrentInterfaceOrientation:toInterfaceOrientation]];
    [self updateBookLayout];
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [indexViewController rotateFromOrientation:fromInterfaceOrientation toOrientation:self.interfaceOrientation];
    [self setCurrentPageHeight];
}

- (BOOL)forceOrientationUpdate {
    // We need to run this only once to prevent looping in -viewWillAppear
    if (shouldForceOrientationUpdate) {
        shouldForceOrientationUpdate = NO;
        UIInterfaceOrientation interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];

        if ( (UIInterfaceOrientationIsLandscape(interfaceOrientation) && [book.orientation isEqualToString:@"landscape"])
            ||
            (UIInterfaceOrientationIsPortrait(interfaceOrientation) && [book.orientation isEqualToString:@"portrait"]) ) {

            //LogBaker(@"[BakerView] Device and book orientations are in sync");
            return NO;
        } else {
            //LogBaker(@"[BakerView] Device and book orientations are out of sync, force orientation update");

            // Present and dismiss a vanilla view controller to trigger the orientation update
            [self presentViewController:[UIViewController new] animated:NO completion:^{ [self dismissViewControllerAnimated:NO completion:nil]; }];
            return YES;
        }

    } else {
        return NO;
    }
}

#pragma mark - MEMORY
- (void)viewWillDisappear:(BOOL)animated {
    NSArray *viewControllers = self.navigationController.viewControllers;
    if ([viewControllers indexOfObject:self] == NSNotFound) {
        // Baker book is disappearing because it was popped from the navigation stack -> Baker book is closing
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueClose" object:self]; // -> Baker Analytics Event
        [self saveBookStatusWithScrollIndex];
    }
}

/**
 *  保存当前的状态, page 和 scrolling-y坐标 的信息, 需要保存此信息是因为 HTML 是无状态的.
 */
- (void)saveBookStatusWithScrollIndex {
    if (currPage != nil) {
        bookStatus.scrollIndex = [currPage stringByEvaluatingJavaScriptFromString:@"window.scrollY;"];
    }
    [bookStatus save];
    //LogBaker(@"[BakerView] Saved status");
}
- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}
- (void)dealloc {
    
    // Set web views delegates to nil, mandatory before releasing UIWebview instances
    currPage.delegate = nil;
    nextPage.delegate = nil;
    prevPage.delegate = nil;
    
    // Retained background images
    

    // Release the kra... objects






}

#pragma mark - MF MAIL COMPOSER
- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {

    // Log the result for debugging purpose
    switch (result) {
        case MFMailComposeResultCancelled:
            LogBaker(@"[BakerView]     Mail cancelled.");
            break;

        case MFMailComposeResultSaved:
            LogBaker(@"[BakerView]     Mail saved.");
            break;

        case MFMailComposeResultSent:
            LogBaker(@"[BakerView]     Mail sent.");
            break;

        case MFMailComposeResultFailed:
            LogBaker(@"[BakerView]     Mail failed, check NSError.");
            break;

        default:
            LogBaker(@"[BakerView]     Mail not sent.");
            break;
    }

    // Remove the mail view
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - INDEX VIEW
- (BOOL)isIndexView:(UIWebView *)webView {
    if (webView == indexViewController.view) {
        return YES;
    } else {
        return NO;
    }
}

@end
