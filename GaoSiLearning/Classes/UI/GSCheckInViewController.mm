#import "GSCheckInViewController.h"
#import "GSOllamaClient.h"
#import "GSCacheManager.h"

static NSString *const kPrefCheckInStreak = @"GS_CHECKIN_STREAK_DAYS";
static NSString *const kPrefCheckInLastDate = @"GS_CHECKIN_LAST_DATE";
static NSString *const kPrefCheckInHistory = @"GS_CHECKIN_HISTORY_DATES";

@interface GSCheckInViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UILabel *lblStreak;
@property (nonatomic, strong) UILabel *lblTodayBadge;
@property (nonatomic, strong) UIStackView *weekDotsStack;

@property (nonatomic, strong) UISegmentedControl *gradeSegment;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *lblLoadingTip;

@property (nonatomic, strong) UIView *conceptCard;
@property (nonatomic, strong) UILabel *lblKpTag;
@property (nonatomic, strong) UILabel *lblSummary;
@property (nonatomic, strong) UILabel *lblFormulas;
@property (nonatomic, strong) UILabel *lblTraps;

@property (nonatomic, strong) UIStackView *questionsStack;
@property (nonatomic, strong) UIButton *btnComplete;

@property (nonatomic, strong) NSDictionary *checkInData;
@property (nonatomic, copy) NSString *selectedGrade;

@end

@implementation GSCheckInViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"每日考点打卡";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    _selectedGrade = (_currentGrade.length > 0 && ![_currentGrade isEqualToString:@"全部"]) ? _currentGrade : @"高一";
    if (!_knowledgePoints) {
        _knowledgePoints = @[];
    }

    [self setupNavigation];
    [self setupUI];
    [self updateStreakUI];
    [self loadContent];
}

- (void)setupNavigation {
    UIBarButtonItem *btnRefresh = [[UIBarButtonItem alloc] initWithTitle:@"换考点"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(handleRefresh)];
    self.navigationItem.rightBarButtonItem = btnRefresh;
}

- (void)setupUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, screenW, self.view.bounds.size.height - 80)];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    // 1. 打卡顶部 Banner
    _headerCard = [[UIView alloc] initWithFrame:CGRectMake(16, 16, screenW - 32, 130)];
    _headerCard.backgroundColor = [UIColor colorWithRed:0.18 green:0.40 blue:0.86 alpha:1.0];
    _headerCard.layer.cornerRadius = 14.0;
    _headerCard.layer.masksToBounds = YES;
    [_scrollView addSubview:_headerCard];

    _lblStreak = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, screenW - 32 - 120, 26)];
    _lblStreak.textColor = [UIColor whiteColor];
    _lblStreak.font = [UIFont boldSystemFontOfSize:19];
    _lblStreak.text = @"🔥 连续打卡 0 天";
    [_headerCard addSubview:_lblStreak];

    _lblTodayBadge = [[UILabel alloc] initWithFrame:CGRectMake(_headerCard.bounds.size.width - 96, 16, 80, 24)];
    _lblTodayBadge.textColor = [UIColor whiteColor];
    _lblTodayBadge.font = [UIFont boldSystemFontOfSize:12];
    _lblTodayBadge.textAlignment = NSTextAlignmentCenter;
    _lblTodayBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    _lblTodayBadge.layer.cornerRadius = 12.0;
    _lblTodayBadge.layer.masksToBounds = YES;
    _lblTodayBadge.text = @"今日待完成";
    [_headerCard addSubview:_lblTodayBadge];

    UILabel *lblTip = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, _headerCard.bounds.size.width - 32, 20)];
    lblTip.textColor = [UIColor colorWithRed:0.88 green:0.91 blue:1.0 alpha:1.0];
    lblTip.font = [UIFont systemFontOfSize:12];
    lblTip.text = @"基于错题薄弱点与年级大纲，精准突破每一天";
    [_headerCard addSubview:lblTip];

    // 本周 7 天打卡圆点
    _weekDotsStack = [[UIStackView alloc] initWithFrame:CGRectMake(16, 72, _headerCard.bounds.size.width - 32, 34)];
    _weekDotsStack.axis = UILayoutConstraintAxisHorizontal;
    _weekDotsStack.distribution = UIStackViewDistributionEqualSpacing;
    _weekDotsStack.alignment = UIStackViewAlignmentCenter;
    [_headerCard addSubview:_weekDotsStack];

    NSArray<NSString *> *weekDays = @[@"一", @"二", @"三", @"四", @"五", @"六", @"日"];
    for (NSString *day in weekDays) {
        UILabel *dot = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        dot.text = day;
        dot.textColor = [UIColor colorWithRed:0.88 green:0.91 blue:1.0 alpha:1.0];
        dot.font = [UIFont systemFontOfSize:12];
        dot.textAlignment = NSTextAlignmentCenter;
        dot.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
        dot.layer.cornerRadius = 15.0;
        dot.layer.masksToBounds = YES;
        [dot.widthAnchor constraintEqualToConstant:30].active = YES;
        [dot.heightAnchor constraintEqualToConstant:30].active = YES;
        [_weekDotsStack addArrangedSubview:dot];
    }

    // 2. 年级切换控件
    NSArray *grades = @[@"高一", @"高二", @"高三", @"初中", @"小学"];
    _gradeSegment = [[UISegmentedControl alloc] initWithItems:grades];
    _gradeSegment.frame = CGRectMake(16, CGRectGetMaxY(_headerCard.frame) + 14, screenW - 32, 32);
    NSInteger idx = [grades indexOfObject:_selectedGrade];
    _gradeSegment.selectedSegmentIndex = (idx != NSNotFound) ? idx : 0;
    [_gradeSegment addTarget:self action:@selector(handleGradeChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_gradeSegment];

    // 3. Loading
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.center = CGPointMake(screenW / 2.0, CGRectGetMaxY(_gradeSegment.frame) + 40);
    _loadingIndicator.hidesWhenStopped = YES;
    [_scrollView addSubview:_loadingIndicator];

    _lblLoadingTip = [[UILabel alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(_loadingIndicator.frame) + 8, screenW - 32, 20)];
    _lblLoadingTip.textColor = [UIColor grayColor];
    _lblLoadingTip.font = [UIFont systemFontOfSize:13];
    _lblLoadingTip.textAlignment = NSTextAlignmentCenter;
    _lblLoadingTip.text = @"Qwen 大模型正在结合错题考点生成打卡内容...";
    _lblLoadingTip.hidden = YES;
    [_scrollView addSubview:_lblLoadingTip];

    // 4. 知识点精要卡片
    _conceptCard = [[UIView alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(_gradeSegment.frame) + 14, screenW - 32, 260)];
    _conceptCard.backgroundColor = [UIColor whiteColor];
    _conceptCard.layer.cornerRadius = 12.0;
    _conceptCard.layer.shadowColor = [UIColor blackColor].CGColor;
    _conceptCard.layer.shadowOpacity = 0.05;
    _conceptCard.layer.shadowOffset = CGSizeMake(0, 2);
    _conceptCard.layer.shadowRadius = 4.0;
    [_scrollView addSubview:_conceptCard];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 14, 180, 22)];
    titleLbl.font = [UIFont boldSystemFontOfSize:15];
    titleLbl.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    titleLbl.text = @"🎯 今日考点速记解析";
    [_conceptCard addSubview:titleLbl];

    _lblKpTag = [[UILabel alloc] initWithFrame:CGRectMake(_conceptCard.bounds.size.width - 150, 14, 136, 22)];
    _lblKpTag.font = [UIFont boldSystemFontOfSize:11];
    _lblKpTag.textColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:1.0];
    _lblKpTag.textAlignment = NSTextAlignmentRight;
    _lblKpTag.text = @"考点";
    [_conceptCard addSubview:_lblKpTag];

    _lblSummary = [[UILabel alloc] initWithFrame:CGRectMake(14, 42, _conceptCard.bounds.size.width - 28, 60)];
    _lblSummary.font = [UIFont systemFontOfSize:13];
    _lblSummary.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
    _lblSummary.numberOfLines = 0;
    [_conceptCard addSubview:_lblSummary];

    UILabel *formulaHead = [[UILabel alloc] initWithFrame:CGRectMake(14, 108, 200, 18)];
    formulaHead.font = [UIFont boldSystemFontOfSize:12];
    formulaHead.textColor = [UIColor colorWithRed:0.15 green:0.39 blue:0.92 alpha:1.0];
    formulaHead.text = @"📐 必备核心定理与公式";
    [_conceptCard addSubview:formulaHead];

    _lblFormulas = [[UILabel alloc] initWithFrame:CGRectMake(14, 128, _conceptCard.bounds.size.width - 28, 55)];
    _lblFormulas.font = [UIFont systemFontOfSize:12];
    _lblFormulas.textColor = [UIColor colorWithRed:0.15 green:0.2 blue:0.3 alpha:1.0];
    _lblFormulas.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:1.0 alpha:1.0];
    _lblFormulas.numberOfLines = 0;
    _lblFormulas.layer.cornerRadius = 6.0;
    _lblFormulas.layer.masksToBounds = YES;
    [_conceptCard addSubview:_lblFormulas];

    UILabel *trapsHead = [[UILabel alloc] initWithFrame:CGRectMake(14, 188, 200, 18)];
    trapsHead.font = [UIFont boldSystemFontOfSize:12];
    trapsHead.textColor = [UIColor colorWithRed:0.86 green:0.15 blue:0.15 alpha:1.0];
    trapsHead.text = @"⚠️ 易错盲区与避坑建议";
    [_conceptCard addSubview:trapsHead];

    _lblTraps = [[UILabel alloc] initWithFrame:CGRectMake(14, 208, _conceptCard.bounds.size.width - 28, 44)];
    _lblTraps.font = [UIFont systemFontOfSize:12];
    _lblTraps.textColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.1 alpha:1.0];
    _lblTraps.backgroundColor = [UIColor colorWithRed:1.0 green:0.96 blue:0.96 alpha:1.0];
    _lblTraps.numberOfLines = 0;
    _lblTraps.layer.cornerRadius = 6.0;
    _lblTraps.layer.masksToBounds = YES;
    [_conceptCard addSubview:_lblTraps];

    // 5. 题目列表容器
    _questionsStack = [[UIStackView alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(_conceptCard.frame) + 16, screenW - 32, 100)];
    _questionsStack.axis = UILayoutConstraintAxisVertical;
    _questionsStack.spacing = 16.0;
    [_scrollView addSubview:_questionsStack];

    // 6. 底部固定打卡按钮
    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 76, screenW, 76)];
    bottomBar.backgroundColor = [UIColor whiteColor];
    bottomBar.layer.shadowColor = [UIColor blackColor].CGColor;
    bottomBar.layer.shadowOpacity = 0.08;
    bottomBar.layer.shadowOffset = CGSizeMake(0, -2);
    bottomBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:bottomBar];

    _btnComplete = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnComplete.frame = CGRectMake(16, 12, screenW - 32, 48)];
    _btnComplete.backgroundColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:1.0];
    _btnComplete.layer.cornerRadius = 10.0;
    [_btnComplete setTitle:@"完成今日打卡 (+1 天)" forState:UIControlStateNormal];
    _btnComplete.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_btnComplete addTarget:self action:@selector(handleCompleteCheckIn) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:_btnComplete];
}

- (NSString *)getTodayDateString {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";
    return [df stringFromDate:[NSDate date]];
}

- (NSString *)getYesterdayDateString {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";
    NSDate *yesterday = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:[NSDate date] options:0];
    return [df stringFromDate:yesterday ?: [NSDate date]];
}

- (void)updateStreakUI {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger streak = [ud integerForKey:kPrefCheckInStreak];
    NSString *lastDate = [ud stringForKey:kPrefCheckInLastDate] ?: @"";
    NSString *todayStr = [self getTodayDateString];
    NSString *yesterdayStr = [self getYesterdayDateString];

    if (lastDate.length > 0 && ![lastDate isEqualToString:todayStr] && ![lastDate isEqualToString:yesterdayStr]) {
        streak = 0;
        [ud setInteger:0 forKey:kPrefCheckInStreak];
    }

    BOOL isDoneToday = [lastDate isEqualToString:todayStr];
    _lblStreak.text = [NSString stringWithFormat:@"🔥 连续打卡 %ld 天", (long)streak];

    if (isDoneToday) {
        _lblTodayBadge.text = @"今日已完成 ✓";
        _lblTodayBadge.backgroundColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
        [_btnComplete setTitle:@"今日打卡已达成 ✓" forState:UIControlStateNormal];
        _btnComplete.backgroundColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
        _btnComplete.enabled = NO;
    } else {
        _lblTodayBadge.text = @"今日待完成";
        _lblTodayBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
        [_btnComplete setTitle:@"完成今日打卡 (+1 天)" forState:UIControlStateNormal];
        _btnComplete.backgroundColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:1.0];
        _btnComplete.enabled = YES;
    }

    // 渲染本周圆点
    NSSet *history = [NSSet setWithArray:[ud arrayForKey:kPrefCheckInHistory] ?: @[]];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    calendar.firstWeekday = 2; // Monday
    NSDate *now = [NSDate date];
    NSDate *startOfWeek = nil;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&startOfWeek interval:NULL forDate:now];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";

    for (NSInteger i = 0; i < 7; i++) {
        if (i < _weekDotsStack.arrangedSubviews.count) {
            UILabel *dot = (UILabel *)_weekDotsStack.arrangedSubviews[i];
            NSDate *dayDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:i toDate:startOfWeek options:0];
            NSString *dayStr = [df stringFromDate:dayDate];
            if ([history containsObject:dayStr]) {
                dot.backgroundColor = [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:1.0];
                dot.textColor = [UIColor whiteColor];
            } else if ([dayStr isEqualToString:todayStr]) {
                dot.backgroundColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1.0];
                dot.textColor = [UIColor whiteColor];
            } else {
                dot.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
                dot.textColor = [UIColor colorWithRed:0.88 green:0.91 blue:1.0 alpha:1.0];
            }
        }
    }
}

- (void)handleGradeChanged:(UISegmentedControl *)sender {
    NSArray *grades = @[@"高一", @"高二", @"高三", @"初中", @"小学"];
    if (sender.selectedSegmentIndex < grades.count) {
        _selectedGrade = grades[sender.selectedSegmentIndex];
        [self loadContent];
    }
}

- (void)handleRefresh {
    [self loadContent];
}

- (void)loadContent {
    [_loadingIndicator startAnimating];
    _lblLoadingTip.hidden = NO;
    _conceptCard.hidden = YES;
    for (UIView *v in _questionsStack.arrangedSubviews) {
        [_questionsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    [[GSOllamaClient sharedClient] requestCheckInContentForGrade:_selectedGrade
                                                 knowledgePoints:_knowledgePoints
                                                      completion:^(NSDictionary * _Nullable data, NSString * _Nullable error) {
        [self.loadingIndicator stopAnimating];
        self.lblLoadingTip.hidden = YES;
        self.conceptCard.hidden = NO;
        self.checkInData = data;
        [self renderContentWithData:data];
    }];
}

- (void)renderContentWithData:(NSDictionary *)data {
    _lblKpTag.text = data[@"knowledgePoint"] ?: @"重点考点";
    _lblSummary.text = data[@"summary"] ?: @"";
    _lblFormulas.text = [NSString stringWithFormat:@" %@", data[@"keyFormulas"] ?: @""];
    _lblTraps.text = [NSString stringWithFormat:@" %@", data[@"commonTraps"] ?: @""];

    for (UIView *v in _questionsStack.arrangedSubviews) {
        [_questionsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray *questions = data[@"questions"];
    if (![questions isKindOfClass:[NSArray class]]) return;

    CGFloat cardW = [UIScreen mainScreen].bounds.size.width - 32;

    for (NSInteger idx = 0; idx < questions.count; idx++) {
        NSDictionary *q = questions[idx];

        UIView *qCard = [[UIView alloc] init];
        qCard.backgroundColor = [UIColor whiteColor];
        qCard.layer.cornerRadius = 12.0;
        qCard.layer.shadowColor = [UIColor blackColor].CGColor;
        qCard.layer.shadowOpacity = 0.05;
        qCard.layer.shadowOffset = CGSizeMake(0, 2);
        qCard.layer.shadowRadius = 4.0;

        UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(14, 14, 80, 20)];
        badge.backgroundColor = [UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1.0];
        badge.textColor = [UIColor whiteColor];
        badge.font = [UIFont boldSystemFontOfSize:11];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.layer.cornerRadius = 4.0;
        badge.layer.masksToBounds = YES;
        badge.text = [NSString stringWithFormat:@"通关题 %ld", (long)(idx + 1)];
        [qCard addSubview:badge];

        UILabel *stemLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 40, cardW - 28, 50)];
        stemLbl.font = [UIFont systemFontOfSize:14];
        stemLbl.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
        stemLbl.numberOfLines = 0;
        stemLbl.text = q[@"stem"] ?: @"";
        [stemLbl sizeToFit];
        stemLbl.frame = CGRectMake(14, 40, cardW - 28, stemLbl.bounds.size.height);
        [qCard addSubview:stemLbl];

        CGFloat optY = CGRectGetMaxY(stemLbl.frame) + 12;
        NSArray *options = q[@"options"] ?: @[];
        NSString *answer = q[@"answer"] ?: @"A";
        NSString *explanation = q[@"explanation"] ?: @"";

        NSMutableArray<UIButton *> *optButtons = [NSMutableArray array];

        UILabel *feedbackLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, cardW - 28, 22)];
        feedbackLbl.font = [UIFont boldSystemFontOfSize:13];
        feedbackLbl.hidden = YES;
        [qCard addSubview:feedbackLbl];

        UIView *expBox = [[UIView alloc] initWithFrame:CGRectMake(14, 0, cardW - 28, 60)];
        expBox.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:0.99 alpha:1.0];
        expBox.layer.cornerRadius = 6.0;
        expBox.hidden = YES;
        [qCard addSubview:expBox];

        UILabel *expHead = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 200, 16)];
        expHead.font = [UIFont boldSystemFontOfSize:12];
        expHead.textColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:1.0];
        expHead.text = @"💡 名师破题解析：";
        [expBox addSubview:expHead];

        UILabel *expText = [[UILabel alloc] initWithFrame:CGRectMake(8, 24, cardW - 44, 40)];
        expText.font = [UIFont systemFontOfSize:12];
        expText.textColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        expText.numberOfLines = 0;
        expText.text = explanation;
        [expText sizeToFit];
        expText.frame = CGRectMake(8, 24, cardW - 44, expText.bounds.size.height);
        [expBox addSubview:expText];
        expBox.frame = CGRectMake(14, 0, cardW - 28, CGRectGetMaxY(expText.frame) + 8);

        for (NSInteger optIdx = 0; optIdx < options.count; optIdx++) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(14, optY, cardW - 28, 40);
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderWidth = 1.0;
            btn.layer.borderColor = [UIColor colorWithRed:0.89 green:0.91 blue:0.94 alpha:1.0].CGColor;
            btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            btn.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
            [btn setTitle:options[optIdx] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:13];

            NSString *optLetter = (optIdx == 0 ? @"A" : (optIdx == 1 ? @"B" : (optIdx == 2 ? @"C" : @"D")));

            __weak typeof(self) weakSelf = self;
            [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
                for (UIButton *b in optButtons) {
                    b.userInteractionEnabled = NO;
                }
                BOOL isCorrect = [optLetter isEqualToString:answer] || [answer hasPrefix:optLetter];
                if (isCorrect) {
                    btn.backgroundColor = [UIColor colorWithRed:0.94 green:0.99 blue:0.96 alpha:1.0];
                    btn.layer.borderColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1.0].CGColor;
                    [btn setTitleColor:[UIColor colorWithRed:0.08 green:0.50 blue:0.24 alpha:1.0] forState:UIControlStateNormal];
                    feedbackLbl.text = @"🎉 回答正确！精准击破考点！";
                    feedbackLbl.textColor = [UIColor colorWithRed:0.09 green:0.64 blue:0.29 alpha:1.0];
                } else {
                    btn.backgroundColor = [UIColor colorWithRed:0.99 green:0.95 blue:0.95 alpha:1.0];
                    btn.layer.borderColor = [UIColor colorWithRed:0.94 green:0.27 blue:0.27 alpha:1.0].CGColor;
                    [btn setTitleColor:[UIColor colorWithRed:0.73 green:0.11 blue:0.11 alpha:1.0] forState:UIControlStateNormal];
                    feedbackLbl.text = [NSString stringWithFormat:@"💡 选错了，正确答案是【%@】", answer];
                    feedbackLbl.textColor = [UIColor colorWithRed:0.86 green:0.15 blue:0.15 alpha:1.0];

                    // 高亮正确选项
                    for (UIButton *b in optButtons) {
                        if ([b.currentTitle hasPrefix:answer]) {
                            b.backgroundColor = [UIColor colorWithRed:0.94 green:0.99 blue:0.96 alpha:1.0];
                            b.layer.borderColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1.0].CGColor;
                            [b setTitleColor:[UIColor colorWithRed:0.08 green:0.50 blue:0.24 alpha:1.0] forState:UIControlStateNormal];
                        }
                    }
                }
                feedbackLbl.frame = CGRectMake(14, optY + 8, cardW - 28, 22);
                feedbackLbl.hidden = NO;

                expBox.frame = CGRectMake(14, CGRectGetMaxY(feedbackLbl.frame) + 6, cardW - 28, expBox.bounds.size.height);
                expBox.hidden = NO;

                qCard.frame = CGRectMake(0, 0, cardW, CGRectGetMaxY(expBox.frame) + 14);
                [weakSelf updateScrollContentSize];
            }] forControlEvents:UIControlEventTouchUpInside];

            [optButtons addObject:btn];
            [qCard addSubview:btn];
            optY += 48;
        }

        qCard.frame = CGRectMake(0, 0, cardW, optY + 8);
        [_questionsStack addArrangedSubview:qCard];
    }

    [self updateScrollContentSize];
}

- (void)updateScrollContentSize {
    [_scrollView layoutIfNeeded];
    CGFloat maxY = CGRectGetMaxY(_questionsStack.frame) + 32;
    _scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, maxY);
}

- (void)handleCompleteCheckIn {
    NSString *todayStr = [self getTodayDateString];
    NSString *yesterdayStr = [self getYesterdayDateString];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *lastDate = [ud stringForKey:kPrefCheckInLastDate] ?: @"";

    if ([lastDate isEqualToString:todayStr]) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"提示"
                                                                   message:@"今日已经完成打卡，持之以恒，明天继续加油！"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSInteger streak = [ud integerForKey:kPrefCheckInStreak];
    streak = [lastDate isEqualToString:yesterdayStr] ? streak + 1 : 1;

    NSMutableArray *history = [NSMutableArray arrayWithArray:[ud arrayForKey:kPrefCheckInHistory] ?: @[]];
    if (![history containsObject:todayStr]) {
        [history addObject:todayStr];
    }

    [ud setInteger:streak forKey:kPrefCheckInStreak];
    [ud setObject:todayStr forKey:kPrefCheckInLastDate];
    [ud setObject:history forKey:kPrefCheckInHistory];
    [ud synchronize];

    [self updateStreakUI];

    NSString *kp = _checkInData[@"knowledgePoint"] ?: @"重点考点";
    NSString *msg = [NSString stringWithFormat:@"太棒了！已连续打卡 %ld 天！\n\n今日针对【%@】考点的巩固自测已圆满完成，错题薄弱点进一步筑牢！", (long)streak, kp];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎉 打卡成功！"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"太棒了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
