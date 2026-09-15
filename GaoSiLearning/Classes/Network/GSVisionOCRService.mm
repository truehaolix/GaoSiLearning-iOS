#import "GSVisionOCRService.h"
#import "ImageProcessor.hpp"
#import "GSCacheManager.h"
#import <Vision/Vision.h>

@implementation GSVisionOCRService {
    NSURLSession *_session;
}

+ (instancetype)sharedService {
    static GSVisionOCRService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSVisionOCRService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 45.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)recognizeQuestionTextFromImage:(UIImage *)image
                            completion:(GSOCRCompletion)completion {
    if (!image) {
        completion(@"", NO);
        return;
    }

    // 图像自适应预处理与压缩
    UIImage *preprocessed = [GSImageProcessor preprocessForOcr:image maxDimension:1400.0];
    NSString *base64 = [GSImageProcessor base64StringFromImage:preprocessed compressionQuality:0.85];

    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/ai/ocr-question", base]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{ @"imageBase64": base64 ?: @"" };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSError *jsonErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"ok"] boolValue]) {
                NSString *text = json[@"text"];
                if (text && text.length > 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(text, YES);
                    });
                    return;
                }
            }
        }

        // 离线回退到 Apple 原生 Vision 离线文字识别
        [self runLocalAppleVisionOcr:image completion:completion];
    }] resume];
}

- (void)runLocalAppleVisionOcr:(UIImage *)image completion:(GSOCRCompletion)completion {
    if (@available(iOS 13.0, *)) {
        CGImageRef cgImage = image.CGImage;
        if (!cgImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@"", NO);
            });
            return;
        }

        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull req, NSError * _Nullable err) {
            if (err || req.results.count == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@"", NO);
                });
                return;
            }

            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            for (VNRecognizedTextObservation *obs in req.results) {
                VNRecognizedText *topCandidate = [obs topCandidates:1].firstObject;
                if (topCandidate) {
                    [lines addObject:topCandidate.string];
                }
            }
            NSString *fullText = [lines componentsJoinedByString:@"\n"];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(fullText, NO);
            });
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.recognitionLanguages = @[@"zh-Hans", @"en-US"];
        request.usesLanguageCorrection = YES;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *e = nil;
            [handler performRequests:@[request] error:&e];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@"", NO);
        });
    }
}

@end
