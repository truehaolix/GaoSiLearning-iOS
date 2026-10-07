#import "GSAPIClient.h"
#import "GSCacheManager.h"

static NSString *GSAPIErrorMessage(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    if (error) return error.localizedDescription;
    if (data.length > 0) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"error"] isKindOfClass:[NSString class]]) {
            return json[@"error"];
        }
    }
    return [NSString stringWithFormat:@"请求失败 (HTTP %ld)", (long)response.statusCode];
}

static void GSCompleteOnMain(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), block);
}

NSNotificationName const GSAuthenticationExpiredNotification = @"GSAuthenticationExpiredNotification";

static BOOL GSHandleUnauthorized(NSHTTPURLResponse *response) {
    if (response.statusCode != 401) return NO;
    GSCompleteOnMain(^{
        [[GSCacheManager sharedManager] logout];
        [[NSNotificationCenter defaultCenter] postNotificationName:GSAuthenticationExpiredNotification object:nil];
    });
    return YES;
}

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
        config.HTTPShouldSetCookies = YES;
        config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
                     role:(NSString *)role
               completion:(GSLoginCompletion)completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/login", base]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"phone": username ?: @"",
        @"password": password ?: @""
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            GSCompleteOnMain(^{
                completion(nil, error.localizedDescription);
            });
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode < 200 || httpResp.statusCode >= 300) {
            GSCompleteOnMain(^{
                completion(nil, GSAPIErrorMessage(data, httpResp, nil));
            });
            return;
        }
        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        if (!json || ![json isKindOfClass:[NSDictionary class]]) {
            GSCompleteOnMain(^{
                completion(nil, @"服务端返回格式异常");
            });
            return;
        }

        NSDictionary *userDict = json[@"user"] ?: json[@"data"] ?: json;
        GSUser *user = [GSUser userFromDictionary:userDict];
        user.token = @"";

        // 学生档案 ID 与账号 ID 不是同一字段，登录后从权威接口解析。
        NSURL *studentsURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/students", base]];
        NSMutableURLRequest *studentsRequest = [NSMutableURLRequest requestWithURL:studentsURL];
        studentsRequest.HTTPMethod = @"GET";
        [[self->_session dataTaskWithRequest:studentsRequest completionHandler:^(NSData *studentsData, NSURLResponse *studentsResponse, NSError *studentsError) {
            NSHTTPURLResponse *studentsHTTP = (NSHTTPURLResponse *)studentsResponse;
            if (studentsError || studentsHTTP.statusCode < 200 || studentsHTTP.statusCode >= 300) {
                GSCompleteOnMain(^{
                    completion(nil, GSAPIErrorMessage(studentsData, studentsHTTP, studentsError));
                });
                return;
            }
            NSDictionary *studentsJSON = [NSJSONSerialization JSONObjectWithData:studentsData ?: [NSData data] options:0 error:nil];
            NSArray *students = [studentsJSON isKindOfClass:[NSDictionary class]] ? studentsJSON[@"students"] : nil;
            if ([students isKindOfClass:[NSArray class]] && students.count > 0) {
                NSDictionary *student = [students.firstObject isKindOfClass:[NSDictionary class]] ? students.firstObject : nil;
                user.studentId = [NSString stringWithFormat:@"%@", student[@"id"] ?: @""];
            }
            if ([user.role isEqualToString:@"student"] && user.studentId.length == 0) {
                GSCompleteOnMain(^{ completion(nil, @"当前账号没有关联学生档案"); });
                return;
            }
            [[GSCacheManager sharedManager] saveUser:user];
            GSCompleteOnMain(^{ completion(user, nil); });
        }] resume];
        (void)role; // 角色由服务端账号决定，客户端选择不参与鉴权。
    }] resume];
}

- (void)logoutWithCompletion:(void(^)(void))completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/logout", base]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[GSCacheManager sharedManager] logout];
        GSCompleteOnMain(^{ if (completion) completion(); });
    }] resume];
}

- (void)fetchWrongQuestionsForStudent:(NSString *)studentId
                              subject:(nullable NSString *)subject
                           completion:(GSQuestionsCompletion)completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSMutableString *urlStr = [NSMutableString stringWithFormat:@"%@/api/wrong-questions", base];
    if (subject && subject.length > 0 && ![subject isEqualToString:@"全部"]) {
        NSString *encodedSub = [subject stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        [urlStr appendFormat:@"?subject=%@", encodedSub];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 离线自动使用本地缓存兜底
            NSArray<GSWrongQuestion *> *cached = [[GSCacheManager sharedManager] loadLocalWrongQuestions];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached, nil);
            });
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (GSHandleUnauthorized(http)) {
            GSCompleteOnMain(^{ completion(nil, @"登录会话已失效，请重新登录"); });
            return;
        }
        if (http.statusCode >= 500) {
            NSArray<GSWrongQuestion *> *cached = [[GSCacheManager sharedManager] loadLocalWrongQuestions];
            NSString *message = GSAPIErrorMessage(data, http, nil);
            GSCompleteOnMain(^{ completion(cached, message); });
            return;
        }
        if (http.statusCode < 200 || http.statusCode >= 300) {
            GSCompleteOnMain(^{ completion(nil, GSAPIErrorMessage(data, http, nil)); });
            return;
        }

        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        if (jsonErr || (![json isKindOfClass:[NSArray class]] && ![json isKindOfClass:[NSDictionary class]])) {
            GSCompleteOnMain(^{ completion(nil, @"错题列表响应格式异常"); });
            return;
        }
        NSMutableArray<GSWrongQuestion *> *questions = [NSMutableArray array];

        NSArray *list = nil;
        if ([json isKindOfClass:[NSArray class]]) {
            list = (NSArray *)json;
        } else if ([json isKindOfClass:[NSDictionary class]]) {
            list = json[@"wrongQuestions"] ?: json[@"items"] ?: json[@"data"] ?: json[@"questions"];
        }

        if ([list isKindOfClass:[NSArray class]]) {
            for (NSDictionary *dict in list) {
                if ([dict isKindOfClass:[NSDictionary class]]) {
                    [questions addObject:[GSWrongQuestion fromDictionary:dict]];
                }
            }
        }

        // 复习阶段属于 review-schedules 权威域，不能从错题字段自行猜测。
        NSString *base = [GSCacheManager sharedManager].backendHost;
        NSURL *reviewURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/review-schedules", base]];
        [[self->_session dataTaskWithURL:reviewURL completionHandler:^(NSData *reviewData, NSURLResponse *reviewResponse, NSError *reviewError) {
            NSHTTPURLResponse *reviewHTTP = (NSHTTPURLResponse *)reviewResponse;
            if (GSHandleUnauthorized(reviewHTTP)) {
                GSCompleteOnMain(^{ completion(nil, @"登录会话已失效，请重新登录"); });
                return;
            }
            NSString *reviewWarning = nil;
            if (reviewError || reviewHTTP.statusCode < 200 || reviewHTTP.statusCode >= 300) {
                reviewWarning = GSAPIErrorMessage(reviewData, reviewHTTP, reviewError);
            }
            NSDictionary *reviewJSON = (!reviewError && reviewHTTP.statusCode >= 200 && reviewHTTP.statusCode < 300)
                ? [NSJSONSerialization JSONObjectWithData:reviewData ?: [NSData data] options:0 error:nil]
                : nil;
            NSArray *schedules = [reviewJSON[@"reviewSchedules"] isKindOfClass:[NSArray class]] ? reviewJSON[@"reviewSchedules"] : @[];
            if (reviewJSON) {
                for (GSWrongQuestion *question in questions) {
                    NSArray *matching = [schedules filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *schedule, NSDictionary *bindings) {
                        return [schedule[@"wrongQuestionId"] isEqualToString:question.questionId];
                    }]];
                    NSUInteger completedCount = [matching filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *schedule, NSDictionary *bindings) {
                        return [schedule[@"status"] isEqualToString:@"已完成"];
                    }]].count;
                    NSArray *pending = [[matching filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *schedule, NSDictionary *bindings) {
                        return ![schedule[@"status"] isEqualToString:@"已完成"];
                    }]] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
                        return [[NSString stringWithFormat:@"%@", left[@"dueDate"] ?: @""] compare:[NSString stringWithFormat:@"%@", right[@"dueDate"] ?: @""]];
                    }];
                    question.reviewCount = completedCount;
                    question.reviewStage = MIN(6, completedCount + 1);
                    if (pending.count > 0) question.nextReviewDate = [NSString stringWithFormat:@"%@", pending.firstObject[@"dueDate"] ?: @""];
                }
            }
            [[GSCacheManager sharedManager] saveWrongQuestions:questions];
            GSCompleteOnMain(^{ completion([questions copy], reviewWarning); });
        }] resume];
    }] resume];
    (void)studentId;
}

- (void)uploadImageForQuestion:(GSWrongQuestion *)question
                    completion:(void(^)(NSString * _Nullable imageURL, NSInteger statusCode, NSString * _Nullable error))completion {
    if ([question.sourceImageUri hasPrefix:@"/uploads/"]) {
        completion(question.sourceImageUri, 200, nil);
        return;
    }
    UIImage *image = [[GSCacheManager sharedManager] loadImageFromDisk:question.sourceImageUri];
    NSData *imageData = image ? UIImageJPEGRepresentation(image, 0.85) : nil;
    if (imageData.length == 0) {
        completion(nil, 400, @"本地错题图片不存在，无法同步");
        return;
    }

    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSMutableData *body = [NSMutableData data];
    NSString *prefix = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n", boundary];
    [body appendData:[prefix dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:imageData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/upload-image", base]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = body;
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (error || http.statusCode < 200 || http.statusCode >= 300) {
            GSHandleUnauthorized(http);
            completion(nil, http.statusCode, GSAPIErrorMessage(data, http, error));
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSString *imageURL = [json[@"url"] isKindOfClass:[NSString class]] ? json[@"url"] : nil;
        completion(imageURL, imageURL.length > 0 ? 200 : 502, imageURL.length > 0 ? nil : @"图片上传响应缺少 url");
    }] resume];
}

- (void)prepareBatchItems:(NSArray<GSWrongQuestion *> *)questions
                     index:(NSUInteger)index
                     items:(NSMutableArray<NSDictionary *> *)items
                completion:(void(^)(NSArray<NSDictionary *> * _Nullable items, NSInteger statusCode, NSString * _Nullable error))completion {
    if (index >= questions.count) {
        completion([items copy], 200, nil);
        return;
    }
    GSWrongQuestion *question = questions[index];
    if (![[NSUUID alloc] initWithUUIDString:question.clientItemId]) {
        question.clientItemId = [[[NSUUID UUID] UUIDString] lowercaseString];
    }
    [self uploadImageForQuestion:question completion:^(NSString * _Nullable imageURL, NSInteger statusCode, NSString * _Nullable error) {
        if (error) {
            completion(nil, statusCode, error);
            return;
        }
        [items addObject:@{
            @"clientItemId": question.clientItemId,
            @"imageUrl": imageURL ?: @"",
            @"subject": question.subject.length > 0 ? question.subject : @"综合",
            @"knowledgePoint": question.knowledgePoint.length > 0 ? question.knowledgePoint : @"待老师确认",
            @"mistakeCause": question.mistakeCause.length > 0 ? question.mistakeCause : @"待老师确认",
            @"questionTitle": question.questionText ?: @"",
            @"questionType": @"解答题",
            @"originalThought": @"",
            @"correctStart": @"",
            @"variantTask": @""
        }];
        [self prepareBatchItems:questions index:index + 1 items:items completion:completion];
    }];
}

- (void)storeQuestionsOffline:(NSArray<GSWrongQuestion *> *)questions
                       reason:(NSString *)reason
                   completion:(GSBatchUploadCompletion)completion {
    for (GSWrongQuestion *question in questions) {
        [[GSCacheManager sharedManager] addWrongQuestionLocally:question];
        [[GSCacheManager sharedManager] addPendingSyncQuestion:question];
    }
    GSCompleteOnMain(^{ completion(YES, questions.count, reason ?: @"已保存到本地，网络恢复后可手动同步"); });
}

- (void)batchSubmitWrongQuestions:(NSArray<GSWrongQuestion *> *)questions
                        studentId:(NSString *)studentId
                       completion:(GSBatchUploadCompletion)completion {
    if (questions.count == 0) {
        completion(YES, 0, nil);
        return;
    }
    if (studentId.length == 0) {
        completion(NO, 0, @"当前账号没有关联学生档案");
        return;
    }

    [self prepareBatchItems:questions index:0 items:[NSMutableArray array] completion:^(NSArray<NSDictionary *> * _Nullable items, NSInteger prepareStatus, NSString * _Nullable prepareError) {
        if (prepareError) {
            if (prepareStatus == 0 || prepareStatus >= 500) {
                [self storeQuestionsOffline:questions reason:prepareError completion:completion];
            } else {
                GSCompleteOnMain(^{ completion(NO, 0, prepareError); });
            }
            return;
        }
        NSString *base = [GSCacheManager sharedManager].backendHost;
        NSURL *batchURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/students/%@/wrong-questions/batch", base, studentId]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:batchURL];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        NSDictionary *body = @{
            @"clientGroupId": [[[NSUUID UUID] UUIDString] lowercaseString],
            @"source": @"ios_camera",
            @"items": items ?: @[]
        };
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

        [[self->_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (error || http.statusCode < 200 || http.statusCode >= 300) {
                GSHandleUnauthorized(http);
                NSString *message = GSAPIErrorMessage(data, http, error);
                if (error || http.statusCode >= 500) {
                    [self storeQuestionsOffline:questions reason:message completion:completion];
                } else {
                    GSCompleteOnMain(^{ completion(NO, 0, message); });
                }
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
            NSInteger accepted = [json[@"created"] count] + [json[@"skipped"] count];
            for (GSWrongQuestion *question in questions) {
                [[GSCacheManager sharedManager] addWrongQuestionLocally:question];
            }
            GSCompleteOnMain(^{ completion(YES, accepted, nil); });
        }] resume];
    }];
}

- (void)reviewQuestion:(NSString *)questionId
             studentId:(NSString *)studentId
            isMastered:(BOOL)isMastered
            completion:(void(^)(BOOL success, NSString * _Nullable error))completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *listURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/review-schedules", base]];
    [[_session dataTaskWithURL:listURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (error || http.statusCode < 200 || http.statusCode >= 300) {
            GSHandleUnauthorized(http);
            GSCompleteOnMain(^{ completion(NO, GSAPIErrorMessage(data, http, error)); });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSArray *schedules = [json[@"reviewSchedules"] isKindOfClass:[NSArray class]] ? json[@"reviewSchedules"] : @[];
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *schedule, NSDictionary *bindings) {
            return [schedule[@"wrongQuestionId"] isEqualToString:questionId] && ![schedule[@"status"] isEqualToString:@"已完成"];
        }];
        NSArray *pending = [[schedules filteredArrayUsingPredicate:predicate] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSString *leftDate = [left[@"dueDate"] isKindOfClass:[NSString class]] ? left[@"dueDate"] : @"";
            NSString *rightDate = [right[@"dueDate"] isKindOfClass:[NSString class]] ? right[@"dueDate"] : @"";
            return [leftDate compare:rightDate];
        }];
        NSDictionary *schedule = pending.firstObject;
        NSString *scheduleId = [schedule[@"id"] isKindOfClass:[NSString class]] ? schedule[@"id"] : nil;
        if (scheduleId.length == 0) {
            GSCompleteOnMain(^{ completion(NO, @"没有待完成的复习计划"); });
            return;
        }
        NSURL *completeURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/review-schedules/%@/complete", base, scheduleId]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:completeURL];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        NSDictionary *body = @{
            @"result": isMastered ? @"已独立完成" : @"仍需复习",
            @"note": @"iOS 错题本复习提交"
        };
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [[self->_session dataTaskWithRequest:request completionHandler:^(NSData *completeData, NSURLResponse *completeResponse, NSError *completeError) {
            NSHTTPURLResponse *completeHTTP = (NSHTTPURLResponse *)completeResponse;
            GSHandleUnauthorized(completeHTTP);
            BOOL ok = !completeError && completeHTTP.statusCode >= 200 && completeHTTP.statusCode < 300;
            GSCompleteOnMain(^{ completion(ok, ok ? nil : GSAPIErrorMessage(completeData, completeHTTP, completeError)); });
        }] resume];
    }] resume];
    (void)studentId;
}

- (void)deleteWrongQuestion:(NSString *)questionId
                 completion:(void(^)(BOOL success, NSString * _Nullable error))completion {
    if (!questionId) {
        if (completion) completion(NO, @"ID为空");
        return;
    }
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/wrong-questions/%@", base, questionId]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"DELETE";

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        GSHandleUnauthorized(httpResp);
        BOOL ok = (!error && httpResp.statusCode >= 200 && httpResp.statusCode < 300);
        GSCompleteOnMain(^{
            if (completion) completion(ok, ok ? nil : GSAPIErrorMessage(data, httpResp, error));
        });
    }] resume];
}

- (void)updateWrongQuestion:(NSString *)questionId
                    subject:(nullable NSString *)subject
             knowledgePoint:(nullable NSString *)knowledgePoint
               mistakeCause:(nullable NSString *)mistakeCause
              questionTitle:(nullable NSString *)questionTitle
                 completion:(void(^)(BOOL success, NSString * _Nullable error))completion {
    if (!questionId) {
        if (completion) completion(NO, @"ID为空");
        return;
    }
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/wrong-questions/%@", base, questionId]];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"PATCH";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if (subject) body[@"subject"] = subject;
    if (knowledgePoint) body[@"knowledgePoint"] = knowledgePoint;
    if (mistakeCause) body[@"mistakeCause"] = mistakeCause;
    if (questionTitle) body[@"questionTitle"] = questionTitle;

    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        GSHandleUnauthorized(httpResp);
        BOOL ok = (!error && httpResp.statusCode >= 200 && httpResp.statusCode < 300);
        GSCompleteOnMain(^{
            if (completion) completion(ok, ok ? nil : GSAPIErrorMessage(data, httpResp, error));
        });
    }] resume];
}

- (void)fetchSimilarQuestionsForSubject:(NSString *)subject
                         knowledgePoint:(NSString *)knowledgePoint
                              completion:(GSSimilarQuestionsCompletion)completion {
    NSString *base = [GSCacheManager sharedManager].backendHost;
    NSURL *capabilitiesURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/mobile-capabilities", base]];
    [[_session dataTaskWithURL:capabilitiesURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (error || http.statusCode < 200 || http.statusCode >= 300) {
            GSCompleteOnMain(^{ completion(nil, GSAPIErrorMessage(data, http, error)); });
            return;
        }
        id parsed = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSDictionary *contract = [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
        NSDictionary *capabilities = [contract[@"capabilities"] isKindOfClass:[NSDictionary class]] ? contract[@"capabilities"] : nil;
        NSDictionary *capability = [capabilities[@"similarQuestions"] isKindOfClass:[NSDictionary class]]
            ? capabilities[@"similarQuestions"] : nil;
        if (![capability[@"status"] isEqualToString:@"available"]) {
            GSCompleteOnMain(^{ completion(@[], nil); });
            return;
        }

        NSString *path = [capability[@"path"] isKindOfClass:[NSString class]] ? capability[@"path"] : @"/api/questions/similar";
        NSURLComponents *components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"%@%@", base, path]];
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"subject" value:subject ?: @""],
            [NSURLQueryItem queryItemWithName:@"knowledgePoint" value:knowledgePoint ?: @""],
            [NSURLQueryItem queryItemWithName:@"limit" value:@"3"]
        ];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
        request.HTTPMethod = @"GET";
        [[self->_session dataTaskWithRequest:request completionHandler:^(NSData *questionData, NSURLResponse *questionResponse, NSError *questionError) {
            NSHTTPURLResponse *questionHTTP = (NSHTTPURLResponse *)questionResponse;
            if (GSHandleUnauthorized(questionHTTP)) {
                GSCompleteOnMain(^{ completion(nil, @"登录会话已失效，请重新登录"); });
                return;
            }
            if (questionError || questionHTTP.statusCode < 200 || questionHTTP.statusCode >= 300) {
                GSCompleteOnMain(^{ completion(nil, GSAPIErrorMessage(questionData, questionHTTP, questionError)); });
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:questionData ?: [NSData data] options:0 error:nil];
            NSArray *items = [json[@"questions"] isKindOfClass:[NSArray class]] ? json[@"questions"] : nil;
            if (!items) {
                GSCompleteOnMain(^{ completion(nil, @"相似题响应格式异常"); });
                return;
            }
            NSMutableArray<GSSimilarQuestion *> *questions = [NSMutableArray array];
            for (NSDictionary *item in items) {
                if ([item isKindOfClass:[NSDictionary class]]) [questions addObject:[GSSimilarQuestion fromDictionary:item]];
            }
            GSCompleteOnMain(^{ completion([questions copy], nil); });
        }] resume];
    }] resume];
}

@end
