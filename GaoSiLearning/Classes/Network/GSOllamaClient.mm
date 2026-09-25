#import "GSOllamaClient.h"
#import "GSCacheManager.h"

static NSString * const kModel27B = @"qwen3.8:27b-bf16";
static NSString * const kModel8B  = @"qwen3:8b";

@implementation GSOllamaClient {
    NSURLSession *_session;
}

+ (NSDictionary *)defaultOllamaOptionsWithTemperature:(float)temperature numPredict:(NSInteger)numPredict {
    return @{
        @"temperature": @(temperature),
        @"num_ctx": @4096,
        @"top_p": @0.85,
        @"repeat_penalty": @1.1,
        @"num_predict": @(numPredict)
    };
}

+ (NSString *)cleanContentFromMessage:(NSDictionary *)messageDict {
    if (![messageDict isKindOfClass:[NSDictionary class]]) return @"";
    NSString *content = messageDict[@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        NSString *thinking = messageDict[@"thinking"];
        if ([thinking isKindOfClass:[NSString class]] && thinking.length > 0) {
            NSArray *markers = @[@"最终答案：", @"最终答案:", @"解析如下：", @"综上所述，", @"综上，", @"总结："];
            for (NSString *marker in markers) {
                NSRange r = [thinking rangeOfString:marker options:NSBackwardsSearch];
                if (r.location != NSNotFound) {
                    content = [thinking substringFromIndex:r.location];
                    break;
                }
            }
            if (!content || content.length == 0) {
                content = thinking;
            }
        }
    }
    if (!content) return @"";

    // 移除可能存在的 <think> 思考标签
    NSRegularExpression *thinkRegex = [NSRegularExpression regularExpressionWithPattern:@"<think>[\\s\\S]*?</think>" options:0 error:nil];
    content = [thinkRegex stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];

    // 清理 markdown 代码块包裹
    NSString *cleaned = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleaned hasPrefix:@"```json"]) {
        cleaned = [cleaned substringFromIndex:7];
    } else if ([cleaned hasPrefix:@"```markdown"]) {
        cleaned = [cleaned substringFromIndex:11];
    } else if ([cleaned hasPrefix:@"```"]) {
        cleaned = [cleaned substringFromIndex:3];
    }
    if ([cleaned hasSuffix:@"```"]) {
        cleaned = [cleaned substringToIndex:cleaned.length - 3];
    }
    return [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (instancetype)sharedClient {
    static GSOllamaClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSOllamaClient alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion {
    if (ocrText.length == 0) {
        if (completion) completion(nil, @"题干为空");
        return;
    }

    // 1. 优先尝试 27B 旗舰模型
    [self executeAiAnalysisWithModel:kModel27B text:ocrText completion:^(GSAiAnalysisResult *res, NSString *err) {
        if (res) {
            if (completion) completion(res, nil);
            return;
        }

        // 2. 自动降级尝试 8B 极速模型
        [self executeAiAnalysisWithModel:kModel8B text:ocrText completion:^(GSAiAnalysisResult *res8b, NSString *err8b) {
            if (res8b) {
                if (completion) completion(res8b, nil);
                return;
            }

            // 3. 兜底使用本地规则库
            dispatch_async(dispatch_get_main_queue(), ^{
                GSAiAnalysisResult *localRes = [self buildFallbackResultForText:ocrText];
                if (completion) completion(localRes, nil);
            });
        }];
    }];
}

- (void)executeAiAnalysisWithModel:(NSString *)model
                              text:(NSString *)ocrText
                        completion:(GSAiAnalysisCompletion)completion {
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = @"你是一个全国资深特级教研名师与高斯知衡AI学情分析专家。请对学生错题进行深度学情诊断与变式题设计。\n"
        @"要求：\n"
        @"1. 学科必须精准判断：数学、物理、化学、生物、英语、语文之一；\n"
        @"2. 核心考点：定位到具体三级考点（如“椭圆离心率与几何性质”、“导数构造辅助函数与零点存在性”等），切勿宽泛；\n"
        @"3. 错因剖析：深入推断学生思维盲区、公式死记硬背、忽视隐含条件或分类讨论不全等认知根因（20-40字）；\n"
        @"4. 变式题目：生成1-2道梯度合理的优质同类变式单选题，选项包含典型干扰项与易错诱饵，数学公式必须严格使用标准LaTeX语法（行内用 $...$，独立用 $$...$$，公式内严禁出现中文汉字）。\n\n"
        @"必须以纯 JSON 格式输出，不要包含任何前后缀、注释或代码块标记：\n"
        @"{\n"
        @"  \"subject\": \"数学\",\n"
        @"  \"knowledgePoint\": \"具体三级考点名称\",\n"
        @"  \"mistakeCause\": \"精准错因与思维卡点剖析\",\n"
        @"  \"similarQuestions\": [\n"
        @"    {\n"
        @"      \"id\": \"sim_1\",\n"
        @"      \"stem\": \"题目题干（若含公式必须用标准 LaTeX $...$ 表达）\",\n"
        @"      \"options\": [\n"
        @"        {\"key\": \"A\", \"content\": \"选项A内容\"},\n"
        @"        {\"key\": \"B\", \"content\": \"选项B内容\"},\n"
        @"        {\"key\": \"C\", \"content\": \"选项C内容\"},\n"
        @"        {\"key\": \"D\", \"content\": \"选项D内容\"}\n"
        @"      ],\n"
        @"      \"answer\": \"A\",\n"
        @"      \"analysis\": \"名师分步解题思路与解析，标明突破口与易错点\",\n"
        @"      \"difficulty\": \"中等\",\n"
        @"      \"source\": \"高斯知衡 AI 变式库\"\n"
        @"    }\n"
        @"  ]\n"
        @"}";

    NSDictionary *payload = @{
        @"model": model ?: kModel27B,
        @"stream": @NO,
        @"format": @"json",
        @"keep_alive": @"24h",
        @"options": [GSOllamaClient defaultOllamaOptionsWithTemperature:0.2f numPredict:2048],
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user", @"content": ocrText }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error.localizedDescription ?: @"网络异常");
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *cleaned = [GSOllamaClient cleanContentFromMessage:root[@"message"]];

        if (cleaned.length == 0) {
            completion(nil, @"大模型返回空响应");
            return;
        }

        NSData *cleanData = [cleaned dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *parsedJson = [NSJSONSerialization JSONObjectWithData:cleanData options:0 error:nil];

        if ([parsedJson isKindOfClass:[NSDictionary class]]) {
            GSAiAnalysisResult *result = [GSAiAnalysisResult fromDictionary:parsedJson];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
        } else {
            completion(nil, @"JSON 解析失败");
        }
    }] resume];
}

- (GSAiAnalysisResult *)buildFallbackResultForText:(NSString *)text {
    GSAiAnalysisResult *res = [[GSAiAnalysisResult alloc] init];
    res.subject = [GSOllamaClient detectSubjectLocally:text];
    res.knowledgePoint = [GSOllamaClient detectKnowledgePointLocally:text subject:res.subject];
    res.mistakeCause = [GSOllamaClient suggestMistakeCauseLocally:text];

    GSSimilarQuestion *sim = [[GSSimilarQuestion alloc] init];
    sim.questionId = [NSString stringWithFormat:@"sim_%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    sim.stem = [NSString stringWithFormat:@"已知关于 %@ 的基础概念，下列说法正确的是：", res.knowledgePoint];
    sim.options = @[
        [GSQuestionOption optionWithKey:@"A" content:@"考查核心概念与公理公式"],
        [GSQuestionOption optionWithKey:@"B" content:@"概念在极值临界点不适用"],
        [GSQuestionOption optionWithKey:@"C" content:@"运算过程中不需要考虑定义域"],
        [GSQuestionOption optionWithKey:@"D" content:@"以上说法均不正确"]
    ];
    sim.answer = @"A";
    sim.analysis = [NSString stringWithFormat:@"本题考查 %@ 的基本性质，需牢记核心推导与适用范围。", res.knowledgePoint];
    sim.difficulty = @"基础";
    sim.source = @"本地精选变式库";
    res.similarQuestions = @[sim];

    return res;
}

#pragma mark - 本地规则秒级判断

+ (NSString *)detectSubjectLocally:(NSString *)text {
    if ([text containsString:@"函数"] || [text containsString:@"向量"] || [text containsString:@"\\triangle"] || [text containsString:@"求证"] || [text containsString:@"解方程"] || [text containsString:@"log"] || [text containsString:@"sin"]) return @"数学";
    if ([text containsString:@"加速度"] || [text containsString:@"牛顿"] || [text containsString:@"重力"] || [text containsString:@"电场"] || [text containsString:@"电阻"] || [text containsString:@"波长"]) return @"物理";
    if ([text containsString:@"溶液"] || [text containsString:@"沉淀"] || [text containsString:@"化合价"] || [text containsString:@"反应方程式"] || [text containsString:@"摩尔"] || [text containsString:@"离子"]) return @"化学";
    if ([text containsString:@"细胞"] || [text containsString:@"染色体"] || [text containsString:@"光合作用"] || [text containsString:@"基因"] || [text containsString:@"蛋白质"]) return @"生物";
    if ([text containsString:@"下列词语"] || [text containsString:@"文言文"] || [text containsString:@"诗歌"] || [text containsString:@"修辞"] || [text containsString:@"成语"]) return @"语文";
    if ([text rangeOfString:@"[A-Za-z]{3,}" options:NSRegularExpressionSearch].location != NSNotFound && [text containsString:@"the"]) return @"英语";
    return @"数学";
}

+ (NSString *)detectKnowledgePointLocally:(NSString *)text subject:(NSString *)subject {
    if ([text containsString:@"向量"]) return @"平面向量线性运算与数量积";
    if ([text containsString:@"三角"] || [text containsString:@"sin"] || [text containsString:@"cos"]) return @"三角函数与诱导公式";
    if ([text containsString:@"二次函数"] || [text containsString:@"抛物线"]) return @"二次函数极值与图像性质";
    if ([text containsString:@"导数"] || [text containsString:@"切线"]) return @"导数与单调性极值";
    if ([text containsString:@"牛顿"]) return @"牛顿第二定律综合应用";
    if ([text containsString:@"动能"] || [text containsString:@"机械能"]) return @"机械能守恒与动能定理";
    if ([text containsString:@"离子"]) return @"离子反应与共存判断";
    return [NSString stringWithFormat:@"%@综合重点考点", subject];
}

+ (NSString *)suggestMistakeCauseLocally:(NSString *)text {
    if ([text containsString:@"计算"] || [text containsString:@"值域"] || [text containsString:@"="]) return @"符号运算错误或分类讨论不全";
    if ([text containsString:@"几何"] || [text containsString:@"图形"]) return @"空间辅助线构造盲区";
    return @"核心概念混淆或审题遗漏隐含条件";
}

- (void)requestStepByStepSolutionForText:(NSString *)questionText
                                 subject:(NSString *)subject
                          knowledgePoint:(NSString *)knowledgePoint
                              completion:(void(^)(NSString *solution, NSString * _Nullable error))completion {
    if (questionText.length == 0) {
        if (completion) completion(@"暂无题目内容，无法生成解析。", nil);
        return;
    }

    [self executeStepByStepWithModel:kModel27B questionText:questionText subject:subject knowledgePoint:knowledgePoint completion:^(NSString *sol27b, NSString *err27b) {
        if (sol27b && sol27b.length > 0) {
            if (completion) completion(sol27b, nil);
            return;
        }

        // 降级尝试 8B 模型极速推导
        [self executeStepByStepWithModel:kModel8B questionText:questionText subject:subject knowledgePoint:knowledgePoint completion:^(NSString *sol8b, NSString *err8b) {
            if (sol8b && sol8b.length > 0) {
                if (completion) completion(sol8b, nil);
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = [NSString stringWithFormat:@"【名师解析】\n本题重点考查【%@ - %@】的核心应用。\n1. 审题时需仔细抓取已知量与隐藏条件；\n2. 建立对应的数学/科学模型，注意分步化简与公式代入时的符号正负；\n3. 运算结束后务必检验定义域与边界极值条件，避免以偏概全。", subject ?: @"数学", knowledgePoint ?: @"重点"];
                if (completion) completion(fallback, nil);
            });
        }];
    }];
}

- (void)executeStepByStepWithModel:(NSString *)model
                      questionText:(NSString *)questionText
                           subject:(NSString *)subject
                    knowledgePoint:(NSString *)knowledgePoint
                        completion:(void(^)(NSString *solution, NSString * _Nullable error))completion {
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = @"你是一名全国资深特级教研名师。请针对提供的错题，输出一份高质量的名师分步精讲与解题锦囊。\n"
        @"请严格遵循以下五维标准结构输出，语言精辟规范，逻辑层层递进：\n\n"
        @"## 【一、考点与题型定位】\n精准指出本题考查的核心考点、知识模块与考题难度层级。\n\n"
        @"## 【二、审题关键与突破口】\n一句话直击破局关键，明确指出题目中的隐含条件与审题陷阱。\n\n"
        @"## 【三、名师规范解答】\n按高考试卷标准评分细则分步书写推导，逻辑严密清晰。遇到数学物理公式必须严格使用标准LaTeX语法，行内用 $...$，独立成行用 $$...$$，严禁在公式内部夹杂中文汉字，核心最终答案必须使用 \\boxed{...} 醒目标注。\n\n"
        @"## 【四、易错盲区与防坑锦囊】\n总结学生常犯的2-3个失分陷阱（如忽略定义域、分类讨论遗漏、正负号代入失误等）。\n\n"
        @"## 【五、名师心法与解题模型】\n提炼通性通法、秒杀验算技巧或同类题型的通用解题模型。";

    NSString *userContent = [NSString stringWithFormat:@"学科：%@\n考点：%@\n题目内容：\n%@", subject ?: @"数学", knowledgePoint ?: @"重点", questionText];

    NSDictionary *body = @{
        @"model": model ?: kModel27B,
        @"stream": @NO,
        @"keep_alive": @"24h",
        @"options": [GSOllamaClient defaultOllamaOptionsWithTemperature:0.2f numPredict:2048],
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user", @"content": userContent }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error.localizedDescription ?: @"网络异常");
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *cleaned = [GSOllamaClient cleanContentFromMessage:root[@"message"]];
        if (cleaned.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cleaned, nil);
            });
        } else {
            completion(nil, @"大模型返回空解析");
        }
    }] resume];
}

- (void)requestKnowledgeClusteringForText:(NSString *)summaryText
                               completion:(void(^)(NSString *report, NSString * _Nullable error))completion {
    if (summaryText.length == 0) {
        if (completion) completion(@"暂无错题数据，无法生成考点聚类分析。", nil);
        return;
    }

    [self executeKnowledgeClusteringWithModel:kModel27B summaryText:summaryText completion:^(NSString *rep27b, NSString *err27b) {
        if (rep27b && rep27b.length > 0) {
            if (completion) completion(rep27b, nil);
            return;
        }

        [self executeKnowledgeClusteringWithModel:kModel8B summaryText:summaryText completion:^(NSString *rep8b, NSString *err8b) {
            if (rep8b && rep8b.length > 0) {
                if (completion) completion(rep8b, nil);
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = @"【AI 考点聚类诊断报告】\n1. 高频易错考点聚类：综合代数与几何模型、受力与运动学定律应用；\n2. 错因主要集中在：分类讨论不全面、隐含条件未挖掘、公式符号代入失误；\n3. 复习提分策略：建议针对错题集开展两轮间隔巩固，优先攻克核心大题解题模板。";
                if (completion) completion(fallback, nil);
            });
        }];
    }];
}

- (void)executeKnowledgeClusteringWithModel:(NSString *)model
                                summaryText:(NSString *)summaryText
                                 completion:(void(^)(NSString *report, NSString * _Nullable error))completion {
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = @"你是一名全国资深特级教研名师与学情大数据专家。请根据提供的学生错题考点与错因清单，输出一份权威专业的【AI 错题全景考点聚类与薄弱项突破诊断报告】。\n"
        @"包含以下四大模块：\n"
        @"## 【一、高频薄弱考点聚类图谱】\n按错误频次归类，分析代数、几何、实验等不同模块的失分权重。\n\n"
        @"## 【二、思维认知盲区与失分根因剖析】\n从概念理解、公式应用、逻辑推理、运算规范四个维度深度归因。\n\n"
        @"## 【三、能力维度评估与失分风险预警】\n评估各模块掌握度与后续综合题失分风险点。\n\n"
        @"## 【四、分阶段提分突破路径与复习日程表】\n给出未来7天急救巩固计划与30天专项进阶路线图，包含每日针对性复盘动作。\n\n"
        @"排版规整，条理清晰，具有权威指导价值。";

    NSDictionary *body = @{
        @"model": model ?: kModel27B,
        @"stream": @NO,
        @"keep_alive": @"24h",
        @"options": [GSOllamaClient defaultOllamaOptionsWithTemperature:0.25f numPredict:2048],
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user", @"content": summaryText }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error.localizedDescription ?: @"网络异常");
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *cleaned = [GSOllamaClient cleanContentFromMessage:root[@"message"]];
        if (cleaned.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cleaned, nil);
            });
        } else {
            completion(nil, @"大模型返回空报告");
        }
    }] resume];
}

- (void)requestCheckInContentForGrade:(NSString *)grade
                      knowledgePoints:(NSArray<NSString *> *)kps
                           completion:(void(^)(NSDictionary * _Nullable data, NSString * _Nullable error))completion {
    NSString *targetKp = nil;
    for (NSString *kp in kps) {
        if (kp.length > 0 && ![kp isEqualToString:@"未分类"] && ![kp isEqualToString:@"全部"]) {
            targetKp = kp;
            break;
        }
    }
    if (!targetKp) {
        if ([grade containsString:@"高一"]) targetKp = @"平面向量数量积与坐标运算";
        else if ([grade containsString:@"高二"]) targetKp = @"导数的几何意义与单调极值";
        else if ([grade containsString:@"初中"]) targetKp = @"二次函数最值与图像综合性质";
        else targetKp = @"导数压轴分类讨论与零点存在性";
    }

    [self executeCheckInWithModel:kModel27B grade:grade targetKp:targetKp completion:^(NSDictionary *d27b, NSString *err27b) {
        if (d27b) {
            if (completion) completion(d27b, nil);
            return;
        }

        [self executeCheckInWithModel:kModel8B grade:grade targetKp:targetKp completion:^(NSDictionary *d8b, NSString *err8b) {
            if (d8b) {
                if (completion) completion(d8b, nil);
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([self defaultCheckInDataForGrade:grade kp:targetKp], nil);
            });
        }];
    }];
}

- (void)executeCheckInWithModel:(NSString *)model
                          grade:(NSString *)grade
                       targetKp:(NSString *)targetKp
                     completion:(void(^)(NSDictionary * _Nullable data, NSString * _Nullable error))completion {
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = [NSString stringWithFormat:
        @"你是一名全国资深重点高中特级教师与教研带头人。\n"
        @"请根据学生所在年级【%@】及其错题本中最薄弱的核心考点【%@】，编写一份定制的今日通关打卡内容。\n"
        @"严格输出合法的纯JSON对象（不要Markdown代码块，直接返回{...}）：\n"
        @"{\n"
        @"  \"knowledgePoint\": \"%@\",\n"
        @"  \"grade\": \"%@\",\n"
        @"  \"summary\": \"深入浅出提炼该考点的核心本质与考查关键（120-180字）\",\n"
        @"  \"keyFormulas\": \"必记核心定理、通解公式或思维定势（遇到公式必须用标准LaTeX语法如 $...$ 或 $$...$$）\",\n"
        @"  \"commonTraps\": \"学生最容易失分的3个典型盲区陷阱（分点 1. 2. 3. 列出，点明防坑策略）\",\n"
        @"  \"questions\": [\n"
        @"    {\n"
        @"      \"title\": \"通关实战 1 · 核心考点基础巩固\",\n"
        @"      \"stem\": \"典型高频单选客观题题干（含标准LaTeX公式）\",\n"
        @"      \"options\": [\"A. 选项A内容\", \"B. 选项B内容\", \"C. 选项C内容\", \"D. 选项D内容\"],\n"
        @"      \"answer\": \"A\",\n"
        @"      \"explanation\": \"名师分步剖析思路、解题关键转化与为什么选A\"\n"
        @"    },\n"
        @"    {\n"
        @"      \"title\": \"通关实战 2 · 思维进阶防坑变式\",\n"
        @"      \"stem\": \"思维进阶防坑单选题干（含标准LaTeX公式）\",\n"
        @"      \"options\": [\"A. 选项A内容\", \"B. 选项B内容\", \"C. 选项C内容\", \"D. 选项D内容\"],\n"
        @"      \"answer\": \"B\",\n"
        @"      \"explanation\": \"名师分步剖析思路、解题关键转化与为什么选B\"\n"
        @"    }\n"
        @"  ]\n"
        @"}", grade ?: @"高中", targetKp, targetKp, grade ?: @"高中"];

    NSDictionary *body = @{
        @"model": model ?: kModel27B,
        @"stream": @NO,
        @"format": @"json",
        @"keep_alive": @"24h",
        @"options": [GSOllamaClient defaultOllamaOptionsWithTemperature:0.2f numPredict:2048],
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user", @"content": [NSString stringWithFormat:@"请为【%@】年级的【%@】考点生成今日打卡学习内容与通关自测练习。", grade ?: @"高中", targetKp] }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error.localizedDescription ?: @"网络异常");
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *cleaned = [GSOllamaClient cleanContentFromMessage:root[@"message"]];
        if (cleaned.length > 0) {
            NSData *jsonData = [cleaned dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]] && dict[@"summary"] && dict[@"questions"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(dict, nil);
                });
                return;
            }
        }

        completion(nil, @"打卡内容生成失败");
    }] resume];
}

- (NSDictionary *)defaultCheckInDataForGrade:(NSString *)grade kp:(NSString *)targetKp {
    if ([grade containsString:@"高一"] || [targetKp containsString:@"向量"]) {
        return @{
            @"knowledgePoint": (targetKp.length > 0 ? targetKp : @"平面向量数量积与坐标运算"),
            @"grade": grade ?: @"高一",
            @"summary": @"平面向量数量积兼具大小与方向双重属性，既可通过几何定义 a·b = |a||b|cosθ 计算，也可借助直角坐标系代数化表示 a·b = x1x2 + y1y2 求解。",
            @"keyFormulas": @"1. 定义式：a · b = |a||b|cosθ\n2. 坐标式：a · b = x1x2 + y1y2\n3. 垂直充要：a ⊥ b ⇔ a · b = 0 ⇔ x1x2 + y1y2 = 0\n4. 模长：|a| = √(x1² + y1²)",
            @"commonTraps": @"1. 数量积不满足结合律：(a·b)c ≠ a(b·c)；\n2. 忽略夹角 θ ∈ [0, π]，当 a·b > 0 时 θ 为锐角或 0，需排除同向共线；\n3. 向量模平方展开易漏交叉项：|a + b|² = |a|² + 2a·b + |b|²。",
            @"questions": @[
                @{
                    @"title": @"通关实战 1 · 坐标与模长综合",
                    @"stem": @"已知平面向量 a = (1, 2)，b = (2, -1)，则向量 2a + b 与 a 的数量积 (2a + b) · a 为？",
                    @"options": @[@"A. 10", @"B. 12", @"C. 8", @"D. 15"],
                    @"answer": @"A",
                    @"explanation": @"先算 2a + b：2a = (2, 4)，2a + b = (4, 3)。再算数量积：(2a + b) · a = 4×1 + 3×2 = 10。选 A。"
                },
                @{
                    @"title": @"通关实战 2 · 垂直充要与参数求解",
                    @"stem": @"已知向量 a = (x, 1)，b = (2, -4)，若 a ⊥ b，则实数 x 的值为？",
                    @"options": @[@"A. 2", @"B. -2", @"C. 4", @"D. -4"],
                    @"answer": @"A",
                    @"explanation": @"两非零向量垂直的充要条件是 a · b = 0。即 2x - 4 = 0，解得 x = 2。选 A。"
                }
            ]
        };
    } else {
        return @{
            @"knowledgePoint": (targetKp.length > 0 ? targetKp : @"导数的几何意义与单调极值"),
            @"grade": grade ?: @"高二",
            @"summary": @"导数反映函数的瞬时变化率。切线斜率即导数值 k = f'(x0)；通过一阶导数符号判定原函数的单调性，极值点必为导数为 0 且两侧导数变号的点。",
            @"keyFormulas": @"1. 切线方程：y - f(x0) = f'(x0)(x - x0)\n2. 单调性判定：在区间上 f'(x) ≥ 0 恒成立则单调递增\n3. 极值判据：若 f'(x0) = 0 且左正右负为极大值点，左负右正为极小值点",
            @"commonTraps": @"1. 混淆“在某点处的切线”与“过某点的切线”；\n2. 导数等于0只是极值点的必要不充分条件；\n3. 求参数范围时，端点处导数是否可以等于0常遗漏验证。",
            @"questions": @[
                @{
                    @"title": @"通关实战 1 · 切线方程基本功",
                    @"stem": @"曲线 f(x) = x³ - 2x + 1 在点 (1, 0) 处的切线方程为？",
                    @"options": @[@"A. y = x - 1", @"B. y = 2x - 2", @"C. y = -x + 1", @"D. y = 3x - 3"],
                    @"answer": @"A",
                    @"explanation": @"求导 f'(x) = 3x² - 2。切点横坐标为 1，故斜率 k = f'(1) = 1。点斜式方程 y - 0 = 1 × (x - 1)，即 y = x - 1。选 A。"
                },
                @{
                    @"title": @"通关实战 2 · 极值点与单调性",
                    @"stem": @"函数 f(x) = x³ - 3x 的极大值点和极大值分别为？",
                    @"options": @[@"A. 极大值点 x = -1，极大值 2", @"B. 极大值点 x = 1，极大值 -2", @"C. 极大值点 x = 0，极大值 0", @"D. 极大值点 x = -1，极大值 -2"],
                    @"answer": @"A",
                    @"explanation": @"求导 f'(x) = 3x² - 3 = 3(x+1)(x-1)。令 f'(x) = 0 得 x = -1, 1。当 x < -1 时导数大于0，在 (-1, 1) 导数小于0，故 x = -1 为极大值点，极大值为 f(-1) = 2。选 A。"
                }
            ]
        };
    }
}

@end
