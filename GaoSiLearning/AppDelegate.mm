#import "AppDelegate.h"
#import "GSLoginViewController.h"
#import "GSWrongBookViewController.h"
#import "GSCacheManager.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    if (@available(iOS 13.0, *)) {
        // Managed by SceneDelegate
    } else {
        self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        UIViewController *rootVC = nil;
        if ([[GSCacheManager sharedManager] isLoggedIn]) {
            GSWrongBookViewController *wrongBookVC = [[GSWrongBookViewController alloc] init];
            rootVC = [[UINavigationController alloc] initWithRootViewController:wrongBookVC];
        } else {
            GSLoginViewController *loginVC = [[GSLoginViewController alloc] init];
            rootVC = [[UINavigationController alloc] initWithRootViewController:loginVC];
        }
        self.window.rootViewController = rootVC;
        [self.window makeKeyAndVisible];
    }
    return YES;
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions API_AVAILABLE(ios(13.0)) {
}

@end
