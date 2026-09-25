#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSCheckInViewController : UIViewController

@property (nonatomic, copy, nullable) NSString *currentGrade;
@property (nonatomic, strong, nullable) NSArray<NSString *> *knowledgePoints;

@end

NS_ASSUME_NONNULL_END
