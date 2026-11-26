#import <UIKit/UIKit.h>
#import <stdlib.h>
#import "FBWebServer.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) FBWebServer *webServer;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, self.window.bounds.size.width - 40, 200)];
    lbl.numberOfLines = 0;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    lbl.text = @"WebDriverAgent TrollStore\n\nPort Dieu Khien: 8100\nPort Chieu Man Hinh: 9100\nTrang Thai: Dang Chay";
    [vc.view addSubview:lbl];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        setenv("USE_PORT", "8100", 1);
        setenv("MJPEG_SERVER_PORT", "9100", 1);
        self.webServer = [[FBWebServer alloc] init];
        [self.webServer startServing];
    });
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}