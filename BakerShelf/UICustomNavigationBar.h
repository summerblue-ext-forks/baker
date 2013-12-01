

/*
 |--------------------------------------------------------------------------
 | 对 UINavigationBar 的封装, 在 AppDelegate 里调用
 |--------------------------------------------------------------------------
 |
 */

#import <UIKit/UIKit.h>

@interface UICustomNavigationBar : UINavigationBar
{
    UIImageView *backgroundImageView;
    NSMutableDictionary *backgroundImages;
}

@end
