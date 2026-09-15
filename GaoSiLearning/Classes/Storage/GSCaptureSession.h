#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface GSCaptureSession : NSObject

@property (nonatomic, strong, nullable) UIImage *pageImage;
@property (nonatomic, strong) NSMutableArray<NSValue *> *candidateBoxes; // CGRect
@property (nonatomic, strong) NSMutableArray<NSValue *> *selectedBoxes;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *knowledgePoint;
@property (nonatomic, copy) NSString *mistakeCause;
@property (nonatomic, strong) NSMutableArray<GSSimilarQuestion *> *aiSimilarQuestions;

+ (instancetype)sharedSession;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
