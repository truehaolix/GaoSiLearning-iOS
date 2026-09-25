#import <Foundation/Foundation.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^GSAiAnalysisCompletion)(GSAiAnalysisResult * _Nullable result, NSString * _Nullable error);

@interface GSOllamaClient : NSObject

+ (instancetype)sharedClient;

/// 异步调用大模型进行深度解析与精准变式生成 (默认 Qwen 27B)
- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion;

/// 异步调用 Qwen 27B 大模型生成名师步骤详解与易错避坑反思
- (void)requestStepByStepSolutionForText:(NSString *)questionText
                                 subject:(NSString *)subject
                          knowledgePoint:(NSString *)knowledgePoint
                              completion:(void(^)(NSString *solution, NSString * _Nullable error))completion;

/// 异步调用 Qwen 27B 大模型对全量错题进行 AI 考点聚类与薄弱项归类诊断
- (void)requestKnowledgeClusteringForText:(NSString *)summaryText
                               completion:(void(^)(NSString *report, NSString * _Nullable error))completion;

/// 快速本地启发式学科判断 (毫秒级先发显示)
+ (NSString *)detectSubjectLocally:(NSString *)text;

/// 快速本地启发式知识点提取
+ (NSString *)detectKnowledgePointLocally:(NSString *)text subject:(NSString *)subject;

/// 快速本地启发式错因推断
+ (NSString *)suggestMistakeCauseLocally:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
