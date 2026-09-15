#import "GSQuestionSelectViewController.h"
#import "GSCropOverlayView.h"
#import "GSRecordDialogViewController.h"
#import "GSCaptureSession.h"
#import "ImageProcessor.hpp"

@interface GSQuestionSelectViewController () <GSCropOverlayDelegate>
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) GSCropOverlayView *overlayView;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *lblCount;
@property (nonatomic, strong) UIButton *btnNext;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) NSArray<NSValue *> *selectedBoxes;
@end

@implementation GSQuestionSelectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"框选题目区域";
    self.view.backgroundColor = [UIColor blackColor];
    _selectedBoxes = @[];

    [self setupUI];
    [self runAutoDetection];
}

- (void)setupUI {
    UIImage *img = [GSCaptureSession sharedSession].pageImage;

    _imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.image = img;
    _imageView.clipsToBounds = YES;
    _imageView.userInteractionEnabled = YES;
    [self.view addSubview:_imageView];

    _overlayView = [[GSCropOverlayView alloc] initWithFrame:self.view.bounds];
    _overlayView.imageSize = img ? img.size : CGSizeZero;
    _overlayView.delegate = self;
    [self.view addSubview:_overlayView];

    // 顶部工具条
    _topBar = [[UIView alloc] initWithFrame:CGRectZero];
    _topBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    [self.view addSubview:_topBar];

    UIButton *btnSelectAll = [self createBarButtonWithTitle:@"全选" action:@selector(handleSelectAll)];
    UIButton *btnClear = [self createBarButtonWithTitle:@"清空" action:@selector(handleClear)];
    UIButton *btnRedetect = [self createBarButtonWithTitle:@"重新自动识别" action:@selector(runAutoDetection)];
    [_topBar addSubview:btnSelectAll];
    [_topBar addSubview:btnClear];
    [_topBar addSubview:btnRedetect];

    // 底部操作栏
    _bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    [self.view addSubview:_bottomBar];

    _lblCount = [[UILabel alloc] init];
    _lblCount.textColor = [UIColor whiteColor];
    _lblCount.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _lblCount.text = @"已选中 0 道题目";
    [_bottomBar addSubview:_lblCount];

    _btnNext = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnNext.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    [_btnNext setTitle:@"下一步：录入错题" forState:UIControlStateNormal];
    _btnNext.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [_btnNext setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnNext.layer.cornerRadius = 8;
    [_btnNext addTarget:self action:@selector(handleNextStep) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_btnNext];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
}

- (UIButton *)createBarButtonWithTitle:(NSString *)title action:(SEL)sel {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    btn.layer.cornerRadius = 6;
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    _imageView.frame = self.view.bounds;
    _overlayView.frame = self.view.bounds;

    _topBar.frame = CGRectMake(0, top, w, 44);
    CGFloat btnW = (w - 32 - 16) / 3.0;
    UIView *b1 = _topBar.subviews[0];
    UIView *b2 = _topBar.subviews[1];
    UIView *b3 = _topBar.subviews[2];
    b1.frame = CGRectMake(16, 7, btnW, 30);
    b2.frame = CGRectMake(16 + btnW + 8, 7, btnW, 30);
    b3.frame = CGRectMake(16 + (btnW + 8) * 2, 7, btnW, 30);

    CGFloat botH = 64.0 + bottom;
    _bottomBar.frame = CGRectMake(0, h - botH, w, botH);
    _lblCount.frame = CGRectMake(16, 12, 140, 40);
    _btnNext.frame = CGRectMake(w - 176, 12, 160, 40);

    _spinner.center = self.view.center;
}

- (void)runAutoDetection {
    UIImage *img = [GSCaptureSession sharedSession].pageImage;
    if (!img) return;

    [_spinner startAnimating];
    self.btnNext.enabled = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSArray<NSValue *> *boxes = [GSImageProcessor detectQuestionBoxesInImage:img];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.btnNext.enabled = YES;
            [self.overlayView setCandidateBoxes:boxes];
        });
    });
}

#pragma mark - GSCropOverlayDelegate

- (void)cropOverlayDidUpdateSelection:(NSArray<NSValue *> *)selectedNormalizedRects {
    self.selectedBoxes = selectedNormalizedRects;
    self.lblCount.text = [NSString stringWithFormat:@"已选中 %ld 道题目", (long)selectedNormalizedRects.count];
    self.btnNext.enabled = (selectedNormalizedRects.count > 0);
    self.btnNext.alpha = (selectedNormalizedRects.count > 0) ? 1.0 : 0.5;
}

- (void)handleSelectAll {
    [self.overlayView selectAllBoxes];
}

- (void)handleClear {
    [self.overlayView clearSelection];
}

- (void)handleNextStep {
    if (self.selectedBoxes.count == 0) return;

    [GSCaptureSession sharedSession].selectedBoxes = [self.selectedBoxes mutableCopy];

    GSRecordDialogViewController *dialog = [[GSRecordDialogViewController alloc] init];
    dialog.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        dialog.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        dialog.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:dialog animated:YES completion:nil];
}

@end
