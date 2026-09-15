#import "GSRecordDialogViewController.h"
#import "GSSimilarQuestionsViewController.h"
#import "GSVisionOCRService.h"
#import "GSOllamaClient.h"
#import "GSAPIClient.h"
#import "GSCacheManager.h"
#import "GSCaptureSession.h"
#import "ImageProcessor.hpp"

@interface GSRecordDialogViewController () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *lblAiBadge;
@property (nonatomic, strong) UIScrollView *subjectChipsScroll;
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UITextView *tvOcrText;
@property (nonatomic, strong) UITextField *tfKnowledgePoint;
@property (nonatomic, strong) UITextField *tfMistakeCause;
@property (nonatomic, strong) UIScrollView *causeChipsScroll;
@property (nonatomic, strong) UIButton *btnSimilar;
@property (nonatomic, strong) UIButton *btnSubmit;

@property (nonatomic, strong) NSArray<NSString *> *subjects;
@property (nonatomic, copy) NSString *selectedSubject;
@property (nonatomic, strong) NSMutableArray<UIButton *> *subjectBtns;

@property (nonatomic, strong) NSArray<NSString *> *causeOptions;
@property (nonatomic, strong) UIImage *croppedImage;
@end

@implementation GSRecordDialogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"录入错题信息";
    self.view.backgroundColor = [UIColor whiteColor];

    _subjects = @[@"数学", @"物理", @"化学", @"语文", @"英语", @"生物", @"历史", @"地理"];
    _selectedSubject = @"数学";
    _subjectBtns = [NSMutableArray array];
    _causeOptions = @[@"计算粗心", @"概念不清", @"审题疏漏", @"公式记错", @"辅助线构造盲区", @"分类讨论不全"];

    [self setupUI];
    [self startAiAnalysisPipeline];
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    // 1. AI 状态胶囊标签
    _lblAiBadge = [[UILabel alloc] init];
    _lblAiBadge.backgroundColor = [UIColor colorWithRed:0.92 green:0.96 blue:1.0 alpha:1.0];
    _lblAiBadge.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    _lblAiBadge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _lblAiBadge.textAlignment = NSTextAlignmentCenter;
    _lblAiBadge.layer.cornerRadius = 12;
    _lblAiBadge.layer.masksToBounds = YES;
    _lblAiBadge.text = @"⚡ 视觉公式 OCR 中...";
    [_scrollView addSubview:_lblAiBadge];

    // 2. 学科选择 Chips
    _subjectChipsScroll = [[UIScrollView alloc] init];
    _subjectChipsScroll.showsHorizontalScrollIndicator = NO;
    [_scrollView addSubview:_subjectChipsScroll];

    CGFloat sx = 0;
    for (NSString *sub in _subjects) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:sub forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        b.layer.cornerRadius = 14;
        b.layer.masksToBounds = YES;
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
        [b sizeToFit];
        b.frame = CGRectMake(sx, 4, b.bounds.size.width + 10, 28);
        sx += b.frame.size.width + 6;
        [b addTarget:self action:@selector(handleSelectSubject:) forControlEvents:UIControlEventTouchUpInside];
        [_subjectChipsScroll addSubview:b];
        [_subjectBtns addObject:b];
    }
    _subjectChipsScroll.contentSize = CGSizeMake(sx, 36);
    [self updateSubjectSelectionUI];

    // 3. 题目切图缩略图
    _thumbnailView = [[UIImageView alloc] init];
    _thumbnailView.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    _thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    _thumbnailView.clipsToBounds = YES;
    _thumbnailView.layer.cornerRadius = 8;
    _thumbnailView.layer.borderWidth = 1.0;
    _thumbnailView.layer.borderColor = [UIColor colorWithRed:0.90 green:0.92 blue:0.94 alpha:1.0].CGColor;
    [_scrollView addSubview:_thumbnailView];

    // 4. 题干输入框 (带 LaTeX 公式)
    UILabel *lblOcrTitle = [self createSectionLabel:@"题目内容 (含 LaTeX 公式)"];
    [_scrollView addSubview:lblOcrTitle];

    _tvOcrText = [[UITextView alloc] init];
    _tvOcrText.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
    _tvOcrText.textColor = [UIColor colorWithRed:0.15 green:0.18 blue:0.22 alpha:1.0];
    _tvOcrText.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:0.99 alpha:1.0];
    _tvOcrText.layer.cornerRadius = 8;
    _tvOcrText.layer.borderWidth = 1.0;
    _tvOcrText.layer.borderColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:1.0].CGColor;
    _tvOcrText.text = @"正在通过视觉大模型精准提取题干与数学公式...";
    [_scrollView addSubview:_tvOcrText];

    // 5. 核心知识点输入框
    UILabel *lblKpTitle = [self createSectionLabel:@"核心考查知识点 (AI 自动归纳)"];
    [_scrollView addSubview:lblKpTitle];

    _tfKnowledgePoint = [self createInputFieldWithPlaceholder:@"输入或由 AI 自动生成知识点"];
    [_scrollView addSubview:_tfKnowledgePoint];

    // 6. 错因分析
    UILabel *lblCauseTitle = [self createSectionLabel:@"错因分析 (深度思维盲区归因)"];
    [_scrollView addSubview:lblCauseTitle];

    _tfMistakeCause = [self createInputFieldWithPlaceholder:@"输入错因，或点击下方标签快速选择"];
    [_scrollView addSubview:_tfMistakeCause];

    _causeChipsScroll = [[UIScrollView alloc] init];
    _causeChipsScroll.showsHorizontalScrollIndicator = NO;
    [_scrollView addSubview:_causeChipsScroll];

    CGFloat cx = 0;
    for (NSString *cause in _causeOptions) {
        UIButton *cb = [UIButton buttonWithType:UIButtonTypeCustom];
        [cb setTitle:cause forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont systemFontOfSize:11];
        [cb setTitleColor:[UIColor colorWithRed:0.40 green:0.45 blue:0.52 alpha:1.0] forState:UIControlStateNormal];
        cb.backgroundColor = [UIColor colorWithRed:0.94 green:0.95 blue:0.97 alpha:1.0];
        cb.layer.cornerRadius = 12;
        cb.contentEdgeInsets = UIEdgeInsetsMake(4, 10, 4, 10);
        [cb sizeToFit];
        cb.frame = CGRectMake(cx, 2, cb.bounds.size.width + 8, 24);
        cx += cb.frame.size.width + 6;
        [cb addTarget:self action:@selector(handleCauseChipTap:) forControlEvents:UIControlEventTouchUpInside];
        [_causeChipsScroll addSubview:cb];
    }
    _causeChipsScroll.contentSize = CGSizeMake(cx, 28);

    // 7. 查看相似题按钮
    _btnSimilar = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnSimilar.backgroundColor = [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0];
    [_btnSimilar setTitle:@"🎯 举一反三 · 查看相似练习题" forState:UIControlStateNormal];
    _btnSimilar.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [_btnSimilar setTitleColor:[UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0] forState:UIControlStateNormal];
    _btnSimilar.layer.cornerRadius = 8;
    [_btnSimilar addTarget:self action:@selector(handleViewSimilar) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_btnSimilar];

    // 8. 提交录入按钮
    _btnSubmit = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnSubmit.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    [_btnSubmit setTitle:@"确认加入错题本" forState:UIControlStateNormal];
    _btnSubmit.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_btnSubmit setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnSubmit.layer.cornerRadius = 10;
    [_btnSubmit addTarget:self action:@selector(handleSubmit) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_btnSubmit];
}

- (UILabel *)createSectionLabel:(NSString *)text {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = text;
    lbl.font = [UIFont boldSystemFontOfSize:13];
    lbl.textColor = [UIColor colorWithRed:0.25 green:0.28 blue:0.32 alpha:1.0];
    return lbl;
}

- (UITextField *)createInputFieldWithPlaceholder:(NSString *)ph {
    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = ph;
    tf.font = [UIFont systemFontOfSize:14];
    tf.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:0.99 alpha:1.0];
    tf.layer.cornerRadius = 8;
    tf.layer.borderWidth = 1.0;
    tf.layer.borderColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:1.0].CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 20)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    return tf;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat p = 16.0;
    CGFloat cw = w - p * 2;

    _lblAiBadge.frame = CGRectMake(p, 16, 170, 28);
    _subjectChipsScroll.frame = CGRectMake(p, 52, cw, 36);

    _thumbnailView.frame = CGRectMake(p, 96, cw, 110);

    UIView *lblOcr = _scrollView.subviews[3];
    lblOcr.frame = CGRectMake(p, 214, cw, 20);
    _tvOcrText.frame = CGRectMake(p, 238, cw, 90);

    UIView *lblKp = _scrollView.subviews[5];
    lblKp.frame = CGRectMake(p, 336, cw, 20);
    _tfKnowledgePoint.frame = CGRectMake(p, 360, cw, 40);

    UIView *lblCause = _scrollView.subviews[7];
    lblCause.frame = CGRectMake(p, 408, cw, 20);
    _tfMistakeCause.frame = CGRectMake(p, 432, cw, 40);
    _causeChipsScroll.frame = CGRectMake(p, 478, cw, 28);

    _btnSimilar.frame = CGRectMake(p, 516, cw, 42);
    _btnSubmit.frame = CGRectMake(p, 568, cw, 48);

    _scrollView.contentSize = CGSizeMake(w, 640);
}

- (void)updateSubjectSelectionUI {
    for (UIButton *b in _subjectBtns) {
        NSString *t = [b titleForState:UIControlStateNormal];
        if ([t isEqualToString:_selectedSubject]) {
            b.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = [UIColor colorWithRed:0.93 green:0.94 blue:0.96 alpha:1.0];
            [b setTitleColor:[UIColor colorWithRed:0.35 green:0.40 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
        }
    }
}

- (void)handleSelectSubject:(UIButton *)btn {
    _selectedSubject = [btn titleForState:UIControlStateNormal];
    [self updateSubjectSelectionUI];
}

- (void)handleCauseChipTap:(UIButton *)btn {
    _tfMistakeCause.text = [btn titleForState:UIControlStateNormal];
}

#pragma mark - AI 流水线

- (void)startAiAnalysisPipeline {
    UIImage *fullImg = [GSCaptureSession sharedSession].pageImage;
    NSArray *selected = [GSCaptureSession sharedSession].selectedBoxes;
    if (!fullImg || selected.count == 0) return;

    CGRect firstNormRect = [selected.firstObject CGRectValue];
    _croppedImage = [GSImageProcessor cropImage:fullImg normalizedRect:firstNormRect];
    _thumbnailView.image = _croppedImage;

    _lblAiBadge.text = @"⚡ 视觉公式 OCR 中...";

    // 1. 端云视觉大模型公式识别
    [[GSVisionOCRService sharedService] recognizeQuestionTextFromImage:_croppedImage completion:^(NSString *ocrText, BOOL isFormulaSuccess) {
        if (ocrText.length > 0) {
            self.tvOcrText.text = ocrText;

            // 本地启发式秒出初判
            NSString *subj = [GSOllamaClient detectSubjectLocally:ocrText];
            self.selectedSubject = subj;
            [self updateSubjectSelectionUI];

            NSString *kp = [GSOllamaClient detectKnowledgePointLocally:ocrText subject:subj];
            self.tfKnowledgePoint.text = kp;

            NSString *cause = [GSOllamaClient suggestMistakeCauseLocally:ocrText];
            self.tfMistakeCause.text = cause;

            // 2. 异步发起 Qwen 27B 旗舰模型深度归因与变式生成
            self.lblAiBadge.text = @"✨ Qwen 27B 分析中...";
            [[GSOllamaClient sharedClient] requestAiAnalysisForText:ocrText completion:^(GSAiAnalysisResult * _Nullable result, NSString * _Nullable error) {
                if (result) {
                    self.lblAiBadge.text = @"✨ 27B 归因完成";
                    if (result.subject.length > 0) {
                        self.selectedSubject = result.subject;
                        [self updateSubjectSelectionUI];
                    }
                    if (result.knowledgePoint.length > 0) {
                        self.tfKnowledgePoint.text = result.knowledgePoint;
                    }
                    if (result.mistakeCause.length > 0) {
                        self.tfMistakeCause.text = result.mistakeCause;
                    }
                    if (result.similarQuestions.count > 0) {
                        [GSCaptureSession sharedSession].aiSimilarQuestions = [result.similarQuestions mutableCopy];
                    }
                } else {
                    self.lblAiBadge.text = @"智能识别就绪";
                }
            }];
        } else {
            self.tvOcrText.text = @"未识别出文字，请手动输入题干";
            self.lblAiBadge.text = @"待手动补充";
        }
    }];
}

- (void)handleViewSimilar {
    GSSimilarQuestionsViewController *similarVC = [[GSSimilarQuestionsViewController alloc] init];
    similarVC.subject = self.selectedSubject;
    similarVC.knowledgePoint = self.tfKnowledgePoint.text.length > 0 ? self.tfKnowledgePoint.text : @"重点基础考点";
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:similarVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)handleSubmit {
    NSString *stem = [_tvOcrText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *kp = [_tfKnowledgePoint.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *cause = [_tfMistakeCause.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if (stem.length == 0) {
        [self showAlert:@"题干内容不能为空"];
        return;
    }

    _btnSubmit.enabled = NO;
    _btnSubmit.alpha = 0.6;

    UIImage *fullImg = [GSCaptureSession sharedSession].pageImage;
    NSArray *selected = [GSCaptureSession sharedSession].selectedBoxes;
    NSString *studentId = [GSCacheManager sharedManager].currentUser.studentId ?: @"1";

    NSMutableArray<GSWrongQuestion *> *questions = [NSMutableArray array];
    for (NSValue *val in selected) {
        CGRect norm = [val CGRectValue];
        UIImage *crop = [GSImageProcessor cropImage:fullImg normalizedRect:norm];
        NSString *imgFile = [[GSCacheManager sharedManager] saveImageToDisk:crop];

        GSWrongQuestion *q = [[GSWrongQuestion alloc] init];
        q.questionId = [NSString stringWithFormat:@"wq_%lld_%d", (long long)[[NSDate date] timeIntervalSince1970], arc4random() % 1000];
        q.clientItemId = q.questionId;
        q.studentId = studentId;
        q.subject = self.selectedSubject;
        q.knowledgePoint = (kp.length > 0) ? kp : @"核心考点";
        q.mistakeCause = (cause.length > 0) ? cause : @"审题与概念疏漏";
        q.questionText = stem;
        q.sourceImageUri = imgFile;
        q.reviewStage = 1;
        q.isMastered = NO;
        q.createdAt = [self currentDateString];

        [questions addObject:q];
    }

    [[GSAPIClient sharedClient] batchSubmitWrongQuestions:questions studentId:studentId completion:^(BOOL success, NSInteger uploadedCount, NSString * _Nullable error) {
        self.btnSubmit.enabled = YES;
        self.btnSubmit.alpha = 1.0;

        if (success) {
            [[GSCaptureSession sharedSession] reset];
            [self dismissViewControllerAnimated:YES completion:^{
                // 返回根错题本列表
                UIWindow *win = [UIApplication sharedApplication].windows.firstObject;
                if ([win.rootViewController isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)win.rootViewController;
                    [nav popToRootViewControllerAnimated:YES];
                }
            }];
        } else {
            [self showAlert:error ?: @"提交失败，已保存至离线"];
        }
    }];
}

- (NSString *)currentDateString {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate date]];
}

- (void)showAlert:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
