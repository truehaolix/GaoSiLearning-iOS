#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface GSCacheManager : NSObject

@property (nonatomic, copy) NSString *backendHost;
@property (nonatomic, copy) NSString *ollamaHost;
@property (nonatomic, strong, nullable) GSUser *currentUser;

+ (instancetype)sharedManager;

- (BOOL)isLoggedIn;
- (void)saveUser:(GSUser *)user;
- (void)logout;

// 错题本地持久化与离线缓存
- (NSArray<GSWrongQuestion *> *)loadLocalWrongQuestions;
- (void)saveWrongQuestions:(NSArray<GSWrongQuestion *> *)questions;
- (void)addWrongQuestionLocally:(GSWrongQuestion *)question;
- (void)deleteWrongQuestionLocally:(NSString *)questionId;
- (void)updateWrongQuestionLocally:(NSString *)questionId
                           subject:(nullable NSString *)subject
                    knowledgePoint:(nullable NSString *)knowledgePoint
                      mistakeCause:(nullable NSString *)mistakeCause
                      questionText:(nullable NSString *)questionText;

// 离线待同步队列
- (NSArray<GSWrongQuestion *> *)loadPendingSyncQuestions;
- (void)addPendingSyncQuestion:(GSWrongQuestion *)question;
- (void)clearPendingSyncQuestions;

// 错题图片本地文件系统存取
- (NSString *)saveImageToDisk:(UIImage *)image;
- (nullable UIImage *)loadImageFromDisk:(NSString *)fileNameOrPath;

@end

NS_ASSUME_NONNULL_END
