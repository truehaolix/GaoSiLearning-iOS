#import "GSOllamaClient.h"
#import "GSCacheManager.h"

static NSString * const kModel27B = @"qwen3.8:27b-bf16";
static NSString * const kModel8B  = @"qwen3:8b";

@implementation GSOllamaClient {
    NSURLSession *_session;
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
        config.timeoutIntervalForRequest = 180.0;
        config.timeoutIntervalForResource = 180.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)requestAiAnalysisForText:(NSString *)ocrText
                      completion:(GSAiAnalysisCompletion)completion {
    if (ocrText.length == 0) {
        completion(nil, @"题干为空");
        return;
    }

    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *prompt = [NSString stringWithFormat:
        @"你是一名资深中小学名师与考情分析专家。请根据学生上传的题目文本，进行深入学科判断、核心知识点提炼、错因归纳与1道高匹配同考点变式练习题生成。\n"
        @"题目内容：\n\"\"\"\n%@\n\"\"\"\n\n"
        @"必须以纯 JSON 格式输出，不要包含任何前后缀、注释或代码块标记：\n"
        @"{\n"
        @"  \"subject\": \"数学/物理/化学/语文/英语/生物/历史/地理/政治\",\n"
        @"  \"knowledgePoint\": \"提取最核心的1-2个具体考点，如：平面向量数量积、二次函数极值\",\n"
        @"  \"mistakeCause\": \"深入推断学生最可能的思维误区或计算错因（20字以内）\",\n"
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
        @"      \"analysis\": \"名师精辟解析与解题思路\",\n"
        @"      \"difficulty\": \"中等\",\n"
        @"      \"source\": \"高斯知衡 AI 变式库\"\n"
        @"    }\n"
        @"  ]\n"
        @"}", ocrText];

    NSDictionary *payload = @{
        @"model": kModel27B,
        @"stream": @NO,
        @"messages": @[
            @{ @"role": @"system", @"content": @"你是一个严谨的教学AI，严格输出指定JSON结构。" },
            @{ @"role": @"user", @"content": prompt }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 自动容灾降级为本地规则生成
            dispatch_async(dispatch_get_main_queue(), ^{
                GSAiAnalysisResult *localRes = [self buildFallbackResultForText:ocrText];
                completion(localRes, nil);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        NSString *content = root[@"message"][@"content"];

        if (!content || content.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([self buildFallbackResultForText:ocrText], nil);
            });
            return;
        }

        // 清理可能包含的 markdown ```json 包裹
        NSString *cleaned = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([cleaned hasPrefix:@"```json"]) {
            cleaned = [cleaned substringFromIndex:7];
        } else if ([cleaned hasPrefix:@"```"]) {
            cleaned = [cleaned substringFromIndex:3];
        }
        if ([cleaned hasSuffix:@"```"]) {
            cleaned = [cleaned substringToIndex:cleaned.length - 3];
        }
        cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSData *cleanData = [cleaned dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *parsedJson = [NSJSONSerialization JSONObjectWithData:cleanData options:0 error:nil];

        if ([parsedJson isKindOfClass:[NSDictionary class]]) {
            GSAiAnalysisResult *result = [GSAiAnalysisResult fromDictionary:parsedJson];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([self buildFallbackResultForText:ocrText], nil);
            });
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
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = @"你是一名资深中小学及高考名师。请针对提供的错题，输出一份高质量的深度解析与名师解答。\n"
        @"内容包含：\n"
        @"【一、审题要点与考查方向】\n"
        @"【二、名师分步详解】（遇到数学公式、算式、符号，必须严格使用标准LaTeX语法，行内用 $...$，独立用 $$...$$）\n"
        @"【三、易错盲区与举一反三反思】\n"
        @"请直接输出规范生动、逻辑清晰的解析文本。";

    NSString *userContent = [NSString stringWithFormat:@"学科：%@\n考点：%@\n题目内容：\n%@", subject ?: @"数学", knowledgePoint ?: @"重点", questionText];

    NSDictionary *body = @{
        @"model": kModel27B,
        @"stream": @NO,
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
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = [NSString stringWithFormat:@"【名师解析】\n本题重点考查【%@ - %@】的核心应用。\n1. 审题时需仔细抓取已知量与隐藏条件；\n2. 建立对应的数学/科学模型，注意分步化简与公式代入时的符号正负；\n3. 运算结束后务必检验定义域与边界极值条件，避免以偏概全。", subject ?: @"数学", knowledgePoint ?: @"重点"];
                if (completion) completion(fallback, nil);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        NSString *content = root[@"message"][@"content"];
        if (content.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = [NSString stringWithFormat:@"【名师解析】\n本题重点考查【%@ - %@】的核心应用。\n1. 审题时需仔细抓取已知量与隐藏条件；\n2. 建立对应的数学/科学模型，注意分步化简；\n3. 仔细核对关键步骤。", subject ?: @"数学", knowledgePoint ?: @"重点"];
                if (completion) completion(fallback, nil);
            });
        }
    }] resume];
}

- (void)requestKnowledgeClusteringForText:(NSString *)summaryText
                               completion:(void(^)(NSString *report, NSString * _Nullable error))completion {
    if (summaryText.length == 0) {
        if (completion) completion(@"暂无错题数据，无法生成考点聚类分析。", nil);
        return;
    }
    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = @"你是一名全国资深特级教研名师与学情大数据专家。请根据提供的学生错题考点与错因清单，输出一份专业的【AI 错题全景考点聚类与薄弱项突破诊断报告】。\n"
        @"内容包含：\n"
        @"【一、高频薄弱考点聚类分析】（按错误频次聚类排序，指出核心痛点）\n"
        @"【二、典型思维盲区与失分归因剖析】\n"
        @"【三、针对性专项突破提分建议与复习时间表】\n"
        @"请输出排版规整、条理清晰的完整报告。";

    NSDictionary *body = @{
        @"model": kModel27B,
        @"stream": @NO,
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
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = @"【AI 考点聚类诊断报告】\n1. 高频易错考点聚类：综合代数与几何模型、受力与运动学定律应用；\n2. 错因主要集中在：分类讨论不全面、隐含条件未挖掘、公式符号代入失误；\n3. 复习提分策略：建议针对错题集开展两轮间隔巩固，优先攻克核心大题解题模板。";
                if (completion) completion(fallback, nil);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jsonErr];
        NSString *content = root[@"message"][@"content"];
        if (content.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *fallback = @"【AI 考点聚类诊断报告】\n1. 高频易错考点聚类：综合代数与几何模型、受力与运动学定律应用；\n2. 错因主要集中在：分类讨论不全面、隐含条件未挖掘、公式符号代入失误；\n3. 复习提分策略：建议针对错题集开展两轮间隔巩固，优先攻克核心大题解题模板。";
                if (completion) completion(fallback, nil);
            });
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

    NSString *host = [GSCacheManager sharedManager].ollamaHost;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/chat", host]];

    NSString *systemPrompt = [NSString stringWithFormat:
        @"你是一名全国资深特级教师与教研名师。请根据学生年级【%@】和错题考点【%@】，输出一份每日通关打卡内容。\n"
        @"必须返回合法的纯JSON对象（不要Markdown代码块，直接返回{...}）：\n"
        @"{\n"
        @"  \"knowledgePoint\": \"%@\",\n"
        @"  \"grade\": \"%@\",\n"
        @"  \"summary\": \"考点核心本质（100字左右）\",\n"
        @"  \"keyFormulas\": \"必备核心公式定理（包含数学符号）\",\n"
        @"  \"commonTraps\": \"典型失分避坑建议（分1. 2. 3.点）\",\n"
        @"  \"questions\": [\n"
        @"    {\n"
        @"      \"title\": \"通关实战 1\",\n"
        @"      \"stem\": \"典型单选题干\",\n"
        @"      \"options\": [\"A. ...\", \"B. ...\", \"C. ...\", \"D. ...\"],\n"
        @"      \"answer\": \"A\",\n"
        @"      \"explanation\": \"分步破题思路与解析\"\n"
        @"    },\n"
        @"    {\n"
        @"      \"title\": \"通关实战 2\",\n"
        @"      \"stem\": \"进阶单选题干\",\n"
        @"      \"options\": [\"A. ...\", \"B. ...\", \"C. ...\", \"D. ...\"],\n"
        @"      \"answer\": \"B\",\n"
        @"      \"explanation\": \"分步破题思路与解析\"\n"
        @"    }\n"
        @"  ]\n"
        @"}", grade ?: @"高中", targetKp, targetKp, grade ?: @"高中"];

    NSDictionary *body = @{
        @"model": kModel27B,
        @"stream": @NO,
        @"format": @"json",
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user", @"content": [NSString stringWithFormat:@"请生成【%@】年级的【%@】今日打卡与通关题目", grade ?: @"高中", targetKp] }
        ]
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([self defaultCheckInDataForGrade:grade kp:targetKp], nil);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *content = root[@"message"][@"content"];
        if (content.length > 0) {
            NSString *jsonStr = content;
            if ([jsonStr hasPrefix:@"```"]) {
                NSRange r1 = [jsonStr rangeOfString:@"\n"];
                NSRange r2 = [jsonStr rangeOfString:@"```" options:NSBackwardsSearch];
                if (r1.location != NSNotFound && r2.location != NSNotFound && r2.location > r1.location) {
                    jsonStr = [jsonStr substringWithRange:NSMakeRange(r1.location + 1, r2.location - r1.location - 1)];
                }
            }
            NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]] && dict[@"summary"] && dict[@"questions"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(dict, nil);
                });
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self defaultCheckInDataForGrade:grade kp:targetKp], nil);
        });
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
