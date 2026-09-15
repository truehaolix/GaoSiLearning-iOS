#import "GSModels.h"

@implementation GSUser

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.userId forKey:@"userId"];
    [coder encodeObject:self.username forKey:@"username"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.role forKey:@"role"];
    [coder encodeObject:self.token forKey:@"token"];
    [coder encodeObject:self.studentId forKey:@"studentId"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.userId = [coder decodeObjectOfClass:[NSString class] forKey:@"userId"] ?: @"";
        self.username = [coder decodeObjectOfClass:[NSString class] forKey:@"username"] ?: @"";
        self.name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"] ?: @"";
        self.role = [coder decodeObjectOfClass:[NSString class] forKey:@"role"] ?: @"student";
        self.token = [coder decodeObjectOfClass:[NSString class] forKey:@"token"] ?: @"";
        self.studentId = [coder decodeObjectOfClass:[NSString class] forKey:@"studentId"] ?: @"";
    }
    return self;
}

+ (instancetype)userFromDictionary:(NSDictionary *)dict {
    GSUser *user = [[GSUser alloc] init];
    user.userId = [NSString stringWithFormat:@"%@", dict[@"id"] ?: dict[@"userId"] ?: @""];
    user.username = [NSString stringWithFormat:@"%@", dict[@"username"] ?: @""];
    user.name = [NSString stringWithFormat:@"%@", dict[@"name"] ?: user.username];
    user.role = [NSString stringWithFormat:@"%@", dict[@"role"] ?: @"student"];
    user.token = [NSString stringWithFormat:@"%@", dict[@"token"] ?: @""];
    user.studentId = [NSString stringWithFormat:@"%@", dict[@"studentId"] ?: user.userId];
    return user;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.userId ?: @"",
        @"username": self.username ?: @"",
        @"name": self.name ?: @"",
        @"role": self.role ?: @"student",
        @"token": self.token ?: @"",
        @"studentId": self.studentId ?: @""
    };
}

@end

@implementation GSWrongQuestion

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.questionId forKey:@"questionId"];
    [coder encodeObject:self.studentId forKey:@"studentId"];
    [coder encodeObject:self.subject forKey:@"subject"];
    [coder encodeObject:self.knowledgePoint forKey:@"knowledgePoint"];
    [coder encodeObject:self.mistakeCause forKey:@"mistakeCause"];
    [coder encodeObject:self.questionText forKey:@"questionText"];
    [coder encodeObject:self.sourceImageUri forKey:@"sourceImageUri"];
    [coder encodeObject:self.clientItemId forKey:@"clientItemId"];
    [coder encodeInteger:self.reviewStage forKey:@"reviewStage"];
    [coder encodeObject:self.nextReviewDate forKey:@"nextReviewDate"];
    [coder encodeBool:self.isMastered forKey:@"isMastered"];
    [coder encodeInteger:self.reviewCount forKey:@"reviewCount"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.questionId = [coder decodeObjectOfClass:[NSString class] forKey:@"questionId"] ?: @"";
        self.studentId = [coder decodeObjectOfClass:[NSString class] forKey:@"studentId"] ?: @"";
        self.subject = [coder decodeObjectOfClass:[NSString class] forKey:@"subject"] ?: @"数学";
        self.knowledgePoint = [coder decodeObjectOfClass:[NSString class] forKey:@"knowledgePoint"] ?: @"";
        self.mistakeCause = [coder decodeObjectOfClass:[NSString class] forKey:@"mistakeCause"] ?: @"";
        self.questionText = [coder decodeObjectOfClass:[NSString class] forKey:@"questionText"] ?: @"";
        self.sourceImageUri = [coder decodeObjectOfClass:[NSString class] forKey:@"sourceImageUri"] ?: @"";
        self.clientItemId = [coder decodeObjectOfClass:[NSString class] forKey:@"clientItemId"] ?: @"";
        self.reviewStage = [coder decodeIntegerForKey:@"reviewStage"];
        self.nextReviewDate = [coder decodeObjectOfClass:[NSString class] forKey:@"nextReviewDate"] ?: @"";
        self.isMastered = [coder decodeBoolForKey:@"isMastered"];
        self.reviewCount = [coder decodeIntegerForKey:@"reviewCount"];
        self.createdAt = [coder decodeObjectOfClass:[NSString class] forKey:@"createdAt"] ?: @"";
    }
    return self;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    GSWrongQuestion *q = [[GSWrongQuestion alloc] init];
    q.questionId = [NSString stringWithFormat:@"%@", dict[@"id"] ?: @""];
    q.studentId = [NSString stringWithFormat:@"%@", dict[@"studentId"] ?: @""];
    q.subject = [NSString stringWithFormat:@"%@", dict[@"subject"] ?: @"数学"];
    q.knowledgePoint = [NSString stringWithFormat:@"%@", dict[@"knowledgePoint"] ?: @""];
    q.mistakeCause = [NSString stringWithFormat:@"%@", dict[@"mistakeCause"] ?: @""];
    q.questionText = [NSString stringWithFormat:@"%@", dict[@"questionText"] ?: @""];
    q.sourceImageUri = [NSString stringWithFormat:@"%@", dict[@"sourceImageUri"] ?: @""];
    q.clientItemId = [NSString stringWithFormat:@"%@", dict[@"clientItemId"] ?: @""];
    q.reviewStage = [dict[@"reviewStage"] respondsToSelector:@selector(integerValue)] ? [dict[@"reviewStage"] integerValue] : 0;
    q.nextReviewDate = [NSString stringWithFormat:@"%@", dict[@"nextReviewDate"] ?: @""];
    q.isMastered = [dict[@"isMastered"] boolValue];
    q.reviewCount = [dict[@"reviewCount"] integerValue];
    q.createdAt = [NSString stringWithFormat:@"%@", dict[@"createdAt"] ?: @""];
    return q;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.questionId ?: @"",
        @"studentId": self.studentId ?: @"",
        @"subject": self.subject ?: @"数学",
        @"knowledgePoint": self.knowledgePoint ?: @"",
        @"mistakeCause": self.mistakeCause ?: @"",
        @"questionText": self.questionText ?: @"",
        @"sourceImageUri": self.sourceImageUri ?: @"",
        @"clientItemId": self.clientItemId ?: @"",
        @"reviewStage": @(self.reviewStage),
        @"nextReviewDate": self.nextReviewDate ?: @"",
        @"isMastered": @(self.isMastered),
        @"reviewCount": @(self.reviewCount),
        @"createdAt": self.createdAt ?: @""
    };
}

@end

@implementation GSQuestionOption

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.key forKey:@"key"];
    [coder encodeObject:self.content forKey:@"content"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.key = [coder decodeObjectOfClass:[NSString class] forKey:@"key"] ?: @"";
        self.content = [coder decodeObjectOfClass:[NSString class] forKey:@"content"] ?: @"";
    }
    return self;
}

+ (instancetype)optionWithKey:(NSString *)key content:(NSString *)content {
    GSQuestionOption *opt = [[GSQuestionOption alloc] init];
    opt.key = key ?: @"";
    opt.content = content ?: @"";
    return opt;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    GSQuestionOption *opt = [[GSQuestionOption alloc] init];
    opt.key = [NSString stringWithFormat:@"%@", dict[@"key"] ?: @""];
    opt.content = [NSString stringWithFormat:@"%@", dict[@"content"] ?: @""];
    return opt;
}

- (NSDictionary *)toDictionary {
    return @{
        @"key": self.key ?: @"",
        @"content": self.content ?: @""
    };
}

@end

@implementation GSSimilarQuestion

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.questionId forKey:@"questionId"];
    [coder encodeObject:self.stem forKey:@"stem"];
    [coder encodeObject:self.options forKey:@"options"];
    [coder encodeObject:self.answer forKey:@"answer"];
    [coder encodeObject:self.analysis forKey:@"analysis"];
    [coder encodeObject:self.difficulty forKey:@"difficulty"];
    [coder encodeObject:self.source forKey:@"source"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.questionId = [coder decodeObjectOfClass:[NSString class] forKey:@"questionId"] ?: @"";
        self.stem = [coder decodeObjectOfClass:[NSString class] forKey:@"stem"] ?: @"";
        NSSet *classes = [NSSet setWithObjects:[NSArray class], [GSQuestionOption class], nil];
        self.options = [coder decodeObjectOfClasses:classes forKey:@"options"] ?: @[];
        self.answer = [coder decodeObjectOfClass:[NSString class] forKey:@"answer"] ?: @"";
        self.analysis = [coder decodeObjectOfClass:[NSString class] forKey:@"analysis"] ?: @"";
        self.difficulty = [coder decodeObjectOfClass:[NSString class] forKey:@"difficulty"] ?: @"中等";
        self.source = [coder decodeObjectOfClass:[NSString class] forKey:@"source"] ?: @"AI";
    }
    return self;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    GSSimilarQuestion *q = [[GSSimilarQuestion alloc] init];
    q.questionId = [NSString stringWithFormat:@"%@", dict[@"id"] ?: @""];
    q.stem = [NSString stringWithFormat:@"%@", dict[@"stem"] ?: @""];
    q.answer = [NSString stringWithFormat:@"%@", dict[@"answer"] ?: @""];
    q.analysis = [NSString stringWithFormat:@"%@", dict[@"analysis"] ?: @""];
    q.difficulty = [NSString stringWithFormat:@"%@", dict[@"difficulty"] ?: @"中等"];
    q.source = [NSString stringWithFormat:@"%@", dict[@"source"] ?: @"AI"];

    NSMutableArray<GSQuestionOption *> *opts = [NSMutableArray array];
    NSArray *rawOpts = dict[@"options"];
    if ([rawOpts isKindOfClass:[NSArray class]]) {
        for (id item in rawOpts) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [opts addObject:[GSQuestionOption fromDictionary:item]];
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)item;
                NSString *key = @"";
                NSString *content = str;
                if (str.length >= 2 && [str characterAtIndex:1] == '.') {
                    key = [str substringToIndex:1];
                    content = [str substringFromIndex:2];
                }
                [opts addObject:[GSQuestionOption optionWithKey:key content:content]];
            }
        }
    }
    q.options = [opts copy];
    return q;
}

- (NSDictionary *)toDictionary {
    NSMutableArray *optsArr = [NSMutableArray array];
    for (GSQuestionOption *o in self.options) {
        [optsArr addObject:[o toDictionary]];
    }
    return @{
        @"id": self.questionId ?: @"",
        @"stem": self.stem ?: @"",
        @"options": [optsArr copy],
        @"answer": self.answer ?: @"",
        @"analysis": self.analysis ?: @"",
        @"difficulty": self.difficulty ?: @"中等",
        @"source": self.source ?: @"AI"
    };
}

@end

@implementation GSAiAnalysisResult

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    GSAiAnalysisResult *res = [[GSAiAnalysisResult alloc] init];
    res.subject = [NSString stringWithFormat:@"%@", dict[@"subject"] ?: @""];
    res.knowledgePoint = [NSString stringWithFormat:@"%@", dict[@"knowledgePoint"] ?: @""];
    res.mistakeCause = [NSString stringWithFormat:@"%@", dict[@"mistakeCause"] ?: @""];

    NSMutableArray<GSSimilarQuestion *> *similar = [NSMutableArray array];
    NSArray *rawSimilar = dict[@"similarQuestions"];
    if ([rawSimilar isKindOfClass:[NSArray class]]) {
        for (id item in rawSimilar) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [similar addObject:[GSSimilarQuestion fromDictionary:item]];
            }
        }
    }
    res.similarQuestions = [similar copy];
    return res;
}

@end
