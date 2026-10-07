#import "GSOllamaClient.h"

@implementation GSOllamaClient

+ (instancetype)sharedClient {
    static GSOllamaClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSOllamaClient alloc] init];
    });
    return instance;
}

- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion {
    if (ocrText.length == 0) {
        if (completion) completion(nil, @"题干为空");
        return;
    }

    GSAiAnalysisResult *result = [[GSAiAnalysisResult alloc] init];
    result.subject = [GSOllamaClient detectSubjectLocally:ocrText];
    result.knowledgePoint = [GSOllamaClient detectKnowledgePointLocally:ocrText subject:result.subject];
    result.mistakeCause = [GSOllamaClient suggestMistakeCauseLocally:ocrText];

    GSSimilarQuestion *question = [[GSSimilarQuestion alloc] init];
    question.questionId = [NSString stringWithFormat:@"local_%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    question.stem = [NSString stringWithFormat:@"请根据“%@”的定义和适用条件，判断下列说法是否成立。", result.knowledgePoint];
    question.options = @[
        [GSQuestionOption optionWithKey:@"A" content:@"先核对定义与适用条件再判断"],
        [GSQuestionOption optionWithKey:@"B" content:@"可以忽略题目中的限制条件"],
        [GSQuestionOption optionWithKey:@"C" content:@"计算后不需要检查结果范围"],
        [GSQuestionOption optionWithKey:@"D" content:@"只需记住结论，无需理解推导"]
    ];
    question.answer = @"A";
    question.analysis = [NSString stringWithFormat:@"本题用于复习 %@ 的基本定义、适用范围和检查步骤。", result.knowledgePoint];
    question.difficulty = @"基础";
    question.source = @"本地规则题库";
    result.similarQuestions = @[question];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(result, nil);
    });
}

- (void)requestStepByStepSolutionForText:(NSString *)questionText
                                 subject:(NSString *)subject
                          knowledgePoint:(NSString *)knowledgePoint
                              completion:(void(^)(NSString *solution, NSString * _Nullable error))completion {
    NSString *solution = questionText.length == 0
        ? @"暂无题目内容，无法生成学习提示。"
        : [NSString stringWithFormat:
            @"【本地学习提示】\n本题考查【%@ - %@】。\n"
             @"1. 先圈出已知量、所求量和限制条件；\n"
             @"2. 写出对应定义、公式或推理依据，再分步计算；\n"
             @"3. 完成后检查定义域、单位、符号和边界条件。",
            subject.length > 0 ? subject : @"综合",
            knowledgePoint.length > 0 ? knowledgePoint : @"重点知识"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(solution, nil);
    });
}

- (void)requestKnowledgeClusteringForText:(NSString *)summaryText
                               completion:(void(^)(NSString *report, NSString * _Nullable error))completion {
    NSString *report = summaryText.length == 0
        ? @"暂无错题数据，无法生成整理建议。"
        : @"【本地错题整理建议】\n"
           @"1. 按学科和知识点统计错题数量，先处理高频薄弱项；\n"
           @"2. 对照错因区分概念、审题、计算和方法选择问题；\n"
           @"3. 每个薄弱知识点完成订正、同类练习和间隔复习。";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(report, nil);
    });
}

- (void)requestCheckInContentForGrade:(NSString *)grade
                      knowledgePoints:(NSArray<NSString *> *)knowledgePoints
                           completion:(void(^)(NSDictionary * _Nullable data, NSString * _Nullable error))completion {
    NSString *target = nil;
    for (NSString *item in knowledgePoints) {
        if (item.length > 0 && ![item isEqualToString:@"未分类"] && ![item isEqualToString:@"全部"]) {
            target = item;
            break;
        }
    }
    if (target.length == 0) {
        if ([grade containsString:@"高一"]) target = @"平面向量数量积与坐标运算";
        else if ([grade containsString:@"高二"]) target = @"导数的几何意义与单调性";
        else if ([grade containsString:@"初中"]) target = @"二次函数图像与最值";
        else target = @"函数与方程综合应用";
    }

    NSDictionary *data = @{
        @"knowledgePoint": target,
        @"grade": grade.length > 0 ? grade : @"高中",
        @"summary": [NSString stringWithFormat:@"今日围绕“%@”完成一次概念回忆、一道基础题和一道变式题，并把错因写成可执行的检查动作。", target],
        @"keyFormulas": @"先写定义与适用条件，再分步推导；完成后检查单位、符号、定义域和边界。",
        @"commonTraps": @"1. 忽略限制条件；\n2. 直接套用公式但未检查适用范围；\n3. 完成后未回看单位、符号或边界。",
        @"questions": @[
            @{
                @"title": @"基础巩固",
                @"stem": [NSString stringWithFormat:@"复习“%@”时，以下哪种做法最完整？", target],
                @"options": @[@"A. 同时核对定义、适用条件和例子", @"B. 只记住最终结论", @"C. 忽略限制条件直接套公式", @"D. 做完后不检查结果"],
                @"answer": @"A",
                @"explanation": @"先用自己的话复述，再对照教材或课堂笔记补全遗漏条件。"
            },
            @{
                @"title": @"错因复盘",
                @"stem": [NSString stringWithFormat:@"重做与“%@”相关的错题后，最有效的下一步是什么？", target],
                @"options": @[@"A. 标出首次错误并写成下次检查动作", @"B. 只抄正确答案", @"C. 立即删除错题", @"D. 跳过原因直接做新题"],
                @"answer": @"A",
                @"explanation": @"把错误改写为下一次可执行的检查动作。"
            }
        ]
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(data, nil);
    });
}

+ (NSString *)detectSubjectLocally:(NSString *)text {
    NSString *normalized = text.lowercaseString;
    if ([normalized containsString:@"牛顿"] || [normalized containsString:@"加速度"] || [normalized containsString:@"电流"] || [normalized containsString:@"磁场"]) return @"物理";
    if ([normalized containsString:@"摩尔"] || [normalized containsString:@"离子"] || [normalized containsString:@"氧化"] || [normalized containsString:@"沉淀"]) return @"化学";
    if ([normalized containsString:@"细胞"] || [normalized containsString:@"基因"] || [normalized containsString:@"遗传"] || [normalized containsString:@"dna"]) return @"生物";
    if ([normalized containsString:@"文言文"] || [normalized containsString:@"古诗"] || [normalized containsString:@"修辞"] || [normalized containsString:@"主旨"]) return @"语文";
    if ([normalized rangeOfString:@"\\b(the|which|because|passage)\\b" options:NSRegularExpressionSearch].location != NSNotFound) return @"英语";
    return @"数学";
}

+ (NSString *)detectKnowledgePointLocally:(NSString *)text subject:(NSString *)subject {
    NSString *normalized = text.lowercaseString;
    if ([normalized containsString:@"导数"] || [normalized containsString:@"切线"]) return @"导数的几何意义与单调性";
    if ([normalized containsString:@"向量"]) return @"平面向量数量积与坐标运算";
    if ([normalized containsString:@"三角"] || [normalized containsString:@"sin"] || [normalized containsString:@"cos"]) return @"三角函数图像与性质";
    if ([normalized containsString:@"牛顿"] || [normalized containsString:@"加速度"]) return @"牛顿运动定律与受力分析";
    if ([normalized containsString:@"离子"] || [normalized containsString:@"沉淀"]) return @"离子反应与溶液平衡";
    if ([normalized containsString:@"遗传"] || [normalized containsString:@"基因"]) return @"遗传规律与基因表达";
    return [NSString stringWithFormat:@"%@综合应用", subject.length > 0 ? subject : @"重点知识"];
}

+ (NSString *)suggestMistakeCauseLocally:(NSString *)text {
    NSString *normalized = text.lowercaseString;
    if ([normalized containsString:@"错误的是"] || [normalized containsString:@"不正确"] || [normalized containsString:@"不满足"]) return @"审题不清，遗漏否定词或限制条件";
    if ([normalized containsString:@"定义"] || [normalized containsString:@"性质"] || [normalized containsString:@"概念"]) return @"核心概念和适用条件掌握不牢";
    if ([normalized containsString:@"计算"] || [normalized containsString:@"="]) return @"计算或符号处理不规范";
    return @"解题起点不明确，缺少条件到方法的转化";
}

@end
