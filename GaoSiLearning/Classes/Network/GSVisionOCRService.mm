#import "GSVisionOCRService.h"
#import "ImageProcessor.hpp"
#import "GSCacheManager.h"
#import "GSAPIClient.h"
#import <Vision/Vision.h>

static NSDictionary *GSDictionaryValue(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

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

    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *capabilityURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/mobile-capabilities", base]];
    [[_session dataTaskWithURL:capabilityURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        id root = (!error && http.statusCode >= 200 && http.statusCode < 300)
            ? [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil]
            : nil;
        NSDictionary *contract = GSDictionaryValue(root);
        NSDictionary *capabilities = GSDictionaryValue(contract[@"capabilities"]);
        NSDictionary *ocrQuestion = GSDictionaryValue(capabilities[@"ocrQuestion"]);
        NSString *value = ocrQuestion[@"status"];
        NSString *status = [value isKindOfClass:[NSString class]] ? value : @"unavailable";
        if (![status isEqualToString:@"available"]) {
            [self runLocalAppleVisionOcr:image completion:completion];
            return;
        }
        [self runServerOcr:image completion:completion];
    }] resume];
}

- (void)runServerOcr:(UIImage *)image completion:(GSOCRCompletion)completion {
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
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode == 401) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[GSCacheManager sharedManager] logout];
                [[NSNotificationCenter defaultCenter] postNotificationName:GSAuthenticationExpiredNotification object:nil];
                completion(@"", NO);
            });
            return;
        }
        if (!error && http.statusCode >= 200 && http.statusCode < 300) {
            NSError *jsonErr = nil;
            id root = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
            NSDictionary *json = GSDictionaryValue(root);
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"ok"] boolValue]) {
                id value = json[@"text"];
                NSString *text = [value isKindOfClass:[NSString class]] ? value : nil;
                if (text.length > 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(text, YES);
                    });
                    return;
                }
            }
        }

        // 服务端能力临时失败时，回退到 Apple 原生 Vision 离线文字识别。
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
