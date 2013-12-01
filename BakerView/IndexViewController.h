

/*
 |--------------------------------------------------------------------------
 | 杂志的文章类表 index
 |--------------------------------------------------------------------------
 |
 | 加载的是 hpub 包里面 index.html 文件.
 | 用户在查看文章的时候双击就会调出此视图.
 |
 */


#import <UIKit/UIKit.h>
#import "BakerBook.h"

@interface IndexViewController : UIViewController <UIWebViewDelegate> {

    NSString *fileName;
    UIScrollView *indexScrollView;
    UIViewController <UIWebViewDelegate> *webViewDelegate;

    int pageY;
    int pageWidth;
    int pageHeight;
    int indexWidth;
    int indexHeight;
    int actualIndexWidth;
    int actualIndexHeight;

    BOOL disabled;
    BOOL loadedFromBundle;

    CGSize cachedContentSize;
}

@property (strong, nonatomic) BakerBook *book;

- (id)initWithBook:(BakerBook *)bakerBook fileName:(NSString *)name webViewDelegate:(UIViewController *)delegate;
- (void)loadContent;
- (void)setBounceForWebView:(UIWebView *)webView bounces:(BOOL)bounces;
- (void)setPageSizeForOrientation:(UIInterfaceOrientation)orientation;
- (BOOL)isIndexViewHidden;
- (BOOL)isDisabled;
- (void)setIndexViewHidden:(BOOL)hidden withAnimation:(BOOL)animation;
- (void)willRotate;
- (void)rotateFromOrientation:(UIInterfaceOrientation)fromInterfaceOrientation toOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
- (void)fadeOut;
- (void)fadeIn;
- (BOOL)stickToLeft;
- (CGSize)sizeFromContentOf:(UIView *)view;
- (void)setActualSize;
- (void)adjustIndexView;
- (void)setViewFrame:(CGRect)frame;
- (NSString *)indexPath;

@end
