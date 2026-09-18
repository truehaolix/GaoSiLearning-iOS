#import "GSLoginViewController.h"
#import "GSWrongBookViewController.h"
#import "GSAPIClient.h"
#import "GSCacheManager.h"

@interface GSLoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UITextField *tfUsername;
@property (nonatomic, strong) UITextField *tfPassword;
@property (nonatomic, strong) UISegmentedControl *segRole;
@property (nonatomic, strong) UIButton *btnLogin;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation GSLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"高斯知衡智能训考";
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
    [self setupUI];
    [self registerKeyboardNotifications];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    // 居中卡片
    _cardView = [[UIView alloc] init];
    _cardView.backgroundColor = [UIColor whiteColor];
    _cardView.layer.cornerRadius = 16.0;
    _cardView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    _cardView.layer.shadowOffset = CGSizeMake(0, 6);
    _cardView.layer.shadowRadius = 16.0;
    _cardView.layer.shadowOpacity = 1.0;
    [_scrollView addSubview:_cardView];

    // Logo / 标题
    UILabel *lblLogo = [[UILabel alloc] init];
    lblLogo.text = @"📐";
    lblLogo.font = [UIFont systemFontOfSize:44];
    lblLogo.textAlignment = NSTextAlignmentCenter;
    [_cardView addSubview:lblLogo];

    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.text = @"高斯知衡错题本";
    lblTitle.font = [UIFont boldSystemFontOfSize:22];
    lblTitle.textColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:1.0];
    lblTitle.textAlignment = NSTextAlignmentCenter;
    [_cardView addSubview:lblTitle];

    UILabel *lblSub = [[UILabel alloc] init];
    lblSub.text = @"智能视觉公式识别 · Qwen 27B 深度归因";
    lblSub.font = [UIFont systemFontOfSize:13];
    lblSub.textColor = [UIColor colorWithRed:0.50 green:0.55 blue:0.60 alpha:1.0];
    lblSub.textAlignment = NSTextAlignmentCenter;
    [_cardView addSubview:lblSub];

    // 输入框
    _tfUsername = [self createStyledTextFieldWithPlaceholder:@"请输入学号 / 用户名" isSecure:NO];
    _tfUsername.text = @"student1";
    [_cardView addSubview:_tfUsername];

    _tfPassword = [self createStyledTextFieldWithPlaceholder:@"请输入密码" isSecure:YES];
    _tfPassword.text = @"123456";
    [_cardView addSubview:_tfPassword];

    // 角色选择
    _segRole = [[UISegmentedControl alloc] initWithItems:@[@"学生身份", @"教师身份"]];
    _segRole.selectedSegmentIndex = 0;
    [_cardView addSubview:_segRole];

    // 登录按钮
    _btnLogin = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnLogin.backgroundColor = [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0];
    [_btnLogin setTitle:@"立即登录" forState:UIControlStateNormal];
    _btnLogin.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_btnLogin setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnLogin.layer.cornerRadius = 10;
    _btnLogin.layer.masksToBounds = YES;
    [_btnLogin addTarget:self action:@selector(handleLogin) forControlEvents:UIControlEventTouchUpInside];
    [_cardView addSubview:_btnLogin];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor whiteColor];
    _spinner.hidesWhenStopped = YES;
    [_btnLogin addSubview:_spinner];
}

- (UITextField *)createStyledTextFieldWithPlaceholder:(NSString *)ph isSecure:(BOOL)sec {
    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = ph;
    tf.secureTextEntry = sec;
    tf.font = [UIFont systemFontOfSize:15];
    tf.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
    tf.layer.cornerRadius = 10;
    tf.layer.borderWidth = 1.0;
    tf.layer.borderColor = [UIColor colorWithRed:0.90 green:0.92 blue:0.94 alpha:1.0].CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 20)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.delegate = self;
    return tf;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat screenW = self.view.bounds.size.width;
    CGFloat screenH = self.view.bounds.size.height;

    CGFloat cardW = MIN(screenW - 40, 420);
    CGFloat cardH = 430;
    CGFloat cardX = (screenW - cardW) / 2.0;
    CGFloat cardY = MAX(40, (screenH - cardH) / 2.0 - 30);

    _cardView.frame = CGRectMake(cardX, cardY, cardW, cardH);
    _scrollView.contentSize = CGSizeMake(screenW, cardY + cardH + 60);

    // 内部子控件布局
    CGFloat p = 24.0;
    CGFloat w = cardW - p * 2;

    UIView *logo = _cardView.subviews[0];
    logo.frame = CGRectMake(p, 20, w, 50);

    UIView *title = _cardView.subviews[1];
    title.frame = CGRectMake(p, 75, w, 28);

    UIView *sub = _cardView.subviews[2];
    sub.frame = CGRectMake(p, 105, w, 20);

    _tfUsername.frame = CGRectMake(p, 145, w, 46);
    _tfPassword.frame = CGRectMake(p, 205, w, 46);
    _segRole.frame = CGRectMake(p, 268, w, 36);
    _btnLogin.frame = CGRectMake(p, 330, w, 48);
    _spinner.center = CGPointMake(w - 35, 24);
}

- (void)handleLogin {
    [self dismissKeyboard];
    NSString *u = [_tfUsername.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *p = [_tfPassword.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *role = (_segRole.selectedSegmentIndex == 0) ? @"student" : @"teacher";

    if (u.length == 0 || p.length == 0) {
        [self showAlert:@"请输入用户名与密码"];
        return;
    }

    _btnLogin.enabled = NO;
    [_spinner startAnimating];

    [[GSAPIClient sharedClient] loginWithUsername:u password:p role:role completion:^(GSUser * _Nullable user, NSString * _Nullable error) {
        self.btnLogin.enabled = YES;
        [self.spinner stopAnimating];

        if (user) {
            GSWrongBookViewController *wrongVC = [[GSWrongBookViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:wrongVC];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
        } else {
            [self showAlert:error ?: @"登录失败，请检查服务连接"];
        }
    }];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)showAlert:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)registerKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGSize kbSize = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    _scrollView.contentInset = UIEdgeInsetsMake(0, 0, kbSize.height + 20, 0);
}

- (void)keyboardWillHide:(NSNotification *)note {
    _scrollView.contentInset = UIEdgeInsetsZero;
}

@end
