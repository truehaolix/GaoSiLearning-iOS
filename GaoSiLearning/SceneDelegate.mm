#import "SceneDelegate.h"
#import "GSLoginViewController.h"
#import "GSWrongBookViewController.h"
#import "GSCacheManager.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions API_AVAILABLE(ios(13.0)) {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;

    UIViewController *rootVC = nil;
    if ([[GSCacheManager sharedManager] isLoggedIn]) {
        GSWrongBookViewController *wrongBookVC = [[GSWrongBookViewController alloc] init];
        rootVC = [[UINavigationController alloc] initWithRootViewController:wrongBookVC];
    } else {
        GSLoginViewController *loginVC = [[GSLoginViewController alloc] init];
        rootVC = [[UINavigationController alloc] initWithRootViewController:loginVC];
    }
    
    // 自适应 iOS 手机屏幕外观与导航栏样式
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0]; // 高斯蓝
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0]
        };
        [UINavigationBar appearance].standardAppearance = appearance;
        [UINavigationBar appearance].scrollEdgeAppearance = appearance;
        [UINavigationBar appearance].compactAppearance = appearance;
        [UINavigationBar appearance].tintColor = [UIColor whiteColor];
    }
    
    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene API_AVAILABLE(ios(13.0)) {}
- (void)sceneDidBecomeActive:(UIScene *)scene API_AVAILABLE(ios(13.0)) {}
- (void)sceneWillResignActive:(UIScene *)scene API_AVAILABLE(ios(13.0)) {}
- (void)sceneWillEnterForeground:(UIScene *)scene API_AVAILABLE(ios(13.0)) {}
- (void)sceneDidEnterBackground:(UIScene *)scene API_AVAILABLE(ios(13.0)) {}

@end
