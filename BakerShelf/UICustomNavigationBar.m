

/*
 |--------------------------------------------------------------------------
 | 对 UINavigationBar 的封装, 在 AppDelegate 里调用
 |--------------------------------------------------------------------------
 |
 */

#import "UICustomNavigationBar.h"

@implementation UICustomNavigationBar


- (NSMutableDictionary *)backgroundImages
{
    if (!backgroundImages) {
        backgroundImages = [[NSMutableDictionary alloc] init];
    }
    return backgroundImages;
}
- (UIImageView *)backgroundImageView
{
    if (!backgroundImageView) {
        backgroundImageView = [[UIImageView alloc] initWithFrame:[self bounds]];
        [backgroundImageView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
        [self insertSubview:backgroundImageView atIndex:0];
    }
    return backgroundImageView;
}
- (void)setBackgroundImage:(UIImage *)backgroundImage forBarMetrics:(UIBarMetrics)barMetrics
{
    if ([UINavigationBar instancesRespondToSelector:@selector(setBackgroundImage:forBarMetrics:)]) {
        [super setBackgroundImage:backgroundImage forBarMetrics:barMetrics];
    } else {
        [self backgroundImages][[NSNumber numberWithInt:barMetrics]] = backgroundImage;
        [self updateBackgroundImage];
    }
}
- (void)updateBackgroundImage
{
    UIBarMetrics metrics = UIBarMetricsLandscapePhone;
    if ([self bounds].size.height > 40) {
        metrics = UIBarMetricsDefault;
    }

    UIImage *image = [self backgroundImages][[NSNumber numberWithInt:metrics]];
    if (!image && metrics != UIBarMetricsDefault) {
        image = [self backgroundImages][@(UIBarMetricsDefault)];
    }

    if (image) {
        [[self backgroundImageView] setImage:image];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    if (backgroundImageView) {
        [self updateBackgroundImage];
        [self sendSubviewToBack:backgroundImageView];
    }
}

@end
