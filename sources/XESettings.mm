#import "XESettings.h"
#import "XEHelper.h"
#import "XEPrivate.h"
#import <objc/runtime.h>

static NSString *const kTrollSpeedURL = @"https://github.com/Lessica/TrollSpeed";
static NSString *const kTelegramURL   = @"https://t.me/xauszulay";
static NSString *const kAuthorGHURL   = @"https://github.com/xauszulay";

static UIColor *XECard(void)  { return [UIColor colorWithWhite:0.12 alpha:1.0]; }
static UIFont  *XEMono(CGFloat s, UIFontWeight w) { return [UIFont monospacedSystemFontOfSize:s weight:w]; }

#pragma mark - App delegate (tab bar)

@implementation XESettingsAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    XEHomeViewController *home = [XEHomeViewController new];
    home.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Main"
                                                    image:[UIImage systemImageNamed:@"house.fill"] tag:0];

    XESettingsViewController *settings = [XESettingsViewController new];
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                        image:[UIImage systemImageNamed:@"slider.horizontal.3"] tag:1];

    XECreditsViewController *credits = [XECreditsViewController new];
    credits.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Credits"
                                                       image:[UIImage systemImageNamed:@"person.2.fill"] tag:2];

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[ [[UINavigationController alloc] initWithRootViewController:home],
                              [[UINavigationController alloc] initWithRootViewController:settings],
                              [[UINavigationController alloc] initWithRootViewController:credits] ];
    tabs.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

#pragma mark - Home (VanTap-style)

@implementation XEHomeViewController {
    UIButton *_runButton;
    UIButton *_renderButton;
    UIButton *_targetButton;
    UILabel  *_statusLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationController.navigationBarHidden = YES;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-22],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-44],
    ]];

    // Title
    UILabel *title = [UILabel new];
    title.text = @"XExternalHUD";
    title.numberOfLines = 0;
    title.font = XEMono(40, UIFontWeightBold);
    title.textColor = [UIColor whiteColor];
    [stack addArrangedSubview:title];
    [stack setCustomSpacing:34 afterView:title];

    // Renderer picker. Just a tap-to-toggle button — a real UIMenu draws a
    // checkmark image, and that path blows up CoreImage in here.
    [stack addArrangedSubview:[self labelView:@"Select menu type"]];
    _renderButton = [self dropdownButtonWithChevron:@"⇄"];   // tap toggles uikit/imgui
    [_renderButton addTarget:self action:@selector(cycleRender) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:_renderButton];
    [stack setCustomSpacing:22 afterView:_renderButton];

    // Target app dropdown (pushes picker)
    [stack addArrangedSubview:[self labelView:@"Target app"]];
    _targetButton = [self dropdownButtonWithChevron:@"›"];   // pushes a picker
    [_targetButton addTarget:self action:@selector(openAppPicker) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:_targetButton];

    UILabel *hint = [UILabel new];
    hint.text = @"Session timer counts your time in the selected game (pauses when it\'s not active). \"Auto\" follows whatever app is in front.";
    hint.numberOfLines = 0;
    hint.font = XEMono(11, UIFontWeightRegular);
    hint.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    [stack addArrangedSubview:hint];
    [stack setCustomSpacing:26 afterView:hint];

    // Divider
    UIView *divider = [UIView new];
    divider.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [divider.heightAnchor constraintEqualToConstant:1].active = YES;
    [stack addArrangedSubview:divider];
    [stack setCustomSpacing:26 afterView:divider];

    // Run / Stop
    _runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _runButton.backgroundColor = XECard();
    _runButton.layer.cornerRadius = 14;
    _runButton.titleLabel.font = XEMono(20, UIFontWeightBold);
    [_runButton addTarget:self action:@selector(toggleHUD) forControlEvents:UIControlEventTouchUpInside];
    [_runButton.heightAnchor constraintEqualToConstant:62].active = YES;
    [stack addArrangedSubview:_runButton];

    _statusLabel = [UILabel new];
    _statusLabel.font = XEMono(12, UIFontWeightRegular);
    _statusLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:_statusLabel];
    [stack setCustomSpacing:18 afterView:_statusLabel];

    // Telegram link (white button)
    UIButton *link = [UIButton buttonWithType:UIButtonTypeSystem];
    link.backgroundColor = [UIColor whiteColor];
    link.layer.cornerRadius = 14;
    link.titleLabel.font = XEMono(18, UIFontWeightBold);
    [link setTitle:@"My Telegram" forState:UIControlStateNormal];
    [link setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [link addTarget:self action:@selector(openTelegram) forControlEvents:UIControlEventTouchUpInside];
    [link.heightAnchor constraintEqualToConstant:62].active = YES;
    [stack addArrangedSubview:link];

    UILabel *credits = [UILabel new];
    credits.numberOfLines = 0;
    credits.font = XEMono(11, UIFontWeightRegular);
    credits.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    credits.textAlignment = NSTextAlignmentCenter;
    credits.text = @"XExternalHUD  •  © xauszulay\nBuilt on TrollSpeed (MIT) © Lessica";
    [stack addArrangedSubview:credits];
}

#pragma mark Builders

- (UILabel *)labelView:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = XEMono(17, UIFontWeightMedium);
    l.textColor = [UIColor whiteColor];
    return l;
}

- (UIButton *)dropdownButtonWithChevron:(NSString *)chevron {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = XECard();
    b.layer.cornerRadius = 14;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(18, 18, 18, 44);
    b.titleLabel.font = XEMono(18, UIFontWeightRegular);
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    [b.heightAnchor constraintEqualToConstant:60].active = YES;

    // Don't drop an SF Symbol in a UIImageView here — styling the symbol goes
    // through CoreImage/GLContext and that hard-crashes in this environment.
    // Plain text glyph is the safe move.
    if (chevron.length) {
        UILabel *chev = [UILabel new];
        chev.text = chevron;
        chev.font = XEMono(20, UIFontWeightBold);
        chev.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        chev.translatesAutoresizingMaskIntoConstraints = NO;
        [b addSubview:chev];
        [chev.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-18].active = YES;
        [chev.centerYAnchor constraintEqualToAnchor:b.centerYAnchor constant:-2].active = YES;
    }
    return b;
}

#pragma mark State

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    BOOL running = [XEHelper isHUDRunning];
    [_runButton setTitle:(running ? @"Stop" : @"Start") forState:UIControlStateNormal];
    [_runButton setTitleColor:(running ? [UIColor systemRedColor] : [UIColor whiteColor]) forState:UIControlStateNormal];
    _statusLabel.text = running ? @"● HUD running" : @"○ HUD stopped";

    NSString *render = [XEHelper stringForKey:@"RenderBackend" defaultValue:@"uikit"];
    [_renderButton setTitle:render forState:UIControlStateNormal];

    NSString *name = [XEHelper stringForKey:@"TargetName" defaultValue:@""];
    [_targetButton setTitle:(name.length ? name : @"Auto (current app)") forState:UIControlStateNormal];
}

#pragma mark Actions

- (void)cycleRender {
    NSString *cur = [XEHelper stringForKey:@"RenderBackend" defaultValue:@"uikit"];
    NSString *next = [cur isEqualToString:@"uikit"] ? @"imgui" : @"uikit";
    [XEHelper setObject:next forKey:@"RenderBackend"];
    [XEHelper postNotification:XE_NOTIFY_RELOAD];
    [self refresh];
}

- (void)toggleHUD {
    if ([XEHelper isHUDRunning]) [XEHelper stopHUD]; else [XEHelper startHUD];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)openAppPicker {
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:[XEAppPickerViewController new] animated:YES];
}

- (void)openTelegram {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kTelegramURL] options:@{} completionHandler:nil];
}

@end

#pragma mark - Credits tab

@implementation XECreditsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationController.navigationBarHidden = YES;

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];

    UILabel *title = [UILabel new];
    title.text = @"Credits";
    title.font = XEMono(30, UIFontWeightBold);
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];
    [stack setCustomSpacing:28 afterView:title];

    // --- xauszulay (author) ---
    [stack addArrangedSubview:[self sectionLabel:@"Made by xauszulay"]];
    [stack addArrangedSubview:[self linkButton:@"Telegram  @xauszulay" action:@selector(openMyTelegram)]];
    [stack addArrangedSubview:[self linkButton:@"GitHub  xauszulay" action:@selector(openMyGitHub)]];

    UIView *gap = [UIView new];
    [gap.heightAnchor constraintEqualToConstant:10].active = YES;
    [stack addArrangedSubview:gap];

    // --- TrollSpeed (base) ---
    [stack addArrangedSubview:[self sectionLabel:@"Built on TrollSpeed (MIT) — Lessica"]];
    [stack addArrangedSubview:[self linkButton:@"TrollSpeed on GitHub" action:@selector(openTrollSpeedGH)]];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.numberOfLines = 0;
    l.font = XEMono(15, UIFontWeightMedium);
    l.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (UIButton *)linkButton:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = XECard();
    b.layer.cornerRadius = 14;
    b.titleLabel.font = XEMono(17, UIFontWeightBold);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:54].active = YES;
    return b;
}

- (void)openURLString:(NSString *)s {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:s] options:@{} completionHandler:nil];
}
- (void)openMyTelegram  { [self openURLString:kTelegramURL]; }
- (void)openMyGitHub    { [self openURLString:kAuthorGHURL]; }
- (void)openTrollSpeedGH { [self openURLString:kTrollSpeedURL]; }

@end

#pragma mark - Detailed settings

typedef NS_ENUM(NSInteger, XESection) {
    XESectionMetrics = 0,
    XESectionAppearance,
    XESectionMisc,
    XESectionCount
};

static NSArray *XEMetricRows(void) {
    return @[ @[@"ShowAppName", @"App name"],
              @[@"ShowSession", @"Session time"],
              @[@"ShowClock",   @"Clock"],
              @[@"ShowBattery", @"Battery"],
              @[@"ShowCPU",     @"CPU usage"],
              @[@"ShowRAM",     @"RAM usage"],
              @[@"ShowNet",     @"Network speed"],
              @[@"ShowFPS",     @"FPS (screen)"] ];
}

// Only the top row + the diagonal corners — no center or side anchors.
static NSArray<NSString *> *XEPositionTitles(void)  { return @[@"↖️", @"⬆️", @"↗️", @"↙️", @"↘️"]; }
static NSArray<NSNumber *> *XEPositionValues(void)  { return @[@(0), @(1), @(2), @(6), @(8)]; }

@implementation XESettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Settings"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)pushReload { [XEHelper postNotification:XE_NOTIFY_RELOAD]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return XESectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case XESectionMetrics:    return XEMetricRows().count;
        case XESectionAppearance: return 4;   // position, font, opacity, color
        case XESectionMisc:       return 3;   // interval, hide-capture, reset
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case XESectionMetrics:    return @"Show";
        case XESectionAppearance: return @"Appearance";
        case XESectionMisc:       return @"Other";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch (indexPath.section) {
        case XESectionMetrics: {
            NSArray *row = XEMetricRows()[indexPath.row];
            cell.textLabel.text = row[1];
            UISwitch *sw = [UISwitch new];
            BOOL def = ![row[0] isEqual:@"ShowCPU"] && ![row[0] isEqual:@"ShowRAM"];
            sw.on = [XEHelper boolForKey:row[0] defaultValue:def];
            sw.accessibilityHint = row[0];
            [sw addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case XESectionAppearance: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Position";
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:XEPositionTitles()];
                NSInteger stored = [XEHelper integerForKey:@"Position" defaultValue:1];
                NSUInteger idx = [XEPositionValues() indexOfObject:@(stored)];
                seg.selectedSegmentIndex = (idx == NSNotFound) ? 1 : (NSInteger)idx;
                seg.frame = CGRectMake(0, 0, 230, 30);
                [seg addTarget:self action:@selector(changePosition:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = seg;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Font size";
                cell.accessoryView = [self sliderMin:9 max:28 value:[XEHelper doubleForKey:@"FontSize" defaultValue:12.0] action:@selector(changeFont:)];
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Background";
                cell.accessoryView = [self sliderMin:0 max:1 value:[XEHelper doubleForKey:@"BgOpacity" defaultValue:0.45] action:@selector(changeOpacity:)];
            } else {
                cell.textLabel.text = @"Text color";
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
                swatch.backgroundColor = [XEHelper colorFromHex:[XEHelper stringForKey:@"TextColor" defaultValue:@"#00FF66"]];
                swatch.layer.cornerRadius = 6;
                swatch.layer.borderWidth = 1;
                swatch.layer.borderColor = [UIColor separatorColor].CGColor;
                cell.accessoryView = swatch;
            }
            break;
        }
        case XESectionMisc: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Info upd interval";
                cell.accessoryView = [self sliderMin:0.25 max:3.0 value:[XEHelper doubleForKey:@"UpdateInterval" defaultValue:1.0] action:@selector(changeInterval:)];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Overlay";
                UISwitch *sw = [UISwitch new];
                sw.on = [XEHelper boolForKey:@"HideFromCapture" defaultValue:NO];
                sw.accessibilityHint = @"HideFromCapture";
                [sw addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else {
                cell.textLabel.text = @"Reset session timer";
                cell.textLabel.textColor = [UIColor systemBlueColor];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            break;
        }
    }
    return cell;
}

- (UISlider *)sliderMin:(float)mn max:(float)mx value:(float)v action:(SEL)action {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)toggleSwitch:(UISwitch *)sw { [XEHelper setObject:@(sw.on) forKey:sw.accessibilityHint]; [self pushReload]; }
- (void)changePosition:(UISegmentedControl *)seg {
    NSNumber *value = XEPositionValues()[seg.selectedSegmentIndex];
    [XEHelper setObject:value forKey:@"Position"]; [self pushReload];
}
- (void)changeFont:(UISlider *)s { [XEHelper setObject:@(round(s.value)) forKey:@"FontSize"]; [self pushReload]; }
- (void)changeOpacity:(UISlider *)s { [XEHelper setObject:@(s.value) forKey:@"BgOpacity"]; [self pushReload]; }
- (void)changeInterval:(UISlider *)s { [XEHelper setObject:@(s.value) forKey:@"UpdateInterval"]; [self pushReload]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == XESectionAppearance && indexPath.row == 3) {
        [self.navigationController pushViewController:[XEColorPickerViewController new] animated:YES];
    } else if (indexPath.section == XESectionMisc && indexPath.row == 2) {
        [XEHelper postNotification:XE_NOTIFY_RESET];
    }
}

@end

#pragma mark - App picker

@implementation XEAppPickerViewController {
    NSArray<NSDictionary *> *_apps;
    NSString *_selectedId;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Select app";
    _selectedId = [XEHelper stringForKey:@"TargetBundleId" defaultValue:@""];
    _apps = @[];
    [self loadApps];
}

- (void)loadApps {
    NSMutableArray *list = [NSMutableArray array];
    @try {
        Class wsCls = objc_getClass("LSApplicationWorkspace");
        LSApplicationWorkspace *ws = [wsCls defaultWorkspace];
        NSArray *all = [ws allApplications];
        for (LSApplicationProxy *proxy in all) {
            NSString *type = nil, *bid = nil, *name = nil;
            @try {
                type = [proxy applicationType];
                bid  = [proxy applicationIdentifier];
                name = [proxy localizedName];
            } @catch (__unused NSException *e) { continue; }
            if (![type isEqualToString:@"User"]) continue;
            if (!bid.length || !name.length) continue;
            if ([bid isEqualToString:@"com.xexternal.hud"]) continue;
            [list addObject:@{ @"id": bid, @"name": name }];
        }
    } @catch (__unused NSException *e) {}

    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    _apps = list;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)_apps.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? nil : (_apps.count ? @"Installed apps" : @"App list unavailable");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL selected;
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Auto (current app)";
        selected = (_selectedId.length == 0);
    } else {
        NSDictionary *app = _apps[indexPath.row];
        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = app[@"id"];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        selected = [app[@"id"] isEqualToString:_selectedId];
    }
    // Plain "✓" text instead of UITableViewCellAccessoryCheckmark — its image
    // styling is another CoreImage landmine in here.
    if (selected) {
        UILabel *tick = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        tick.text = @"✓";
        tick.textColor = [UIColor systemGreenColor];
        tick.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        cell.accessoryView = tick;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [XEHelper removeObjectForKey:@"TargetBundleId"];
        [XEHelper removeObjectForKey:@"TargetName"];
    } else {
        NSDictionary *app = _apps[indexPath.row];
        [XEHelper setObject:app[@"id"] forKey:@"TargetBundleId"];
        [XEHelper setObject:app[@"name"] forKey:@"TargetName"];
    }
    [XEHelper postNotification:XE_NOTIFY_RELOAD];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Custom colour picker (no system images)

static NSArray<NSString *> *XEColorPresets(void) {
    return @[ @"#00FF66", @"#FFFFFF", @"#FF3B30", @"#FF9500", @"#FFD400", @"#34C759",
              @"#00C7FF", @"#0A84FF", @"#5E5CE6", @"#BF5AF2", @"#FF2D95", @"#FF6482",
              @"#AF52DE", @"#64D2FF", @"#30D158", @"#A0A0A0" ];
}

@implementation XEColorPickerViewController {
    UIView   *_preview;
    UILabel  *_hexLabel;
    UISlider *_rS, *_gS, *_bS;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Text color";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIColor *cur = [XEHelper colorFromHex:[XEHelper stringForKey:@"TextColor" defaultValue:@"#00FF66"]];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [cur getRed:&r green:&g blue:&b alpha:&a];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    // Preview + hex
    _preview = [UIView new];
    _preview.layer.cornerRadius = 12;
    _preview.backgroundColor = cur;
    [_preview.heightAnchor constraintEqualToConstant:64].active = YES;
    [stack addArrangedSubview:_preview];

    _hexLabel = [UILabel new];
    _hexLabel.textAlignment = NSTextAlignmentCenter;
    _hexLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:_hexLabel];

    // Swatch grid (4 per row), plain UIButtons coloured by backgroundColor.
    NSArray<NSString *> *presets = XEColorPresets();
    UIStackView *grid = [UIStackView new];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10;
    grid.distribution = UIStackViewDistributionFillEqually;
    UIStackView *rowSV = nil;
    for (NSUInteger i = 0; i < presets.count; i++) {
        if (i % 4 == 0) {
            rowSV = [UIStackView new];
            rowSV.axis = UILayoutConstraintAxisHorizontal;
            rowSV.spacing = 10;
            rowSV.distribution = UIStackViewDistributionFillEqually;
            [grid addArrangedSubview:rowSV];
        }
        UIButton *sw = [UIButton buttonWithType:UIButtonTypeCustom];
        sw.backgroundColor = [XEHelper colorFromHex:presets[i]];
        sw.layer.cornerRadius = 8;
        sw.layer.borderWidth = 1;
        sw.layer.borderColor = [UIColor separatorColor].CGColor;
        sw.tag = (NSInteger)i;
        [sw.heightAnchor constraintEqualToConstant:44].active = YES;
        [sw addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [rowSV addArrangedSubview:sw];
    }
    [stack addArrangedSubview:grid];

    // RGB sliders
    _rS = [self colorSlider:r * 255]; _gS = [self colorSlider:g * 255]; _bS = [self colorSlider:b * 255];
    [stack addArrangedSubview:[self sliderRow:@"R" slider:_rS]];
    [stack addArrangedSubview:[self sliderRow:@"G" slider:_gS]];
    [stack addArrangedSubview:[self sliderRow:@"B" slider:_bS]];

    [self updatePreviewAndSave:NO];
}

- (UISlider *)colorSlider:(CGFloat)value {
    UISlider *s = [UISlider new];
    s.minimumValue = 0; s.maximumValue = 255; s.value = value;
    [s addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UIView *)sliderRow:(NSString *)name slider:(UISlider *)slider {
    UILabel *l = [UILabel new];
    l.text = name;
    l.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightBold];
    [l.widthAnchor constraintEqualToConstant:22].active = YES;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, slider]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    return row;
}

- (void)swatchTapped:(UIButton *)sender {
    UIColor *c = [XEHelper colorFromHex:XEColorPresets()[sender.tag]];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    _rS.value = r * 255; _gS.value = g * 255; _bS.value = b * 255;
    [self updatePreviewAndSave:YES];
}

- (void)sliderChanged { [self updatePreviewAndSave:YES]; }

- (void)updatePreviewAndSave:(BOOL)save {
    UIColor *c = [UIColor colorWithRed:_rS.value / 255.0 green:_gS.value / 255.0 blue:_bS.value / 255.0 alpha:1.0];
    _preview.backgroundColor = c;
    NSString *hex = [XEHelper hexFromColor:c];
    _hexLabel.text = hex;
    if (save) {
        [XEHelper setObject:hex forKey:@"TextColor"];
        [XEHelper postNotification:XE_NOTIFY_RELOAD];
    }
}

@end
