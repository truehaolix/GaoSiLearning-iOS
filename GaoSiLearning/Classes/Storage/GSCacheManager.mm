#import "GSCacheManager.h"

static NSString * const kKeyBackendHost = @"gs_backend_host";
static NSString * const kKeyUserArchive = @"gs_current_user_archive";
static NSString * const kDefaultBackend = @"http://112.46.82.154:4174";

@implementation GSCacheManager {
    NSString *_documentsPath;
    NSString *_imagesDirPath;
    NSString *_questionsFilePath;
    NSString *_pendingSyncFilePath;
}

+ (instancetype)sharedManager {
    static GSCacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSCacheManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _documentsPath = paths.firstObject;
        _imagesDirPath = [_documentsPath stringByAppendingPathComponent:@"question_images"];
        _questionsFilePath = [_documentsPath stringByAppendingPathComponent:@"wrong_questions.json"];
        _pendingSyncFilePath = [_documentsPath stringByAppendingPathComponent:@"pending_sync.json"];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:_imagesDirPath]) {
            [fm createDirectoryAtPath:_imagesDirPath withIntermediateDirectories:YES attributes:nil error:nil];
        }

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        _backendHost = [ud stringForKey:kKeyBackendHost] ?: kDefaultBackend;

        NSData *userData = [ud objectForKey:kKeyUserArchive];
        if (userData) {
            NSError *err = nil;
            _currentUser = [NSKeyedUnarchiver unarchivedObjectOfClass:[GSUser class] fromData:userData error:&err];
        }
    }
    return self;
}

- (void)setBackendHost:(NSString *)backendHost {
    _backendHost = [backendHost copy];
    [[NSUserDefaults standardUserDefaults] setObject:_backendHost forKey:kKeyBackendHost];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isLoggedIn {
    if (!self.currentUser) return NO;
    NSURL *url = [NSURL URLWithString:self.backendHost];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url]) {
        if ([cookie.name isEqualToString:@"session"] && cookie.value.length > 0) return YES;
    }
    return NO;
}

- (void)saveUser:(GSUser *)user {
    self.currentUser = user;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (user) {
        NSError *err = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:user requiringSecureCoding:YES error:&err];
        [ud setObject:data forKey:kKeyUserArchive];
    } else {
        [ud removeObjectForKey:kKeyUserArchive];
    }
    [ud synchronize];
}

- (void)logout {
    NSURL *url = [NSURL URLWithString:self.backendHost];
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookiesForURL:url]) {
        if ([cookie.name isEqualToString:@"session"]) [storage deleteCookie:cookie];
    }
    [self saveUser:nil];
}

#pragma mark - 错题存储与读取

- (NSArray<GSWrongQuestion *> *)loadLocalWrongQuestions {
    @synchronized (self) {
        NSData *data = [NSData dataWithContentsOfFile:_questionsFilePath];
        if (!data) return @[];
        NSError *err = nil;
        NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![jsonArray isKindOfClass:[NSArray class]]) return @[];

        NSMutableArray<GSWrongQuestion *> *result = [NSMutableArray array];
        for (NSDictionary *dict in jsonArray) {
            if ([dict isKindOfClass:[NSDictionary class]]) {
                [result addObject:[GSWrongQuestion fromDictionary:dict]];
            }
        }
        return [result copy];
    }
}

- (void)saveWrongQuestions:(NSArray<GSWrongQuestion *> *)questions {
    @synchronized (self) {
        NSMutableArray *arr = [NSMutableArray array];
        for (GSWrongQuestion *q in questions) {
            [arr addObject:[q toDictionary]];
        }
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:&err];
        [data writeToFile:_questionsFilePath atomically:YES];
    }
}

- (void)addWrongQuestionLocally:(GSWrongQuestion *)question {
    @synchronized (self) {
        NSMutableArray<GSWrongQuestion *> *list = [[self loadLocalWrongQuestions] mutableCopy];
        NSIndexSet *duplicates = [list indexesOfObjectsPassingTest:^BOOL(GSWrongQuestion *obj, NSUInteger idx, BOOL *stop) {
            BOOL sameServerId = question.questionId.length > 0 && [obj.questionId isEqualToString:question.questionId];
            BOOL sameClientId = question.clientItemId.length > 0 && [obj.clientItemId isEqualToString:question.clientItemId];
            return sameServerId || sameClientId;
        }];
        [list removeObjectsAtIndexes:duplicates];
        [list insertObject:question atIndex:0];
        [self saveWrongQuestions:list];
    }
}

- (void)deleteWrongQuestionLocally:(NSString *)questionId {
    if (!questionId) return;
    @synchronized (self) {
        NSMutableArray<GSWrongQuestion *> *list = [[self loadLocalWrongQuestions] mutableCopy];
        NSUInteger idx = [list indexOfObjectPassingTest:^BOOL(GSWrongQuestion * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.questionId isEqualToString:questionId];
        }];
        if (idx != NSNotFound) {
            [list removeObjectAtIndex:idx];
            [self saveWrongQuestions:list];
        }
    }
}

- (void)updateWrongQuestionLocally:(NSString *)questionId
                           subject:(nullable NSString *)subject
                    knowledgePoint:(nullable NSString *)knowledgePoint
                      mistakeCause:(nullable NSString *)mistakeCause
                      questionText:(nullable NSString *)questionText {
    if (!questionId) return;
    @synchronized (self) {
        NSMutableArray<GSWrongQuestion *> *list = [[self loadLocalWrongQuestions] mutableCopy];
        NSUInteger idx = [list indexOfObjectPassingTest:^BOOL(GSWrongQuestion * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.questionId isEqualToString:questionId];
        }];
        if (idx != NSNotFound) {
            GSWrongQuestion *q = list[idx];
            if (subject) q.subject = subject;
            if (knowledgePoint) q.knowledgePoint = knowledgePoint;
            if (mistakeCause) q.mistakeCause = mistakeCause;
            if (questionText) q.questionText = questionText;
            [self saveWrongQuestions:list];
        }
    }
}

#pragma mark - 待同步队列

- (NSArray<GSWrongQuestion *> *)loadPendingSyncQuestions {
    @synchronized (self) {
        NSData *data = [NSData dataWithContentsOfFile:_pendingSyncFilePath];
        if (!data) return @[];
        NSError *err = nil;
        NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![jsonArray isKindOfClass:[NSArray class]]) return @[];

        NSMutableArray<GSWrongQuestion *> *result = [NSMutableArray array];
        for (NSDictionary *dict in jsonArray) {
            if ([dict isKindOfClass:[NSDictionary class]]) {
                [result addObject:[GSWrongQuestion fromDictionary:dict]];
            }
        }
        return [result copy];
    }
}

- (void)addPendingSyncQuestion:(GSWrongQuestion *)question {
    @synchronized (self) {
        NSMutableArray<GSWrongQuestion *> *list = [[self loadPendingSyncQuestions] mutableCopy];
        if (question.clientItemId.length > 0 && [list indexOfObjectPassingTest:^BOOL(GSWrongQuestion *obj, NSUInteger idx, BOOL *stop) {
            return [obj.clientItemId isEqualToString:question.clientItemId];
        }] != NSNotFound) {
            return;
        }
        [list addObject:question];
        NSMutableArray *arr = [NSMutableArray array];
        for (GSWrongQuestion *q in list) {
            [arr addObject:[q toDictionary]];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
        [data writeToFile:_pendingSyncFilePath atomically:YES];
    }
}

- (void)clearPendingSyncQuestions {
    @synchronized (self) {
        [[NSFileManager defaultManager] removeItemAtPath:_pendingSyncFilePath error:nil];
    }
}

#pragma mark - 图片存取

- (NSString *)saveImageToDisk:(UIImage *)image {
    if (!image) return @"";
    NSString *fileName = [NSString stringWithFormat:@"crop_%@.jpg", [[NSUUID UUID] UUIDString]];
    NSString *fullPath = [_imagesDirPath stringByAppendingPathComponent:fileName];
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    [data writeToFile:fullPath atomically:YES];
    return fileName;
}

- (nullable UIImage *)loadImageFromDisk:(NSString *)fileNameOrPath {
    if (!fileNameOrPath || fileNameOrPath.length == 0) return nil;
    NSString *fullPath = fileNameOrPath;
    if (![fileNameOrPath containsString:@"/"]) {
        fullPath = [_imagesDirPath stringByAppendingPathComponent:fileNameOrPath];
    }
    return [UIImage imageWithContentsOfFile:fullPath];
}

@end
