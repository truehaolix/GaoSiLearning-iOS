#import "GSOrganizeViewController.h"
#import "GSModels.h"
#import "GSCacheManager.h"
#import "GSAPIClient.h"
#import "GSOllamaClient.h"

@interface GSOrganizeViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *lblStats;
@property (nonatomic, strong) UIButton *btnSelectAll;
@property (nonatomic, strong) UILabel *lblSelectedCount;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *bottomBar;

@property (nonatomic, strong) NSArray<GSWrongQuestion *> *allQuestions;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;
@end

@implementation GSOrganizeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"错题智能整理中心";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    _selectedIds = [NSMutableSet set];
    _allQuestions = @[];

    [self setupNavigationItems];
    [self setupUI];
    [self loadData];
}

- (void)setupNavigationItems {
    UIBarButtonItem *btnAi = [[UIBarButtonItem alloc] initWithTitle:@"AI 考点聚类"
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(handleAiClustering)];
    self.navigationItem.rightBarButtonItem = btnAi;
}

- (void)setupUI {
    CGFloat w = self.view.bounds.size.width;

    // 1. 顶部统计与全选栏
    _headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 80)];
    _headerView.backgroundColor = [UIColor whiteColor];

    _lblStats = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, w - 32, 22)];
    _lblStats.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _lblStats.textColor = [UIColor colorWithRed:0.35 green:0.40 blue:0.45 alpha:1.0];
    [_headerView addSubview:_lblStats];

    _btnSelectAll = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnSelectAll.frame = CGRectMake(16, 42, 60, 28);
    [_btnSelectAll setTitle:@"全选" forState:UIControlStateNormal];
    _btnSelectAll.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_btnSelectAll setTitleColor:[UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0] forState:UIControlStateNormal];
    [_btnSelectAll addTarget:self action:@selector(handleToggleSelectAll) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_btnSelectAll];

    _lblSelectedCount = [[UILabel alloc] initWithFrame:CGRectMake(80, 42, w - 96, 28)];
    _lblSelectedCount.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _lblSelectedCount.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    _lblSelectedCount.text = @"已选 0 道题";
    [_headerView addSubview:_lblSelectedCount];

    [self.view addSubview:_headerView];

    // 2. 错题多选 TableView
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:_tableView];

    // 3. 底部批量操作栏
    _bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomBar.backgroundColor = [UIColor whiteColor];
    _bottomBar.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    _bottomBar.layer.shadowOffset = CGSizeMake(0, -3);
    _bottomBar.layer.shadowRadius = 6;
    _bottomBar.layer.shadowOpacity = 1.0;
    [self.view addSubview:_bottomBar];

    NSArray *btnTitles = @[@"📂 移科", @"✓ 标为已掌握", @"📄 组卷导出", @"🗑️ 删除"];
    NSArray *btnColors = @[
        [UIColor colorWithRed:0.20 green:0.25 blue:0.30 alpha:1.0],
        [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0],
        [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0],
        [UIColor colorWithRed:0.90 green:0.30 blue:0.25 alpha:1.0]
    ];

    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 200 + i;
        [b setTitle:btnTitles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        b.layer.cornerRadius = 8;
        b.layer.borderWidth = 1;
        b.layer.borderColor = [btnColors[i] colorWithAlphaComponent:0.4].CGColor;
        [b setTitleColor:btnColors[i] forState:UIControlStateNormal];

        if (i == 2) {
            // 组卷导出主按钮高亮实心
            b.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = [UIColor whiteColor];
        }

        [b addTarget:self action:@selector(handleBottomAction:) forControlEvents:UIControlEventTouchUpInside];
        [_bottomBar addSubview:b];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    _headerView.frame = CGRectMake(0, top, w, 76);

    CGFloat barH = 56.0;
    CGFloat barY = h - bottom - barH;
    _bottomBar.frame = CGRectMake(0, barY, w, barH + bottom);

    CGFloat pad = 8.0;
    CGFloat bw = (w - pad * 5) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = [_bottomBar viewWithTag:200 + i];
        b.frame = CGRectMake(pad + i * (bw + pad), 8, bw, 40);
    }

    _tableView.frame = CGRectMake(0, top + 76, w, barY - (top + 76));
}

- (void)loadData {
    self.allQuestions = [[GSCacheManager sharedManager] loadLocalWrongQuestions];
    [self updateDashboard];
    [self.tableView reloadData];
}

- (void)updateDashboard {
    NSInteger total = self.allQuestions.count;
    NSInteger mastered = 0;
    for (GSWrongQuestion *q in self.allQuestions) {
        if (q.isMastered) mastered++;
    }
    NSInteger needReview = total - mastered;

    _lblStats.text = [NSString stringWithFormat:@"收录总数 %ld 题 · 待巩固 %ld 题 · 已掌握 %ld 题", (long)total, (long)needReview, (long)mastered];
    _lblSelectedCount.text = [NSString stringWithFormat:@"已选 %lu 道题", (unsigned long)self.selectedIds.count];

    BOOL allSelected = (total > 0 && self.selectedIds.count == total);
    [_btnSelectAll setTitle:(allSelected ? @"全不选" : @"全选") forState:UIControlStateNormal];
}

- (void)handleToggleSelectAll {
    if (self.selectedIds.count == self.allQuestions.count) {
        [self.selectedIds removeAllObjects];
    } else {
        for (GSWrongQuestion *q in self.allQuestions) {
            if (q.questionId) [self.selectedIds addObject:q.questionId];
        }
    }
    [self updateDashboard];
    [self.tableView reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.allQuestions.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 105.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GSOrganizeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 6, self.view.bounds.size.width - 32, 93)];
        card.tag = 500;
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 10;
        [cell.contentView addSubview:card];

        UILabel *check = [[UILabel alloc] initWithFrame:CGRectMake(10, 34, 24, 24)];
        check.tag = 501;
        check.font = [UIFont boldSystemFontOfSize:18];
        check.textAlignment = NSTextAlignmentCenter;
        [card addSubview:check];

        UILabel *tagSubject = [[UILabel alloc] initWithFrame:CGRectMake(40, 10, 42, 20)];
        tagSubject.tag = 502;
        tagSubject.font = [UIFont boldSystemFontOfSize:11];
        tagSubject.textAlignment = NSTextAlignmentCenter;
        tagSubject.layer.cornerRadius = 4;
        tagSubject.layer.masksToBounds = YES;
        [card addSubview:tagSubject];

        UILabel *lblKp = [[UILabel alloc] initWithFrame:CGRectMake(90, 10, card.bounds.size.width - 170, 20)];
        lblKp.tag = 503;
        lblKp.font = [UIFont boldSystemFontOfSize:14];
        lblKp.textColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
        [card addSubview:lblKp];

        UILabel *lblMastery = [[UILabel alloc] initWithFrame:CGRectMake(card.bounds.size.width - 70, 10, 60, 20)];
        lblMastery.tag = 504;
        lblMastery.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        lblMastery.textAlignment = NSTextAlignmentRight;
        [card addSubview:lblMastery];

        UILabel *lblCause = [[UILabel alloc] initWithFrame:CGRectMake(40, 36, card.bounds.size.width - 50, 18)];
        lblCause.tag = 505;
        lblCause.font = [UIFont systemFontOfSize:12];
        lblCause.textColor = [UIColor colorWithRed:0.90 green:0.30 blue:0.25 alpha:1.0];
        [card addSubview:lblCause];

        UILabel *lblStem = [[UILabel alloc] initWithFrame:CGRectMake(40, 58, card.bounds.size.width - 50, 26)];
        lblStem.tag = 506;
        lblStem.font = [UIFont systemFontOfSize:12];
        lblStem.textColor = [UIColor colorWithRed:0.45 green:0.50 blue:0.55 alpha:1.0];
        lblStem.numberOfLines = 1;
        [card addSubview:lblStem];
    }

    UIView *card = [cell.contentView viewWithTag:500];
    UILabel *check = [card viewWithTag:501];
    UILabel *tagSub = [card viewWithTag:502];
    UILabel *lblKp = [card viewWithTag:503];
    UILabel *lblMastery = [card viewWithTag:504];
    UILabel *lblCause = [card viewWithTag:505];
    UILabel *lblStem = [card viewWithTag:506];

    GSWrongQuestion *q = self.allQuestions[indexPath.row];
    BOOL isSel = [self.selectedIds containsObject:q.questionId];

    check.text = isSel ? @"☑️" : @"⬜";
    tagSub.text = q.subject ?: @"数学";
    tagSub.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:0.12];
    tagSub.textColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];

    lblKp.text = q.knowledgePoint ?: @"核心考点";
    lblMastery.text = q.isMastered ? @"已掌握" : @"待复习";
    lblMastery.textColor = q.isMastered ? [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0] : [UIColor colorWithRed:0.90 green:0.35 blue:0.25 alpha:1.0];

    lblCause.text = [NSString stringWithFormat:@"错因：%@", q.mistakeCause ?: @"未归类"];
    lblStem.text = q.questionText.length > 0 ? q.questionText : @"【试卷原题切片】";

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    GSWrongQuestion *q = self.allQuestions[indexPath.row];
    if ([self.selectedIds containsObject:q.questionId]) {
        [self.selectedIds removeObject:q.questionId];
    } else {
        [self.selectedIds addObject:q.questionId];
    }
    [self updateDashboard];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - 底部批量操作分发

- (void)handleBottomAction:(UIButton *)btn {
    if (self.selectedIds.count == 0) {
        [self showToast:@"请先勾选需要整理的错题"];
        return;
    }

    switch (btn.tag) {
        case 200: [self handleBatchMoveSubject]; break;
        case 201: [self handleBatchMarkMastered]; break;
        case 202: [self handleExportPracticePaper]; break;
        case 203: [self handleBatchDelete]; break;
    }
}

// 1. 批量移科
- (void)handleBatchMoveSubject {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"批量移入指定科目 (%lu 题)", (unsigned long)self.selectedIds.count]
                                                                   message:@"请选择目标科目"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *subs = @[@"数学", @"物理", @"化学", @"语文", @"英语", @"生物", @"历史", @"地理", @"政治"];
    for (NSString *sub in subs) {
        [sheet addAction:[UIAlertAction actionWithTitle:sub style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            for (NSString *qid in self.selectedIds) {
                [[GSCacheManager sharedManager] updateWrongQuestionLocally:qid subject:sub knowledgePoint:nil mistakeCause:nil questionText:nil];
                [[GSAPIClient sharedClient] updateWrongQuestion:qid subject:sub knowledgePoint:nil mistakeCause:nil questionTitle:nil completion:nil];
            }
            [self.selectedIds removeAllObjects];
            [self loadData];
            [self showToast:[NSString stringWithFormat:@"已成功批量移入「%@」", sub]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 2. 批量标记掌握
- (void)handleBatchMarkMastered {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"批量标记已掌握"
                                                                   message:[NSString stringWithFormat:@"确定将选中的 %lu 道错题标记为「已掌握」吗？", (unsigned long)self.selectedIds.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        for (GSWrongQuestion *q in self.allQuestions) {
            if ([self.selectedIds containsObject:q.questionId]) {
                q.isMastered = YES;
            }
        }
        [[GSCacheManager sharedManager] saveWrongQuestions:self.allQuestions];
        NSUInteger count = self.selectedIds.count;
        [self.selectedIds removeAllObjects];
        [self updateDashboard];
        [self.tableView reloadData];
        [self showToast:[NSString stringWithFormat:@"已将 %lu 道错题标记为已掌握", (unsigned long)count]];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@interface GSPaperPreviewViewController : UIViewController
@property (nonatomic, strong) NSArray<GSWrongQuestion *> *questions;
@property (nonatomic, copy) NSString *fullPaperText;
@end

@implementation GSPaperPreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"📄 试卷预览与导出 (%lu 题)", (unsigned long)self.questions.count];
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];

    UIBarButtonItem *btnClose = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(handleClose)];
    self.navigationItem.leftBarButtonItem = btnClose;

    UIBarButtonItem *btnCopy = [[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(handleCopy)];
    UIBarButtonItem *btnShare = [[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain target:self action:@selector(handleShare)];
    self.navigationItem.rightBarButtonItems = @[btnShare, btnCopy];

    [self setupUI];
}

- (void)handleClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleCopy {
    [UIPasteboard generalPasteboard].string = self.fullPaperText;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"试卷全文已复制到剪贴板，可粘贴至文档打印" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleShare {
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[self.fullPaperText ?: @""] applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
}

- (void)setupUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scrollView];

    CGFloat curY = 16.0;

    // 1. 试卷卷头信息卡
    UIView *headerCard = [[UIView alloc] initWithFrame:CGRectMake(16, curY, screenW - 32, 100)];
    headerCard.backgroundColor = [UIColor whiteColor];
    headerCard.layer.cornerRadius = 10.0;
    headerCard.layer.shadowColor = [UIColor blackColor].CGColor;
    headerCard.layer.shadowOpacity = 0.05;
    headerCard.layer.shadowOffset = CGSizeMake(0, 2);
    headerCard.layer.shadowRadius = 4.0;
    [scrollView addSubview:headerCard];

    UILabel *lblPaperTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 14, screenW - 56, 22)];
    lblPaperTitle.font = [UIFont boldSystemFontOfSize:17];
    lblPaperTitle.textAlignment = NSTextAlignmentCenter;
    lblPaperTitle.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    lblPaperTitle.text = @"高斯知衡 · 错题专项巩固强化练习卷";
    [headerCard addSubview:lblPaperTitle];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    NSString *dateStr = [fmt stringFromDate:[NSDate date]];

    UILabel *lblSubInfo = [[UILabel alloc] initWithFrame:CGRectMake(12, 42, screenW - 56, 18)];
    lblSubInfo.font = [UIFont systemFontOfSize:12];
    lblSubInfo.textAlignment = NSTextAlignmentCenter;
    lblSubInfo.textColor = [UIColor grayColor];
    lblSubInfo.text = @"考试时长：60 分钟    满分：100 分    得分：_______";
    [headerCard addSubview:lblSubInfo];

    UILabel *lblStudent = [[UILabel alloc] initWithFrame:CGRectMake(12, 66, screenW - 56, 18)];
    lblStudent.font = [UIFont systemFontOfSize:12];
    lblStudent.textAlignment = NSTextAlignmentCenter;
    lblStudent.textColor = [UIColor grayColor];
    lblStudent.text = [NSString stringWithFormat:@"姓名：___________    班级：___________    日期：%@", dateStr];
    [headerCard addSubview:lblStudent];

    curY += 114.0;

    // 2. 逐题渲染
    for (NSInteger i = 0; i < self.questions.count; i++) {
        GSWrongQuestion *q = self.questions[i];
        NSInteger num = i + 1;

        UIView *qCard = [[UIView alloc] initWithFrame:CGRectMake(16, curY, screenW - 32, 200)];
        qCard.backgroundColor = [UIColor whiteColor];
        qCard.layer.cornerRadius = 10.0;
        qCard.layer.shadowColor = [UIColor blackColor].CGColor;
        qCard.layer.shadowOpacity = 0.05;
        qCard.layer.shadowOffset = CGSizeMake(0, 2);
        qCard.layer.shadowRadius = 4.0;
        [scrollView addSubview:qCard];

        CGFloat innerY = 12.0;

        // 题号 & 标签
        UILabel *numBadge = [[UILabel alloc] initWithFrame:CGRectMake(14, innerY, 60, 22)];
        numBadge.font = [UIFont boldSystemFontOfSize:14];
        numBadge.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
        numBadge.text = [NSString stringWithFormat:@"第 %ld 题", (long)num];
        [qCard addSubview:numBadge];

        UILabel *subBadge = [[UILabel alloc] initWithFrame:CGRectMake(80, innerY, 48, 22)];
        subBadge.backgroundColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:0.12];
        subBadge.textColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.93 alpha:1.0];
        subBadge.font = [UIFont boldSystemFontOfSize:11];
        subBadge.textAlignment = NSTextAlignmentCenter;
        subBadge.layer.cornerRadius = 4.0;
        subBadge.layer.masksToBounds = YES;
        subBadge.text = q.subject ?: @"学科";
        [qCard addSubview:subBadge];

        UILabel *kpBadge = [[UILabel alloc] initWithFrame:CGRectMake(134, innerY, screenW - 32 - 146, 22)];
        kpBadge.font = [UIFont systemFontOfSize:12];
        kpBadge.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0];
        kpBadge.text = [NSString stringWithFormat:@"考点：%@", q.knowledgePoint ?: @"综合应用"];
        [qCard addSubview:kpBadge];

        innerY += 30.0;

        // 题干文字
        UILabel *stemLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, innerY, screenW - 60, 20)];
        stemLbl.font = [UIFont systemFontOfSize:14];
        stemLbl.textColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0];
        stemLbl.numberOfLines = 0;
        if (q.questionText.length > 0 && ![q.questionText hasSuffix:@"错题"]) {
            stemLbl.text = q.questionText;
        } else if (q.sourceImageUri.length > 0) {
            stemLbl.text = @"【请根据下方试卷切片原题进行审题作答】";
        } else {
            stemLbl.text = [NSString stringWithFormat:@"【%@ · 考点突破：%@】请根据考纲核心题型进行演算推导与解题。", q.subject ?: @"学科", q.knowledgePoint ?: @"核心考点"];
        }
        [stemLbl sizeToFit];
        stemLbl.frame = CGRectMake(14, innerY, screenW - 60, stemLbl.bounds.size.height);
        [qCard addSubview:stemLbl];

        innerY += stemLbl.bounds.size.height + 10.0;

        // 试卷原题切片图
        if (q.sourceImageUri.length > 0) {
            UIImage *img = [[GSCacheManager sharedManager] loadImageFromDisk:q.sourceImageUri];
            if (img) {
                CGFloat imgW = screenW - 60;
                CGFloat imgH = (img.size.width > 0) ? (imgW * img.size.height / img.size.width) : 120.0;
                if (imgH > 350.0) imgH = 350.0;
                if (imgH < 80.0) imgH = 80.0;

                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(14, innerY, imgW, imgH)];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.image = img;
                iv.layer.cornerRadius = 6.0;
                iv.layer.masksToBounds = YES;
                iv.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
                [qCard addSubview:iv];

                innerY += imgH + 12.0;
            }
        }

        // 解答与作答留白区
        UIView *ansSpace = [[UIView alloc] initWithFrame:CGRectMake(14, innerY, screenW - 60, 100)];
        ansSpace.backgroundColor = [UIColor colorWithRed:0.98 green:0.98 blue:0.99 alpha:1.0];
        ansSpace.layer.cornerRadius = 6.0;
        ansSpace.layer.borderWidth = 1.0;
        ansSpace.layer.borderColor = [UIColor colorWithRed:0.85 green:0.88 blue:0.92 alpha:1.0].CGColor;
        [qCard addSubview:ansSpace];

        UILabel *lblAnsTip = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, 160, 16)];
        lblAnsTip.font = [UIFont systemFontOfSize:11];
        lblAnsTip.textColor = [UIColor colorWithRed:0.6 green:0.65 blue:0.7 alpha:1.0];
        lblAnsTip.text = @"【解答与作答留白区】";
        [ansSpace addSubview:lblAnsTip];

        innerY += 100.0 + 14.0;

        qCard.frame = CGRectMake(16, curY, screenW - 32, innerY);
        curY += innerY + 14.0;
    }

    // 3. 参考答案与解析卡
    UIView *ansCard = [[UIView alloc] initWithFrame:CGRectMake(16, curY, screenW - 32, 100)];
    ansCard.backgroundColor = [UIColor whiteColor];
    ansCard.layer.cornerRadius = 10.0;
    ansCard.layer.shadowColor = [UIColor blackColor].CGColor;
    ansCard.layer.shadowOpacity = 0.05;
    ansCard.layer.shadowOffset = CGSizeMake(0, 2);
    ansCard.layer.shadowRadius = 4.0;
    [scrollView addSubview:ansCard];

    UILabel *lblAnsHead = [[UILabel alloc] initWithFrame:CGRectMake(14, 14, screenW - 60, 20)];
    lblAnsHead.font = [UIFont boldSystemFontOfSize:14];
    lblAnsHead.textColor = [UIColor colorWithRed:0.15 green:0.39 blue:0.92 alpha:1.0];
    lblAnsHead.text = @"💡 参考答案与名师解析卡";
    [ansCard addSubview:lblAnsHead];

    CGFloat ansInnerY = 40.0;
    for (NSInteger i = 0; i < self.questions.count; i++) {
        GSWrongQuestion *q = self.questions[i];
        NSInteger num = i + 1;

        UILabel *itemAns = [[UILabel alloc] initWithFrame:CGRectMake(14, ansInnerY, screenW - 60, 20)];
        itemAns.font = [UIFont systemFontOfSize:12];
        itemAns.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
        itemAns.numberOfLines = 0;
        itemAns.text = [NSString stringWithFormat:@"第 %ld 题【核心考点】：%@\n【易错盲区分析】：%@\n【解题关键提示】：严格审清题意，分步规范作答并检验边界条件。",
                        (long)num,
                        q.knowledgePoint ?: @"核心概念",
                        q.mistakeCause ?: @"审题不清 / 计算疏忽"];
        [itemAns sizeToFit];
        itemAns.frame = CGRectMake(14, ansInnerY, screenW - 60, itemAns.bounds.size.height);
        [ansCard addSubview:itemAns];

        ansInnerY += itemAns.bounds.size.height + 12.0;
    }

    ansCard.frame = CGRectMake(16, curY, screenW - 32, ansInnerY + 8.0);
    curY += ansCard.bounds.size.height + 24.0;

    scrollView.contentSize = CGSizeMake(screenW, curY);
}

@end

// 3. 组卷导出
- (void)handleExportPracticePaper {
    NSMutableArray<GSWrongQuestion *> *chosen = [NSMutableArray array];
    for (GSWrongQuestion *q in self.allQuestions) {
        if ([self.selectedIds containsObject:q.questionId]) {
            [chosen addObject:q];
        }
    }

    if (chosen.count == 0) {
        [self showToast:@"请至少勾选一道题目进行组卷"];
        return;
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    NSString *dateStr = [fmt stringFromDate:[NSDate date]];

    NSMutableString *paper = [NSMutableString string];
    [paper appendString:@"====================================================\n"];
    [paper appendString:@"         高斯知衡 · 错题专项巩固强化练习卷         \n"];
    [paper appendString:@"====================================================\n"];
    [paper appendFormat:@"姓名：___________    日期：%@    时长：60 分钟\n", dateStr];
    [paper appendString:@"满分：100 分         得分：_______\n"];
    [paper appendString:@"----------------------------------------------------\n\n"];

    NSMutableString *answers = [NSMutableString string];
    [answers appendString:@"\n\n====================================================\n"];
    [answers appendString:@"            【参考答案与名师解析卡】                \n"];
    [answers appendString:@"====================================================\n"];

    for (NSInteger i = 0; i < chosen.count; i++) {
        GSWrongQuestion *q = chosen[i];
        NSInteger num = i + 1;
        [paper appendFormat:@"第 %ld 题（%@ · 考点：%@）\n", (long)num, q.subject ?: @"学科", q.knowledgePoint ?: @"综合应用"];
        NSString *stem = (q.questionText.length > 0 && ![q.questionText hasSuffix:@"错题"]) ? q.questionText : @"【详见试卷原题切片】";
        [paper appendFormat:@"%@\n\n", stem];
        [paper appendString:@"【解答与作答留白区】：\n\n\n\n\n"];
        [paper appendString:@"----------------------------------------------------\n"];

        [answers appendFormat:@"第 %ld 题【核心考点】：%@\n", (long)num, q.knowledgePoint ?: @"核心概念"];
        [answers appendFormat:@"【易错盲区分析】：%@\n", q.mistakeCause ?: @"审题不清 / 计算失误"];
        [answers appendString:@"【名师解析提示】：紧扣定理定义，规范书写步骤，检验极值条件。\n\n"];
    }

    NSString *fullText = [NSString stringWithFormat:@"%@%@", paper, answers];

    GSPaperPreviewViewController *previewVC = [[GSPaperPreviewViewController alloc] init];
    previewVC.questions = chosen;
    previewVC.fullPaperText = fullText;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:previewVC];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

// 4. 批量删除
- (void)handleBatchDelete {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"批量删除确认"
                                                                   message:[NSString stringWithFormat:@"确定要彻底删除选中的 %lu 道错题吗？相关的复习排程也将一并清除。", (unsigned long)self.selectedIds.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        for (NSString *qid in self.selectedIds) {
            [[GSCacheManager sharedManager] deleteWrongQuestionLocally:qid];
            [[GSAPIClient sharedClient] deleteWrongQuestion:qid completion:nil];
        }
        NSUInteger count = self.selectedIds.count;
        [self.selectedIds removeAllObjects];
        [self loadData];
        [self showToast:[NSString stringWithFormat:@"已批量删除 %lu 道错题", (unsigned long)count]];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 5. AI 考点聚类
- (void)handleAiClustering {
    if (self.allQuestions.count == 0) {
        [self showToast:@"当前题库无错题，无法开展 AI 考点聚类"];
        return;
    }

    NSMutableString *summary = [NSMutableString string];
    for (NSInteger i = 0; i < self.allQuestions.count; i++) {
        GSWrongQuestion *q = self.allQuestions[i];
        [summary appendFormat:@"%ld. [%@] 考点：%@ | 错因：%@\n", (long)(i + 1), q.subject ?: @"学科", q.knowledgePoint ?: @"重点", q.mistakeCause ?: @"未归类"];
    }

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"🤖 AI 考点聚类诊断中"
                                                                     message:@"正在调用 Qwen 27B 大模型对全部错题进行智能归纳与薄弱盲区深度聚类...\n请稍候..."
                                                              preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:loading animated:YES completion:^{
        [[GSOllamaClient sharedClient] requestKnowledgeClusteringForText:summary completion:^(NSString * _Nonnull report, NSString * _Nullable error) {
            [loading dismissViewControllerAnimated:YES completion:^{
                UIAlertController *resAlert = [UIAlertController alertControllerWithTitle:@"✨ AI 错题考点全景聚类诊断报告"
                                                                                  message:report
                                                                           preferredStyle:UIAlertControllerStyleAlert];

                [resAlert addAction:[UIAlertAction actionWithTitle:@"复制诊断报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [UIPasteboard generalPasteboard].string = report;
                    [self showToast:@"诊断报告已复制到剪贴板"];
                }]];

                [resAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:resAlert animated:YES completion:nil];
            }];
        }];
    }];
}

- (void)showToast:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end
