#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSUser : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *studentId;
+ (instancetype)userFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface GSWrongQuestion : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *questionId;
@property (nonatomic, copy) NSString *studentId;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *knowledgePoint;
@property (nonatomic, copy) NSString *mistakeCause;
@property (nonatomic, copy) NSString *questionText;
@property (nonatomic, copy) NSString *sourceImageUri;
@property (nonatomic, copy) NSString *clientItemId;
@property (nonatomic, assign) NSInteger reviewStage;
@property (nonatomic, copy) NSString *nextReviewDate;
@property (nonatomic, assign) BOOL isMastered;
@property (nonatomic, assign) NSInteger reviewCount;
@property (nonatomic, copy) NSString *createdAt;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface GSQuestionOption : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *content;
+ (instancetype)optionWithKey:(NSString *)key content:(NSString *)content;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface GSSimilarQuestion : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *questionId;
@property (nonatomic, copy) NSString *stem;
@property (nonatomic, strong) NSArray<GSQuestionOption *> *options;
@property (nonatomic, copy) NSString *answer;
@property (nonatomic, copy) NSString *analysis;
@property (nonatomic, copy) NSString *difficulty;
@property (nonatomic, copy) NSString *source;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface GSAiAnalysisResult : NSObject
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *knowledgePoint;
@property (nonatomic, copy) NSString *mistakeCause;
@property (nonatomic, strong) NSArray<GSSimilarQuestion *> *similarQuestions;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END
