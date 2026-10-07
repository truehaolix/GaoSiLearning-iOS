#import <Foundation/Foundation.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^GSAiAnalysisCompletion)(GSAiAnalysisResult * _Nullable result, NSString * _Nullable error);

@interface GSOllamaClient : NSObject

+ (instancetype)sharedClient;

/// 使用本地规则完成学科、考点、错因初判并生成基础练习。
- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion;

/// 生成明确标记的本地学习步骤提示。
- (void)requestStepByStepSolutionForText:(NSString *)questionText
                                 subject:(NSString *)subject
                          knowledgePoint:(NSString *)knowledgePoint
                              completion:(void(^)(NSString *solution, NSString * _Nullable error))completion;

/// 根据本地错题摘要生成整理建议。
- (void)requestKnowledgeClusteringForText:(NSString *)summaryText
                               completion:(void(^)(NSString *report, NSString * _Nullable error))completion;

/// 根据年级与本地薄弱点生成端侧打卡模板。
- (void)requestCheckInContentForGrade:(NSString *)grade
                      knowledgePoints:(NSArray<NSString *> *)kps
                           completion:(void(^)(NSDictionary * _Nullable data, NSString * _Nullable error))completion;

/// 快速本地启发式学科判断 (毫秒级先发显示)
+ (NSString *)detectSubjectLocally:(NSString *)text;

/// 快速本地启发式知识点提取
+ (NSString *)detectKnowledgePointLocally:(NSString *)text subject:(NSString *)subject;

/// 快速本地启发式错因推断
+ (NSString *)suggestMistakeCauseLocally:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
