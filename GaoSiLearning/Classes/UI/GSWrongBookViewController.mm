#import "GSWrongBookViewController.h"
#import "GSQuestionSelectViewController.h"
#import "GSSimilarQuestionsViewController.h"
#import "GSOrganizeViewController.h"
#import "GSOllamaClient.h"
#import "GSAPIClient.h"
#import "GSCacheManager.h"
#import "GSCaptureSession.h"
#import "GSModels.h"

@interface GSWrongBookViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *subjectScrollView;
@property (nonatomic, strong) UIScrollView *filterScrollView;
@property (nonatomic, strong) UIView *statsHeaderView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *btnCapture;

@property (nonatomic, strong) NSArray<NSString *> *subjects;
@property (nonatomic, copy) NSString *selectedSubject;
@property (nonatomic, strong) NSMutableArray<UIButton *> *subjectButtons;

// 4 大筛选维度
@property (nonatomic, copy) NSString *filterTime;
@property (nonatomic, copy) NSString *filterSource;
@property (nonatomic, copy) NSString *filterGrade;
@property (nonatomic, copy) NSString *filterMastery;
@property (nonatomic, copy) NSString *filterCause;
@property (nonatomic, copy) NSString *filterType;

@property (nonatomic, strong) UIButton *btnFilterTime;
@property (nonatomic, strong) UIButton *btnFilterSource;
@property (nonatomic, strong) UIButton *btnFilterGrade;
@property (nonatomic, strong) UIButton *btnFilterMore;

@property (nonatomic, strong) NSArray<GSWrongQuestion *> *allQuestions;
@property (nonatomic, strong) NSArray<GSWrongQuestion *> *filteredQuestions;
@end

@implementation GSWrongBookViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"智能错题本";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    _subjects = @[@"全部", @"数学", @"物理", @"化学", @"语文", @"英语", @"生物", @"历史", @"地理", @"政治"];
    _selectedSubject = @"全部";
    _subjectButtons = [NSMutableArray array];

    _filterTime = @"全部";
    _filterSource = @"全部";
    _filterGrade = @"全部";
    _filterMastery = @"全部";
    _filterCause = @"全部";
    _filterType = @"全部";

    _allQuestions = @[];
    _filteredQuestions = @[];

    [self setupNavigationItems];
    [self setupUI];
    [self loadQuestions];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadQuestions];
}

- (void)setupNavigationItems {
    UIBarButtonItem *btnSync = [[UIBarButtonItem alloc] initWithTitle:@"同步" style:UIBarButtonItemStylePlain target:self action:@selector(handleManualSync)];
    UIBarButtonItem *btnOrganize = [[UIBarButtonItem alloc] initWithTitle:@"整理" style:UIBarButtonItemStylePlain target:self action:@selector(handleOpenOrganize)];
    self.navigationItem.rightBarButtonItems = @[btnOrganize, btnSync];

    UIBarButtonItem *btnLogout = [[UIBarButtonItem alloc] initWithTitle:@"退出" style:UIBarButtonItemStylePlain target:self action:@selector(handleLogout)];
    self.navigationItem.leftBarButtonItem = btnLogout;
}

- (void)handleOpenOrganize {
    GSOrganizeViewController *orgVC = [[GSOrganizeViewController alloc] init];
    [self.navigationController pushViewController:orgVC animated:YES];
}

- (void)setupUI {
    // 1. 搜索栏
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _searchBar.placeholder = @"搜索题干、核心知识点或错因...";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    [self.view addSubview:_searchBar];

    // 2. 顶部横向滚动学科胶囊栏
    _subjectScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _subjectScrollView.showsHorizontalScrollIndicator = NO;
    _subjectScrollView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_subjectScrollView];

    CGFloat x = 12.0;
    for (NSString *sub in _subjects) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:sub forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        btn.layer.cornerRadius = 15.0;
        btn.layer.masksToBounds = YES;
        btn.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
        [btn sizeToFit];
        btn.frame = CGRectMake(x, 8, btn.bounds.size.width + 10, 30);
        x += btn.frame.size.width + 8;

        [btn addTarget:self action:@selector(handleSubjectSelect:) forControlEvents:UIControlEventTouchUpInside];
        [_subjectScrollView addSubview:btn];
        [_subjectButtons addObject:btn];
    }
    _subjectScrollView.contentSize = CGSizeMake(x + 12, 46);
    [self updateSubjectButtonsStyle];

    // 3. 时间 / 来源 / 年级 / 更多 筛选栏
    _filterScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _filterScrollView.showsHorizontalScrollIndicator = NO;
    _filterScrollView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_filterScrollView];

    _btnFilterTime = [self createFilterChipWithTitle:@"时间 ▾" action:@selector(handleTimeFilterTap)];
    _btnFilterSource = [self createFilterChipWithTitle:@"来源 ▾" action:@selector(handleSourceFilterTap)];
    _btnFilterGrade = [self createFilterChipWithTitle:@"年级 ▾" action:@selector(handleGradeFilterTap)];
    _btnFilterMore = [self createFilterChipWithTitle:@"更多 ▾" action:@selector(handleMoreFilterTap)];

    [_filterScrollView addSubview:_btnFilterTime];
    [_filterScrollView addSubview:_btnFilterSource];
    [_filterScrollView addSubview:_btnFilterGrade];
    [_filterScrollView addSubview:_btnFilterMore];

    // 4. 统计状态栏
    _statsHeaderView = [[UIView alloc] initWithFrame:CGRectZero];
    _statsHeaderView.backgroundColor = [UIColor colorWithRed:0.93 green:0.95 blue:0.98 alpha:1.0];
    [self.view addSubview:_statsHeaderView];

    // 5. 错题列表 TableView
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    // 绑定长按手势弹出快捷管理菜单
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTableViewLongPress:)];
    lp.minimumPressDuration = 0.5;
    [_tableView addGestureRecognizer:lp];

    [self.view addSubview:_tableView];

    // 6. 底部全宽主操作按钮: 拍照 / 选取试卷录错题
    _btnCapture = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnCapture.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    [_btnCapture setTitle:@"📷 拍照 / 选取试卷录错题" forState:UIControlStateNormal];
    _btnCapture.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_btnCapture setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnCapture.layer.cornerRadius = 12;
    _btnCapture.layer.shadowColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:0.35].CGColor;
    _btnCapture.layer.shadowOffset = CGSizeMake(0, 4);
    _btnCapture.layer.shadowRadius = 8;
    _btnCapture.layer.shadowOpacity = 1.0;
    [_btnCapture addTarget:self action:@selector(handleCaptureTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_btnCapture];
}

- (UIButton *)createFilterChipWithTitle:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    b.layer.cornerRadius = 14.0;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.92 alpha:1.0].CGColor;
    b.backgroundColor = [UIColor whiteColor];
    [b setTitleColor:[UIColor colorWithRed:0.30 green:0.35 blue:0.40 alpha:1.0] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    _searchBar.frame = CGRectMake(0, top, w, 44);
    _subjectScrollView.frame = CGRectMake(0, top + 44, w, 44);

    _filterScrollView.frame = CGRectMake(0, top + 88, w, 38);
    CGFloat fx = 12.0;
    NSArray *chips = @[_btnFilterTime, _btnFilterSource, _btnFilterGrade, _btnFilterMore];
    for (UIButton *b in chips) {
        [b sizeToFit];
        b.frame = CGRectMake(fx, 4, b.bounds.size.width + 10, 28);
        fx += b.bounds.size.width + 18;
    }
    _filterScrollView.contentSize = CGSizeMake(fx + 12, 38);

    _statsHeaderView.frame = CGRectMake(0, top + 126, w, 34);

    CGFloat btnH = 50.0;
    CGFloat btnY = h - bottom - btnH - 10;
    _btnCapture.frame = CGRectMake(16, btnY, w - 32, btnH);

    _tableView.frame = CGRectMake(0, top + 160, w, btnY - (top + 160) - 6);
}

- (void)updateSubjectButtonsStyle {
    for (UIButton *btn in _subjectButtons) {
        NSString *title = [btn titleForState:UIControlStateNormal];
        if ([title isEqualToString:_selectedSubject]) {
            btn.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1.0];
            [btn setTitleColor:[UIColor colorWithRed:0.35 green:0.40 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
        }
    }
}

- (void)handleSubjectSelect:(UIButton *)btn {
    _selectedSubject = [btn titleForState:UIControlStateNormal];
    [self updateSubjectButtonsStyle];
    [self applyFilter];
}

- (void)loadQuestions {
    GSUser *user = [GSCacheManager sharedManager].currentUser;
    NSString *stuId = user.studentId ?: @"1";

    // 先展示本地缓存
    self.allQuestions = [[GSCacheManager sharedManager] loadLocalWrongQuestions];
    [self applyFilter];

    [[GSAPIClient sharedClient] fetchWrongQuestionsForStudent:stuId subject:nil completion:^(NSArray<GSWrongQuestion *> * _Nullable questions, NSString * _Nullable error) {
        if (questions) {
            self.allQuestions = questions;
            [self applyFilter];
        }
    }];
}

// ── 4 大筛选弹窗交互 ─────────────────────────────────────────────────────────

- (void)handleTimeFilterTap {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"按时间筛选与排序" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@"全部时间", @"今天", @"近7天", @"近30天", @"近3个月", @"最早录入优先", @"最新录入优先"];
    for (NSString *opt in opts) {
        [sheet addAction:[UIAlertAction actionWithTitle:opt style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.filterTime = [opt isEqualToString:@"全部时间"] ? @"全部" : opt;
            [self updateFilterChipsUi];
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleSourceFilterTap {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"按录入来源筛选" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@"全部来源", @"平时作业", @"随堂练习", @"单元测验", @"月考周考", @"期中期末", @"模考真题", @"拍照录入"];
    for (NSString *opt in opts) {
        [sheet addAction:[UIAlertAction actionWithTitle:opt style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.filterSource = [opt isEqualToString:@"全部来源"] ? @"全部" : opt;
            [self updateFilterChipsUi];
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleGradeFilterTap {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"按学段年级筛选" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@"全部年级", @"高一", @"高二", @"高三", @"初中", @"小学"];
    for (NSString *opt in opts) {
        [sheet addAction:[UIAlertAction actionWithTitle:opt style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.filterGrade = [opt isEqualToString:@"全部年级"] ? @"全部" : opt;
            [self updateFilterChipsUi];
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleMoreFilterTap {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多综合筛选" message:@"选择掌握状态或重置所有条件" preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"仅看待复习错题" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.filterMastery = @"待复习";
        [self updateFilterChipsUi];
        [self applyFilter];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"仅看已掌握错题" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.filterMastery = @"已掌握";
        [self updateFilterChipsUi];
        [self applyFilter];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"仅看计算失误" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.filterCause = @"计算";
        [self updateFilterChipsUi];
        [self applyFilter];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"仅看概念模糊 / 思维盲区" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.filterCause = @"概念";
        [self updateFilterChipsUi];
        [self applyFilter];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"重置所有筛选" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        self.filterTime = @"全部";
        self.filterSource = @"全部";
        self.filterGrade = @"全部";
        self.filterMastery = @"全部";
        self.filterCause = @"全部";
        self.filterType = @"全部";
        [self updateFilterChipsUi];
        [self applyFilter];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)updateFilterChipsUi {
    BOOL timeActive = ![self.filterTime isEqualToString:@"全部"];
    [_btnFilterTime setTitle:timeActive ? [NSString stringWithFormat:@"%@ ▾", self.filterTime] : @"时间 ▾" forState:UIControlStateNormal];
    [self styleChip:_btnFilterTime active:timeActive];

    BOOL srcActive = ![self.filterSource isEqualToString:@"全部"];
    [_btnFilterSource setTitle:srcActive ? [NSString stringWithFormat:@"%@ ▾", self.filterSource] : @"来源 ▾" forState:UIControlStateNormal];
    [self styleChip:_btnFilterSource active:srcActive];

    BOOL gradeActive = ![self.filterGrade isEqualToString:@"全部"];
    [_btnFilterGrade setTitle:gradeActive ? [NSString stringWithFormat:@"%@ ▾", self.filterGrade] : @"年级 ▾" forState:UIControlStateNormal];
    [self styleChip:_btnFilterGrade active:gradeActive];

    BOOL moreActive = (![self.filterMastery isEqualToString:@"全部"] || ![self.filterCause isEqualToString:@"全部"]);
    [_btnFilterMore setTitle:moreActive ? @"更多(已筛) ▾" : @"更多 ▾" forState:UIControlStateNormal];
    [self styleChip:_btnFilterMore active:moreActive];

    [self.view setNeedsLayout];
}

- (void)styleChip:(UIButton *)chip active:(BOOL)active {
    if (active) {
        chip.backgroundColor = [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0];
        chip.layer.borderColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0].CGColor;
        [chip setTitleColor:[UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0] forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    } else {
        chip.backgroundColor = [UIColor whiteColor];
        chip.layer.borderColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.92 alpha:1.0].CGColor;
        [chip setTitleColor:[UIColor colorWithRed:0.30 green:0.35 blue:0.40 alpha:1.0] forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    }
}

- (void)applyFilter {
    NSString *keyword = [_searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<GSWrongQuestion *> *res = [NSMutableArray array];

    for (GSWrongQuestion *q in self.allQuestions) {
        // 1. 学科
        BOOL subjectMatch = [_selectedSubject isEqualToString:@"全部"] || [q.subject isEqualToString:_selectedSubject];

        // 2. 搜索关键字
        BOOL kwMatch = YES;
        if (keyword.length > 0) {
            kwMatch = ([q.questionText containsString:keyword] ||
                       [q.knowledgePoint containsString:keyword] ||
                       [q.mistakeCause containsString:keyword]);
        }

        // 3. 来源
        BOOL srcMatch = YES;
        if (![_filterSource isEqualToString:@"全部"]) {
            srcMatch = [q.mistakeCause containsString:_filterSource] || [q.knowledgePoint containsString:_filterSource];
        }

        // 4. 年级
        BOOL gradeMatch = YES;
        if (![_filterGrade isEqualToString:@"全部"]) {
            NSString *allStr = [NSString stringWithFormat:@"%@ %@", q.knowledgePoint ?: @"", q.questionText ?: @""];
            gradeMatch = [allStr containsString:_filterGrade] || ([_filterGrade isEqualToString:@"高三"] && [allStr containsString:@"高考"]);
        }

        // 5. 掌握状态
        BOOL masteryMatch = YES;
        if ([_filterMastery isEqualToString:@"已掌握"]) {
            masteryMatch = q.isMastered;
        } else if ([_filterMastery isEqualToString:@"待复习"]) {
            masteryMatch = !q.isMastered;
        }

        // 6. 错因
        BOOL causeMatch = YES;
        if (![_filterCause isEqualToString:@"全部"]) {
            causeMatch = [q.mistakeCause containsString:_filterCause];
        }

        if (subjectMatch && kwMatch && srcMatch && gradeMatch && masteryMatch && causeMatch) {
            [res addObject:q];
        }
    }

    // 时间排序
    if ([_filterTime isEqualToString:@"最早录入优先"]) {
        res = [[res sortedArrayUsingComparator:^NSComparisonResult(GSWrongQuestion *q1, GSWrongQuestion *q2) {
            return [q1.createdAt compare:q2.createdAt];
        }] mutableCopy];
    }

    self.filteredQuestions = [res copy];
    [self updateStats];
    [self.tableView reloadData];
}

- (void)updateStats {
    for (UIView *v in _statsHeaderView.subviews) [v removeFromSuperview];
    NSInteger total = self.allQuestions.count;
    NSInteger mastered = 0;
    for (GSWrongQuestion *q in self.allQuestions) {
        if (q.isMastered) mastered++;
    }
    NSInteger needReview = total - mastered;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, self.view.bounds.size.width - 32, 34)];
    lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    lbl.textColor = [UIColor colorWithRed:0.40 green:0.45 blue:0.52 alpha:1.0];
    lbl.text = [NSString stringWithFormat:@"总计收录 %ld 题 · 待复习 %ld · 艾宾浩斯已掌握 %ld", (long)total, (long)needReview, (long)mastered];
    [_statsHeaderView addSubview:lbl];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredQuestions.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 135.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GSWrongQuestionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 6, self.view.bounds.size.width - 32, 122)];
        card.tag = 999;
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 12.0;
        card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.04].CGColor;
        card.layer.shadowOffset = CGSizeMake(0, 3);
        card.layer.shadowRadius = 6.0;
        card.layer.shadowOpacity = 1.0;
        [cell.contentView addSubview:card];

        UILabel *tagSubject = [[UILabel alloc] initWithFrame:CGRectMake(12, 12, 42, 22)];
        tagSubject.tag = 1001;
        tagSubject.font = [UIFont boldSystemFontOfSize:11];
        tagSubject.textAlignment = NSTextAlignmentCenter;
        tagSubject.layer.cornerRadius = 4;
        tagSubject.layer.masksToBounds = YES;
        [card addSubview:tagSubject];

        UILabel *lblKp = [[UILabel alloc] initWithFrame:CGRectMake(62, 12, card.frame.size.width - 150, 22)];
        lblKp.tag = 1002;
        lblKp.font = [UIFont boldSystemFontOfSize:15];
        lblKp.textColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
        [card addSubview:lblKp];

        UILabel *tagStage = [[UILabel alloc] initWithFrame:CGRectMake(card.frame.size.width - 80, 12, 68, 22)];
        tagStage.tag = 1003;
        tagStage.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        tagStage.textAlignment = NSTextAlignmentCenter;
        tagStage.layer.cornerRadius = 11;
        tagStage.layer.masksToBounds = YES;
        [card addSubview:tagStage];

        UILabel *lblStem = [[UILabel alloc] initWithFrame:CGRectMake(12, 42, card.frame.size.width - 24, 42)];
        lblStem.tag = 1004;
        lblStem.font = [UIFont systemFontOfSize:13];
        lblStem.textColor = [UIColor colorWithRed:0.35 green:0.38 blue:0.42 alpha:1.0];
        lblStem.numberOfLines = 2;
        [card addSubview:lblStem];

        UILabel *lblCause = [[UILabel alloc] initWithFrame:CGRectMake(12, 90, card.frame.size.width - 24, 20)];
        lblCause.tag = 1005;
        lblCause.font = [UIFont systemFontOfSize:12];
        lblCause.textColor = [UIColor colorWithRed:0.90 green:0.35 blue:0.25 alpha:1.0];
        [card addSubview:lblCause];
    }

    UIView *card = [cell.contentView viewWithTag:999];
    UILabel *tagSubject = [card viewWithTag:1001];
    UILabel *lblKp = [card viewWithTag:1002];
    UILabel *tagStage = [card viewWithTag:1003];
    UILabel *lblStem = [card viewWithTag:1004];
    UILabel *lblCause = [card viewWithTag:1005];

    GSWrongQuestion *q = self.filteredQuestions[indexPath.row];
    tagSubject.text = q.subject ?: @"数学";
    if ([q.subject isEqualToString:@"数学"]) {
        tagSubject.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:0.15];
        tagSubject.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    } else if ([q.subject isEqualToString:@"物理"]) {
        tagSubject.backgroundColor = [UIColor colorWithRed:0.60 green:0.30 blue:0.90 alpha:0.15];
        tagSubject.textColor = [UIColor colorWithRed:0.60 green:0.30 blue:0.90 alpha:1.0];
    } else {
        tagSubject.backgroundColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.10 alpha:0.15];
        tagSubject.textColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.10 alpha:1.0];
    }

    lblKp.text = q.knowledgePoint.length > 0 ? q.knowledgePoint : @"核心重点考点";
    lblStem.text = q.questionText.length > 0 ? q.questionText : @"暂无提取文字";
    lblCause.text = [NSString stringWithFormat:@"错因：%@ · 遗忘周期：%@",
                     (q.mistakeCause.length > 0 ? q.mistakeCause : @"思维定式偏差"),
                     (q.nextReviewDate.length > 0 ? q.nextReviewDate : @"今日需复习")];

    if (q.isMastered) {
        tagStage.text = @"已掌握 ✓";
        tagStage.backgroundColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:0.15];
        tagStage.textColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
    } else {
        tagStage.text = [NSString stringWithFormat:@"阶段 %ld", (long)q.reviewStage];
        tagStage.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:0.12];
        tagStage.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    }

    return cell;
}

#pragma mark - 点击打开详情 & 长按操作菜单

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.filteredQuestions.count) return;
    GSWrongQuestion *q = self.filteredQuestions[indexPath.row];
    [self showDetailForQuestion:q];
}

- (void)handleTableViewLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [gesture locationInView:_tableView];
    NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:pt];
    if (!indexPath || indexPath.row >= self.filteredQuestions.count) return;

    GSWrongQuestion *q = self.filteredQuestions[indexPath.row];
    [self showActionMenuForQuestion:q];
}

- (void)showDetailForQuestion:(GSWrongQuestion *)q {
    NSString *statusStr = q.isMastered ? @"已掌握 ✓" : [NSString stringWithFormat:@"阶段 %ld (待复习)", (long)q.reviewStage];
    NSString *msg = [NSString stringWithFormat:@"【所属科目】%@\n【核心考点】%@\n【错因分析】%@\n【掌握状态】%@\n\n【题干内容】\n%@",
                     q.subject ?: @"全科",
                     q.knowledgePoint ?: @"核心考点",
                     q.mistakeCause ?: @"思维盲区",
                     statusStr,
                     q.questionText.length > 0 ? q.questionText : @"【暂无纯文本题干，可参考原始录入切图】"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ · 错题详情", q.subject ?: @"错题"]
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"💡 AI 名师解析" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showAnalysisForQuestion:q];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🎯 举一反三变式" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openSimilarQuestionsForQuestion:q];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showActionMenuForQuestion:(GSWrongQuestion *)q {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"【%@】错题管理", q.subject ?: @"错题"]
                                                                   message:[NSString stringWithFormat:@"考点：%@   错因：%@", q.knowledgePoint ?: @"未分类", q.mistakeCause ?: @"未归类"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"💡 AI 名师解析" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showAnalysisForQuestion:q];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🎯 同类变式题目" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openSimilarQuestionsForQuestion:q];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"✏️ 编辑错题信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showEditDialogForQuestion:q];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📂 移入其他科目" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showMoveSubjectDialogForQuestion:q];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🗑️ 删除此错题" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self showDeleteConfirmForQuestion:q];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 5 大功能实现

- (void)showDeleteConfirmForQuestion:(GSWrongQuestion *)q {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除错题确认"
                                                                   message:[NSString stringWithFormat:@"确定要从错题本中彻底删除这道错题吗？\n\n【科目】%@\n【考点】%@\n\n删除后相关的艾宾浩斯复习排程也将一并清除。", q.subject ?: @"全科", q.knowledgePoint ?: @""]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[GSCacheManager sharedManager] deleteWrongQuestionLocally:q.questionId];
        [[GSAPIClient sharedClient] deleteWrongQuestion:q.questionId completion:^(BOOL success, NSString * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [self showToast:@"错题已删除"];
                }
            });
        }];
        [self loadQuestions];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showEditDialogForQuestion:(GSWrongQuestion *)q {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✏️ 编辑错题信息"
                                                                   message:@"修改考点、错因及题干内容"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"核心考点";
        textField.text = q.knowledgePoint;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"错因分析";
        textField.text = q.mistakeCause;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"题干内容 (支持 LaTeX)";
        textField.text = q.questionText;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"保存修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newKp = alert.textFields[0].text;
        NSString *newCause = alert.textFields[1].text;
        NSString *newStem = alert.textFields[2].text;

        [[GSCacheManager sharedManager] updateWrongQuestionLocally:q.questionId subject:nil knowledgePoint:newKp mistakeCause:newCause questionText:newStem];
        [[GSAPIClient sharedClient] updateWrongQuestion:q.questionId subject:nil knowledgePoint:newKp mistakeCause:newCause questionTitle:newStem completion:^(BOOL success, NSString * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToast:success ? @"错题修改已保存" : @"修改已存至本地离线"];
            });
        }];
        [self loadQuestions];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAnalysisForQuestion:(GSWrongQuestion *)q {
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"💡 AI 名师解析"
                                                                     message:@"正在调用 Qwen 27B 大模型生成分步精解与易错避坑剖析...\n请稍候..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:^{
        NSString *queryText = q.questionText.length > 0 ? q.questionText : q.knowledgePoint;
        [[GSOllamaClient sharedClient] requestStepByStepSolutionForText:queryText subject:q.subject knowledgePoint:q.knowledgePoint completion:^(NSString *solution, NSString * _Nullable error) {
            [loading dismissViewControllerAnimated:YES completion:^{
                UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"💡 AI 名师解析 · Qwen 27B"
                                                                                     message:solution
                                                                              preferredStyle:UIAlertControllerStyleAlert];

                [resultAlert addAction:[UIAlertAction actionWithTitle:@"复制解析" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [UIPasteboard generalPasteboard].string = solution;
                    [self showToast:@"解析已复制到剪贴板"];
                }]];

                [resultAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:resultAlert animated:YES completion:nil];
            }];
        }];
    }];
}

- (void)openSimilarQuestionsForQuestion:(GSWrongQuestion *)q {
    GSSimilarQuestionsViewController *simVC = [[GSSimilarQuestionsViewController alloc] init];
    simVC.subject = q.subject ?: @"数学";
    simVC.knowledgePoint = q.knowledgePoint ?: @"重点知识";
    [self.navigationController pushViewController:simVC animated:YES];
}

- (void)showMoveSubjectDialogForQuestion:(GSWrongQuestion *)q {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"移入其他科目"
                                                                   message:@"请选择目标科目归类"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *allSubs = @[@"数学", @"物理", @"化学", @"语文", @"英语", @"生物", @"历史", @"地理", @"政治"];
    for (NSString *sub in allSubs) {
        [sheet addAction:[UIAlertAction actionWithTitle:sub style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[GSCacheManager sharedManager] updateWrongQuestionLocally:q.questionId subject:sub knowledgePoint:nil mistakeCause:nil questionText:nil];
            [[GSAPIClient sharedClient] updateWrongQuestion:q.questionId subject:sub knowledgePoint:nil mistakeCause:nil questionTitle:nil completion:^(BOOL success, NSString * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showToast:[NSString stringWithFormat:@"已成功移入「%@」", sub]];
                });
            }];
            [self loadQuestions];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 录题交互

- (void)handleCaptureTap {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"录入错题" message:@"拍摄试卷或从相册选择包含错题的图片" preferredStyle:UIAlertControllerStyleActionSheet];

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"拍照" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self openImagePickerWithSource:UIImagePickerControllerSourceTypeCamera];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"从相册选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openImagePickerWithSource:UIImagePickerControllerSourceTypePhotoLibrary];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openImagePickerWithSource:(UIImagePickerControllerSourceType)source {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = source;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (img) {
            [GSCaptureSession sharedSession].pageImage = img;
            GSQuestionSelectViewController *selectVC = [[GSQuestionSelectViewController alloc] init];
            [self.navigationController pushViewController:selectVC animated:YES];
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleManualSync {
    NSArray *pending = [[GSCacheManager sharedManager] loadPendingSyncQuestions];
    if (pending.count == 0) {
        [self showToast:@"已是最新，无待同步数据"];
        return;
    }
    NSString *stuId = [GSCacheManager sharedManager].currentUser.studentId ?: @"1";
    [[GSAPIClient sharedClient] batchSubmitWrongQuestions:pending studentId:stuId completion:^(BOOL success, NSInteger uploadedCount, NSString * _Nullable error) {
        if (success) {
            [[GSCacheManager sharedManager] clearPendingSyncQuestions];
            [self showToast:[NSString stringWithFormat:@"成功同步 %ld 道离线错题", (long)uploadedCount]];
            [self loadQuestions];
        } else {
            [self showToast:error ?: @"同步失败"];
        }
    }];
}

- (void)handleLogout {
    [[GSCacheManager sharedManager] logout];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showToast:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
