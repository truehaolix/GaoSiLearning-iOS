#import "GSSimilarQuestionsViewController.h"
#import "GSLaTeXView.h"
#import "GSCaptureSession.h"
#import "GSOllamaClient.h"
#import "GSModels.h"

@interface GSSimilarQuestionsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) GSLaTeXView *stemLatexView;
@property (nonatomic, strong) UIView *optionsContainer;
@property (nonatomic, strong) UIButton *btnToggleAnalysis;
@property (nonatomic, strong) UIView *analysisCard;
@property (nonatomic, strong) UILabel *lblAnswer;
@property (nonatomic, strong) GSLaTeXView *analysisLatexView;
@property (nonatomic, strong) UIButton *btnRefreshAi;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) GSSimilarQuestion *currentQuestion;
@property (nonatomic, assign) BOOL isAnalysisVisible;
@end

@implementation GSSimilarQuestionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"举一反三 · 变式练习";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(handleDismiss)];

    [self setupUI];
    [self loadInitialQuestion];
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    // 1. 顶部考点信息卡片
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [UIColor whiteColor];
    _headerCard.layer.cornerRadius = 12;
    _headerCard.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.04].CGColor;
    _headerCard.layer.shadowOffset = CGSizeMake(0, 2);
    _headerCard.layer.shadowRadius = 4;
    _headerCard.layer.shadowOpacity = 1.0;
    [_scrollView addSubview:_headerCard];

    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.font = [UIFont boldSystemFontOfSize:15];
    lblTitle.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    lblTitle.text = [NSString stringWithFormat:@"🎯 对应考点：[%@] %@", self.subject ?: @"数学", self.knowledgePoint ?: @"核心重点"];
    lblTitle.tag = 101;
    [_headerCard addSubview:lblTitle];

    // 换一批按钮
    _btnRefreshAi = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnRefreshAi.backgroundColor = [UIColor colorWithRed:0.92 green:0.96 blue:1.0 alpha:1.0];
    [_btnRefreshAi setTitle:@"✨ AI 换一批" forState:UIControlStateNormal];
    _btnRefreshAi.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [_btnRefreshAi setTitleColor:[UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0] forState:UIControlStateNormal];
    _btnRefreshAi.layer.cornerRadius = 6;
    [_btnRefreshAi addTarget:self action:@selector(handleRefreshAi) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:_btnRefreshAi];

    // 2. 题干 LaTeX 卡片
    _stemLatexView = [[GSLaTeXView alloc] initWithFrame:CGRectZero];
    _stemLatexView.backgroundColor = [UIColor whiteColor];
    _stemLatexView.layer.cornerRadius = 12;
    _stemLatexView.layer.borderWidth = 1.0;
    _stemLatexView.layer.borderColor = [UIColor colorWithRed:0.90 green:0.92 blue:0.94 alpha:1.0].CGColor;
    [_scrollView addSubview:_stemLatexView];

    // 3. 选项容器
    _optionsContainer = [[UIView alloc] init];
    [_scrollView addSubview:_optionsContainer];

    // 4. 解析展开切换按钮
    _btnToggleAnalysis = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnToggleAnalysis.backgroundColor = [UIColor colorWithRed:0.94 green:0.95 blue:0.97 alpha:1.0];
    [_btnToggleAnalysis setTitle:@"💡 查看参考答案与名师解析 ▾" forState:UIControlStateNormal];
    _btnToggleAnalysis.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [_btnToggleAnalysis setTitleColor:[UIColor colorWithRed:0.25 green:0.28 blue:0.32 alpha:1.0] forState:UIControlStateNormal];
    _btnToggleAnalysis.layer.cornerRadius = 8;
    [_btnToggleAnalysis addTarget:self action:@selector(handleToggleAnalysis) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_btnToggleAnalysis];

    // 5. 解析卡片 (默认隐藏)
    _analysisCard = [[UIView alloc] init];
    _analysisCard.backgroundColor = [UIColor colorWithRed:0.98 green:0.99 blue:1.0 alpha:1.0];
    _analysisCard.layer.cornerRadius = 12;
    _analysisCard.layer.borderWidth = 1.0;
    _analysisCard.layer.borderColor = [UIColor colorWithRed:0.85 green:0.90 blue:0.98 alpha:1.0].CGColor;
    _analysisCard.hidden = YES;
    [_scrollView addSubview:_analysisCard];

    _lblAnswer = [[UILabel alloc] init];
    _lblAnswer.font = [UIFont boldSystemFontOfSize:15];
    _lblAnswer.textColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
    [_analysisCard addSubview:_lblAnswer];

    _analysisLatexView = [[GSLaTeXView alloc] initWithFrame:CGRectZero];
    [_analysisCard addSubview:_analysisLatexView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_scrollView addSubview:_spinner];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutAllCards];
}

- (void)layoutAllCards {
    CGFloat w = self.view.bounds.size.width;
    CGFloat p = 16.0;
    CGFloat cw = w - p * 2;

    _headerCard.frame = CGRectMake(p, 16, cw, 50);
    UIView *lblT = [_headerCard viewWithTag:101];
    lblT.frame = CGRectMake(12, 10, cw - 120, 30);
    _btnRefreshAi.frame = CGRectMake(cw - 100, 10, 90, 30);

    CGFloat curY = 76;
    _stemLatexView.frame = CGRectMake(p, curY, cw, 120);
    curY += 128;

    CGFloat optH = 0;
    for (UIView *v in _optionsContainer.subviews) {
        optH = MAX(optH, CGRectGetMaxY(v.frame));
    }
    _optionsContainer.frame = CGRectMake(p, curY, cw, optH);
    curY += optH + 16;

    _btnToggleAnalysis.frame = CGRectMake(p, curY, cw, 42);
    curY += 50;

    if (self.isAnalysisVisible) {
        _analysisCard.hidden = NO;
        _lblAnswer.frame = CGRectMake(14, 12, cw - 28, 24);
        _analysisLatexView.frame = CGRectMake(14, 40, cw - 28, 100);
        _analysisCard.frame = CGRectMake(p, curY, cw, 150);
        curY += 160;
    } else {
        _analysisCard.hidden = YES;
    }

    _spinner.center = CGPointMake(w / 2.0, 150);
    _scrollView.contentSize = CGSizeMake(w, curY + 40);
}

- (void)loadInitialQuestion {
    NSArray<GSSimilarQuestion *> *cached = [GSCaptureSession sharedSession].aiSimilarQuestions;
    if (cached.count > 0) {
        [self displayQuestion:cached.firstObject];
    } else {
        [self handleRefreshAi];
    }
}

- (void)displayQuestion:(GSSimilarQuestion *)q {
    _currentQuestion = q;
    [_stemLatexView renderLaTeXContent:q.stem];

    // 清空重构选项
    for (UIView *v in _optionsContainer.subviews) [v removeFromSuperview];
    CGFloat oy = 0;
    CGFloat cw = self.view.bounds.size.width - 32;

    for (GSQuestionOption *opt in q.options) {
        UIView *optCard = [[UIView alloc] initWithFrame:CGRectMake(0, oy, cw, 44)];
        optCard.backgroundColor = [UIColor whiteColor];
        optCard.layer.cornerRadius = 8;
        optCard.layer.borderWidth = 1.0;
        optCard.layer.borderColor = [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1.0].CGColor;

        UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 24, 24)];
        badge.text = opt.key;
        badge.font = [UIFont boldSystemFontOfSize:13];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.backgroundColor = [UIColor colorWithRed:0.92 green:0.95 blue:0.98 alpha:1.0];
        badge.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
        badge.layer.cornerRadius = 12;
        badge.layer.masksToBounds = YES;
        [optCard addSubview:badge];

        UILabel *txt = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, cw - 52, 32)];
        txt.text = opt.content;
        txt.font = [UIFont systemFontOfSize:14];
        txt.textColor = [UIColor colorWithRed:0.20 green:0.23 blue:0.27 alpha:1.0];
        [optCard addSubview:txt];

        [_optionsContainer addSubview:optCard];
        oy += 52;
    }

    _lblAnswer.text = [NSString stringWithFormat:@"参考答案：%@ (来源：%@ · 难度：%@)", q.answer, q.source ?: @"AI", q.difficulty ?: @"中等"];
    [_analysisLatexView renderLaTeXContent:q.analysis];

    [self layoutAllCards];
}

- (void)handleToggleAnalysis {
    self.isAnalysisVisible = !self.isAnalysisVisible;
    if (self.isAnalysisVisible) {
        [_btnToggleAnalysis setTitle:@"💡 收起参考答案与名师解析 ▴" forState:UIControlStateNormal];
    } else {
        [_btnToggleAnalysis setTitle:@"💡 查看参考答案与名师解析 ▾" forState:UIControlStateNormal];
    }
    [UIView animateWithDuration:0.25 animations:^{
        [self layoutAllCards];
    }];
}

- (void)handleRefreshAi {
    [_spinner startAnimating];
    _btnRefreshAi.enabled = NO;

    NSString *promptText = [NSString stringWithFormat:@"关于%@学科中%@考点的基础题与变式题", self.subject ?: @"数学", self.knowledgePoint ?: @"核心考点"];
    [[GSOllamaClient sharedClient] requestAiAnalysisForText:promptText completion:^(GSAiAnalysisResult * _Nullable result, NSString * _Nullable error) {
        [self.spinner stopAnimating];
        self.btnRefreshAi.enabled = YES;

        if (result.similarQuestions.count > 0) {
            [self displayQuestion:result.similarQuestions.firstObject];
        }
    }];
}

- (void)handleDismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
