#import "GSCacheManager.h"

static NSString * const kKeyBackendHost = @"gs_backend_host";
static NSString * const kKeyOllamaHost  = @"gs_ollama_host";
static NSString * const kKeyUserArchive = @"gs_current_user_archive";
static NSString * const kDefaultBackend = @"http://112.46.82.154:4174";
static NSString * const kDefaultOllama  = @"http://112.46.82.154:11434";

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
        _ollamaHost = [ud stringForKey:kKeyOllamaHost] ?: kDefaultOllama;

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

- (void)setOllamaHost:(NSString *)ollamaHost {
    _ollamaHost = [ollamaHost copy];
    [[NSUserDefaults standardUserDefaults] setObject:_ollamaHost forKey:kKeyOllamaHost];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isLoggedIn {
    return (self.currentUser != nil && self.currentUser.token.length > 0);
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
        [list insertObject:question atIndex:0];
        [self saveWrongQuestions:list];
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
