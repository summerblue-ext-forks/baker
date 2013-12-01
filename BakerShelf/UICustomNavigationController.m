

/*
 |--------------------------------------------------------------------------
 | 在 AppDelegate 里调用, rootNavigationController
 |--------------------------------------------------------------------------
 |
 */


#import "UICustomNavigationController.h"
#import "UICustomNavigationBar.h"

@implementation UICustomNavigationController

- (id)init
{
    self = [super init];

    [self navigationBar];
    
    NSMutableData *data = [NSMutableData data];
    
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:self forKey:@"self"];
    [archiver finishEncoding];
    
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:[UICustomNavigationBar class] forClassName:@"UINavigationBar"];
    self = [unarchiver decodeObjectForKey:@"self"];
    [unarchiver finishDecoding];
    
    return self;
    
}

- (NSUInteger)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}
- (BOOL)shouldAutorotate
{
    return [self.topViewController shouldAutorotate];
}

@end