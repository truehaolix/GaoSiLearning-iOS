#import "GSCaptureSession.h"

@implementation GSCaptureSession

+ (instancetype)sharedSession {
    static GSCaptureSession *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSCaptureSession alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

- (void)reset {
    self.pageImage = nil;
    self.candidateBoxes = [NSMutableArray array];
    self.selectedBoxes = [NSMutableArray array];
    self.subject = @"数学";
    self.knowledgePoint = @"";
    self.mistakeCause = @"";
    self.aiSimilarQuestions = [NSMutableArray array];
}

@end
