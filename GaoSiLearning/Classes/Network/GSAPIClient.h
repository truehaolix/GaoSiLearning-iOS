#import <Foundation/Foundation.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^GSLoginCompletion)(GSUser * _Nullable user, NSString * _Nullable error);
typedef void(^GSQuestionsCompletion)(NSArray<GSWrongQuestion *> * _Nullable questions, NSString * _Nullable error);
typedef void(^GSBatchUploadCompletion)(BOOL success, NSInteger uploadedCount, NSString * _Nullable error);

@interface GSAPIClient : NSObject

+ (instancetype)sharedClient;

/// 登录认证接口
- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
                     role:(NSString *)role
               completion:(GSLoginCompletion)completion;

/// 查询错题列表 (支持学科过滤)
- (void)fetchWrongQuestionsForStudent:(NSString *)studentId
                              subject:(nullable NSString *)subject
                           completion:(GSQuestionsCompletion)completion;

/// 批量提交错题 (自动生成 6 阶段艾宾浩斯复习计划)
- (void)batchSubmitWrongQuestions:(NSArray<GSWrongQuestion *> *)questions
                        studentId:(NSString *)studentId
                       completion:(GSBatchUploadCompletion)completion;

/// 标记单道错题复习完成 (推进艾宾浩斯阶段)
- (void)reviewQuestion:(NSString *)questionId
             studentId:(NSString *)studentId
            isMastered:(BOOL)isMastered
            completion:(void(^)(BOOL success, NSString * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
