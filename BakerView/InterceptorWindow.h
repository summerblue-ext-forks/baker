

/*
 |--------------------------------------------------------------------------
 | 用户点击事件管理
 |--------------------------------------------------------------------------
 |
 | 继承 UIWindow , 作为 Application Delegate 里的 self.window 顶级视图对象.
 |
 | 当用户点击页面的时候, 发送消息到 [BakerViewController handleInterceptedTouch] 里,
 | handleInterceptedTouch 收到消息后判断用户的点击了多少下, 是否是 crolling 等..
 |
 */

#import <Foundation/Foundation.h>

@interface InterceptorWindow : UIWindow

#pragma mark - Events management
- (void)interceptEvent:(UIEvent *)event;

@end
