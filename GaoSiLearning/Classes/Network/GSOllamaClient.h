#import <Foundation/Foundation.h>
#import "GSModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^GSAiAnalysisCompletion)(GSAiAnalysisResult * _Nullable result, NSString * _Nullable error);

@interface GSOllamaClient : NSObject

+ (instancetype)sharedClient;

/// 异步调用大模型进行深度解析与精准变式生成 (默认 Qwen 27B)
- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion;

/// 快速本地启发式学科判断 (毫秒级先发显示)
+ (NSString *)detectSubjectLocally:(NSString *)text;

/// 快速本地启发式知识点提取
+ (NSString *)detectKnowledgePointLocally:(NSString *)text subject:(NSString *)subject;

/// 快速本地启发式错因推断
+ (NSString *)suggestMistakeCauseLocally:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
