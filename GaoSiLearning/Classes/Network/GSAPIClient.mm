#import "GSAPIClient.h"
#import "GSCacheManager.h"

@implementation GSAPIClient {
    NSURLSession *_session;
}

+ (instancetype)sharedClient {
    static GSAPIClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSAPIClient alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
                     role:(NSString *)role
               completion:(GSLoginCompletion)completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/auth/login", base]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"username": username ?: @"",
        @"password": password ?: @"",
        @"role": role ?: @"student"
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error.localizedDescription);
            });
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode < 200 || httpResp.statusCode >= 300) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSString stringWithFormat:@"登录失败 (HTTP %ld)", (long)httpResp.statusCode]);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        if (!json || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @"服务端返回格式异常");
            });
            return;
        }

        NSDictionary *userDict = json[@"user"] ?: json[@"data"] ?: json;
        GSUser *user = [GSUser userFromDictionary:userDict];
        if (json[@"token"]) {
            user.token = [NSString stringWithFormat:@"%@", json[@"token"]];
        }
        [[GSCacheManager sharedManager] saveUser:user];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(user, nil);
        });
    }] resume];
}

- (void)fetchWrongQuestionsForStudent:(NSString *)studentId
                              subject:(nullable NSString *)subject
                           completion:(GSQuestionsCompletion)completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSMutableString *urlStr = [NSMutableString stringWithFormat:@"%@/api/students/%@/wrong-questions", base, studentId];
    if (subject && subject.length > 0 && ![subject isEqualToString:@"全部"]) {
        NSString *encodedSub = [subject stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        [urlStr appendFormat:@"?subject=%@", encodedSub];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    NSString *token = [GSCacheManager sharedManager].currentUser.token;
    if (token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 离线自动使用本地缓存兜底
            NSArray<GSWrongQuestion *> *cached = [[GSCacheManager sharedManager] loadLocalWrongQuestions];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached, nil);
            });
            return;
        }

        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        NSMutableArray<GSWrongQuestion *> *questions = [NSMutableArray array];

        NSArray *list = nil;
        if ([json isKindOfClass:[NSArray class]]) {
            list = (NSArray *)json;
        } else if ([json isKindOfClass:[NSDictionary class]]) {
            list = json[@"items"] ?: json[@"data"] ?: json[@"questions"];
        }

        if ([list isKindOfClass:[NSArray class]]) {
            for (NSDictionary *dict in list) {
                if ([dict isKindOfClass:[NSDictionary class]]) {
                    [questions addObject:[GSWrongQuestion fromDictionary:dict]];
                }
            }
        }

        // 更新本地持久化缓存
        if (questions.count > 0) {
            [[GSCacheManager sharedManager] saveWrongQuestions:questions];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([questions copy], nil);
        });
    }] resume];
}

- (void)batchSubmitWrongQuestions:(NSArray<GSWrongQuestion *> *)questions
                        studentId:(NSString *)studentId
                       completion:(GSBatchUploadCompletion)completion {
    if (questions.count == 0) {
        completion(YES, 0, nil);
        return;
    }

    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *batchUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/students/%@/wrong-questions/batch", base, studentId]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:batchUrl];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *token = [GSCacheManager sharedManager].currentUser.token;
    if (token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    NSMutableArray *items = [NSMutableArray array];
    for (GSWrongQuestion *q in questions) {
        [items addObject:[q toDictionary]];
    }
    NSDictionary *body = @{ @"items": items };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        // 若服务端批量接口正常 (200 / 201)
        if (!error && httpResp.statusCode >= 200 && httpResp.statusCode < 300) {
            // 本地入库
            for (GSWrongQuestion *q in questions) {
                [[GSCacheManager sharedManager] addWrongQuestionLocally:q];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, questions.count, nil);
            });
            return;
        }

        // 若网络失败或服务未响应，存入本地待同步队列，保障离线可用
        for (GSWrongQuestion *q in questions) {
            [[GSCacheManager sharedManager] addWrongQuestionLocally:q];
            [[GSCacheManager sharedManager] addPendingSyncQuestion:q];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, questions.count, @"已保存到本地离线缓存，网络恢复后将自动同步");
        });
    }] resume];
}

- (void)reviewQuestion:(NSString *)questionId
             studentId:(NSString *)studentId
            isMastered:(BOOL)isMastered
            completion:(void(^)(BOOL success, NSString * _Nullable error))completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/students/%@/wrong-questions/%@/review", base, studentId, questionId]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *token = [GSCacheManager sharedManager].currentUser.token;
    if (token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    NSDictionary *body = @{ @"isMastered": @(isMastered) };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error == nil, error.localizedDescription);
        });
    }] resume];
}

@end
