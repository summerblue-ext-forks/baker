

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


#import "InterceptorWindow.h"

@implementation InterceptorWindow

#pragma mark - Events management

- (void)sendEvent:(UIEvent *)event {

    [super sendEvent:event];
    [self interceptEvent:event];
}
- (void)interceptEvent:(UIEvent *)event {

    if (event.type == UIEventTypeTouches)
    {
        NSSet *touches = [event allTouches];
        if (touches.count == 1)
        {
            UITouch *touch = touches.anyObject;

            NSDictionary *userInfo = @{@"touch": touch};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"notification_touch_intercepted" object:nil userInfo:userInfo];
        }
    }
}

@end
