#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GSCropOverlayDelegate <NSObject>
- (void)cropOverlayDidUpdateSelection:(NSArray<NSValue *> *)selectedNormalizedRects;
@end

@interface GSCropOverlayView : UIView

@property (nonatomic, weak) id<GSCropOverlayDelegate> delegate;
@property (nonatomic, assign) CGSize imageSize;

/// 设置检测出的候选选框 (归一化 CGRect)
- (void)setCandidateBoxes:(NSArray<NSValue *> *)boxes;

/// 获取当前所有被选中的归一化矩形
- (NSArray<NSValue *> *)selectedBoxes;

/// 清空选区
- (void)clearSelection;

/// 选中所有题目选框
- (void)selectAllBoxes;

@end

NS_ASSUME_NONNULL_END
