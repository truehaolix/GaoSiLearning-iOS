#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^GSOCRCompletion)(NSString *ocrText, BOOL isFormulaSuccess);

@interface GSVisionOCRService : NSObject

+ (instancetype)sharedService;

/// 执行端云协同视觉公式 OCR（服务端能力开放时优先调用，失败时使用 Apple Vision 离线兜底）。
- (void)recognizeQuestionTextFromImage:(UIImage *)image
                            completion:(GSOCRCompletion)completion;

@end

NS_ASSUME_NONNULL_END
