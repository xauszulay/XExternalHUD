#import "XEHUDViewController.h"
#import "XEHelper.h"
#import "XEMetrics.h"
#import "XEPrivate.h"
#import "XESecureView.h"
#import <objc/runtime.h>

static inline CGFloat XEOrientationAngle(UIInterfaceOrientation o) {
    switch (o) {
        case UIInterfaceOrientationPortraitUpsideDown: return M_PI;
        case UIInterfaceOrientationLandscapeLeft:      return -M_PI_2;
        case UIInterfaceOrientationLandscapeRight:     return M_PI_2;
        default:                                       return 0;
    }
}

@implementation XEHUDViewController {
    UIView   *_pill;
    UILabel  *_label;
    XEMetrics *_metrics;
    NSTimer  *_timer;

    // Orientation
    FBSOrientationObserver *_orientationObserver;
    UIInterfaceOrientation _orientation;

    // Cached settings
    BOOL   _showSession, _showAppName, _showClock, _showBattery, _showRAM, _showCPU, _showNet, _showFPS;
    XEHUDPosition _position;
    double _fontSize;
    double _bgOpacity;
    double _interval;
    UIColor *_textColor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = NO;

    _metrics = [XEMetrics new];

    _pill = [[UIView alloc] initWithFrame:CGRectZero];
    _pill.layer.cornerRadius = 8.0;
    _pill.layer.masksToBounds = YES;
    [self.view addSubview:_pill];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.numberOfLines = 0;
    _label.textAlignment = NSTextAlignmentLeft;
    [_pill addSubview:_label];

    [self _setupOrientationObserver];
    [self reloadSettings];
}

#pragma mark - Orientation (hosted windows don't auto-rotate)

- (void)_setupOrientationObserver {
    _orientation = UIInterfaceOrientationPortrait;
    [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/FrontBoardServices.framework"] load];
    Class cls = objc_getClass("FBSOrientationObserver");
    if (!cls) return;

    _orientationObserver = [[cls alloc] init];
    __weak XEHUDViewController *weakSelf = self;
    [_orientationObserver setHandler:^(FBSOrientationUpdate *update) {
        UIInterfaceOrientation o = (UIInterfaceOrientation)update.orientation;
        NSTimeInterval d = update.duration;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _applyOrientation:o duration:d];
        });
    }];
}

- (void)_applyOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    if (orientation == _orientation || orientation == UIInterfaceOrientationUnknown) return;
    _orientation = orientation;

    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    CGRect bounds = landscape ? CGRectMake(0, 0, screen.size.height, screen.size.width) : screen;

    [UIView animateWithDuration:duration animations:^{
        self.view.bounds = bounds;
        self.view.transform = CGAffineTransformMakeRotation(XEOrientationAngle(orientation));
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)reloadSettings {
    _showSession = [XEHelper boolForKey:@"ShowSession" defaultValue:YES];
    _showAppName = [XEHelper boolForKey:@"ShowAppName" defaultValue:YES];
    _showClock   = [XEHelper boolForKey:@"ShowClock"   defaultValue:YES];
    _showBattery = [XEHelper boolForKey:@"ShowBattery" defaultValue:YES];
    _showRAM     = [XEHelper boolForKey:@"ShowRAM"     defaultValue:NO];
    _showCPU     = [XEHelper boolForKey:@"ShowCPU"     defaultValue:NO];
    _showNet     = [XEHelper boolForKey:@"ShowNet"     defaultValue:YES];
    _showFPS     = [XEHelper boolForKey:@"ShowFPS"     defaultValue:YES];

    NSString *targetId = [XEHelper stringForKey:@"TargetBundleId" defaultValue:@""];
    NSString *targetName = [XEHelper stringForKey:@"TargetName" defaultValue:@""];
    [_metrics setTargetBundleId:targetId name:targetName];

    _position  = (XEHUDPosition)[XEHelper integerForKey:@"Position" defaultValue:XEHUDPositionTopCenter];
    _fontSize  = [XEHelper doubleForKey:@"FontSize" defaultValue:12.0];
    _bgOpacity = [XEHelper doubleForKey:@"BgOpacity" defaultValue:0.45];
    _interval  = [XEHelper doubleForKey:@"UpdateInterval" defaultValue:1.0];
    _textColor = [XEHelper colorFromHex:[XEHelper stringForKey:@"TextColor" defaultValue:@"#00FF66"]];

    _pill.backgroundColor = [UIColor colorWithWhite:0.0 alpha:_bgOpacity];
    _label.font = [UIFont monospacedDigitSystemFontOfSize:_fontSize weight:UIFontWeightSemibold];
    _label.textColor = _textColor;

    // Hide from screen recordings / screenshots if requested.
    BOOL hideCapture = [XEHelper boolForKey:@"HideFromCapture" defaultValue:NO];
    [_pill xe_hideFromCapture:hideCapture];
    [self.view xe_hideFromCapture:hideCapture];

    [self _restartTimer];
    [self _refresh];
}

- (void)resetSession {
    [_metrics resetSession];
    [self _refresh];
}

- (void)_restartTimer {
    [_timer invalidate];
    double i = MAX(0.25, _interval);
    _timer = [NSTimer scheduledTimerWithTimeInterval:i target:self
                                            selector:@selector(_refresh)
                                            userInfo:nil repeats:YES];
}

- (void)_refresh {
    [_metrics sample];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_showAppName) [parts addObject:[NSString stringWithFormat:@"🎮 %@", [_metrics appNameString]]];
    if (_showSession) [parts addObject:[NSString stringWithFormat:@"⏱ %@", [_metrics sessionString]]];
    if (_showClock)   [parts addObject:[NSString stringWithFormat:@"🕐 %@", [_metrics clockString]]];
    if (_showBattery) [parts addObject:[NSString stringWithFormat:@"🔋 %@", [_metrics batteryString]]];
    if (_showCPU)     [parts addObject:[NSString stringWithFormat:@"CPU %@", [_metrics cpuString]]];
    if (_showRAM)     [parts addObject:[NSString stringWithFormat:@"RAM %@", [_metrics ramString]]];
    if (_showNet)     [parts addObject:[_metrics netString]];
    if (_showFPS)     [parts addObject:[NSString stringWithFormat:@"FPS %@", [_metrics fpsString]]];

    _label.text = [parts componentsJoinedByString:@"   "];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    const CGFloat hPad = 10.0, vPad = 5.0, margin = 8.0;

    // Hosted windows love to report zero safe-area insets, which would shove the
    // pill up under the notch / Dynamic Island / home indicator. So when the
    // system gives us nothing, just plug in some sane defaults.
    UIEdgeInsets ins = self.view.safeAreaInsets;
    if (ins.top == 0 && ins.bottom == 0 && ins.left == 0 && ins.right == 0) {
        BOOL landscape = UIInterfaceOrientationIsLandscape(_orientation);
        ins = landscape ? UIEdgeInsetsMake(12, 44, 21, 44) : UIEdgeInsetsMake(44, 12, 34, 12);
    }
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, ins);

    CGSize max = CGSizeMake(safe.size.width - 2 * margin, safe.size.height);
    CGSize textSize = [_label sizeThatFits:max];
    CGFloat w = ceil(textSize.width) + 2 * hPad;
    CGFloat h = ceil(textSize.height) + 2 * vPad;

    _label.frame = CGRectMake(hPad, vPad, ceil(textSize.width), ceil(textSize.height));

    CGFloat x, y;
    switch (_position) {
        case XEHUDPositionTopLeft:      x = safe.origin.x + margin;                         y = safe.origin.y + margin; break;
        case XEHUDPositionTopCenter:    x = safe.origin.x + (safe.size.width - w) / 2.0;     y = safe.origin.y + margin; break;
        case XEHUDPositionTopRight:     x = CGRectGetMaxX(safe) - w - margin;               y = safe.origin.y + margin; break;
        case XEHUDPositionMidLeft:      x = safe.origin.x + margin;                         y = safe.origin.y + (safe.size.height - h) / 2.0; break;
        case XEHUDPositionCenter:       x = safe.origin.x + (safe.size.width - w) / 2.0;     y = safe.origin.y + (safe.size.height - h) / 2.0; break;
        case XEHUDPositionMidRight:     x = CGRectGetMaxX(safe) - w - margin;               y = safe.origin.y + (safe.size.height - h) / 2.0; break;
        case XEHUDPositionBottomLeft:   x = safe.origin.x + margin;                         y = CGRectGetMaxY(safe) - h - margin; break;
        case XEHUDPositionBottomCenter: x = safe.origin.x + (safe.size.width - w) / 2.0;     y = CGRectGetMaxY(safe) - h - margin; break;
        case XEHUDPositionBottomRight:  x = CGRectGetMaxX(safe) - w - margin;               y = CGRectGetMaxY(safe) - h - margin; break;
        default:                        x = safe.origin.x + (safe.size.width - w) / 2.0;     y = safe.origin.y + margin; break;
    }
    _pill.frame = CGRectMake(round(x), round(y), w, h);
}

// Let it ride in any orientation.
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)dealloc {
    [_timer invalidate];
    [_orientationObserver invalidate];
}

@end
