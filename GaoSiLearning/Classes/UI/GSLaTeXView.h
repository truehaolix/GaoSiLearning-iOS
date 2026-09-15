#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSLaTeXView : UIView <WKNavigationDelegate>

@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy, nullable) void(^onHeightChanged)(CGFloat height);

- (instancetype)initWithFrame:(CGRect)frame;
- (void)renderLaTeXContent:(NSString *)content;

@end

NS_ASSUME_NONNULL_END
