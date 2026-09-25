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

// 3. 组卷导出
- (void)handleExportPracticePaper {
    NSMutableArray<GSWrongQuestion *> *chosen = [NSMutableArray array];
    for (GSWrongQuestion *q in self.allQuestions) {
        if ([self.selectedIds containsObject:q.questionId]) {
            [chosen addObject:q];
        }
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
        [paper appendFormat:@"%@\n\n", q.questionText.length > 0 ? q.questionText : @"【详见试卷原题切片】"];
        [paper appendString:@"【解答与作答留白区】：\n\n\n\n\n"];
        [paper appendString:@"----------------------------------------------------\n"];

        [answers appendFormat:@"第 %ld 题【核心考点】：%@\n", (long)num, q.knowledgePoint ?: @"核心概念"];
        [answers appendFormat:@"【易错盲区分析】：%@\n", q.mistakeCause ?: @"审题不清 / 计算失误"];
        [answers appendString:@"【名师解析提示】：紧扣定理定义，规范书写步骤，检验极值条件。\n\n"];
    }

    NSString *fullText = [NSString stringWithFormat:@"%@%@", paper, answers];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"📄 组卷预览 (%lu 题)", (unsigned long)chosen.count]
                                                                   message:fullText
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"复制试卷全文" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = fullText;
        [self showToast:@"试卷全文已复制到剪贴板，可粘贴至文档打印"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[fullText] applicationActivities:nil];
        [self presentViewController:act animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
