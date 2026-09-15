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

@end
