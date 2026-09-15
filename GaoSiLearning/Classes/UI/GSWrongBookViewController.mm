#import "GSWrongBookViewController.h"
#import "GSQuestionSelectViewController.h"
#import "GSAPIClient.h"
#import "GSCacheManager.h"
#import "GSCaptureSession.h"
#import "GSModels.h"

@interface GSWrongBookViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *subjectScrollView;
@property (nonatomic, strong) UIView *statsHeaderView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *btnCapture;

@property (nonatomic, strong) NSArray<NSString *> *subjects;
@property (nonatomic, copy) NSString *selectedSubject;
@property (nonatomic, strong) NSMutableArray<UIButton *> *subjectButtons;

@property (nonatomic, strong) NSArray<GSWrongQuestion *> *allQuestions;
@property (nonatomic, strong) NSArray<GSWrongQuestion *> *filteredQuestions;
@end

@implementation GSWrongBookViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"智能错题本";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    _subjects = @[@"全部", @"数学", @"物理", @"化学", @"语文", @"英语", @"生物", @"历史", @"地理"];
    _selectedSubject = @"全部";
    _subjectButtons = [NSMutableArray array];
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
    self.navigationItem.rightBarButtonItem = btnSync;

    UIBarButtonItem *btnLogout = [[UIBarButtonItem alloc] initWithTitle:@"退出" style:UIBarButtonItemStylePlain target:self action:@selector(handleLogout)];
    self.navigationItem.leftBarButtonItem = btnLogout;
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

    // 3. 统计状态栏
    _statsHeaderView = [[UIView alloc] initWithFrame:CGRectZero];
    _statsHeaderView.backgroundColor = [UIColor colorWithRed:0.93 green:0.95 blue:0.98 alpha:1.0];
    [self.view addSubview:_statsHeaderView];

    // 4. 错题列表 TableView
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:_tableView];

    // 5. 底部全宽主操作按钮: 拍照 / 选取试卷录错题 (完全对齐 Android 去掉选题打印、扩充全宽主按钮)
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    _searchBar.frame = CGRectMake(0, top, w, 44);
    _subjectScrollView.frame = CGRectMake(0, top + 44, w, 46);
    _statsHeaderView.frame = CGRectMake(0, top + 90, w, 36);

    CGFloat btnH = 50.0;
    CGFloat btnY = h - bottom - btnH - 10;
    _btnCapture.frame = CGRectMake(16, btnY, w - 32, btnH);

    _tableView.frame = CGRectMake(0, top + 126, w, btnY - (top + 126) - 6);
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

- (void)applyFilter {
    NSString *keyword = [_searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<GSWrongQuestion *> *res = [NSMutableArray array];

    for (GSWrongQuestion *q in self.allQuestions) {
        BOOL subjectMatch = [_selectedSubject isEqualToString:@"全部"] || [q.subject isEqualToString:_selectedSubject];
        BOOL kwMatch = YES;
        if (keyword.length > 0) {
            kwMatch = ([q.questionText containsString:keyword] ||
                       [q.knowledgePoint containsString:keyword] ||
                       [q.mistakeCause containsString:keyword]);
        }
        if (subjectMatch && kwMatch) {
            [res addObject:q];
        }
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

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, self.view.bounds.size.width - 32, 36)];
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
