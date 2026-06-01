#import "XEImGuiHUD.h"
#import "XEHelper.h"
#import "XEMetrics.h"
#import "XESecureView.h"
#import "XEPrivate.h"
#import <objc/runtime.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#import "imgui/imgui.h"
#import "imgui/imgui_impl_metal.h"

// Build tag we can show on-screen — TrollStore loves to keep a stale app around,
// so this is how you tell which binary is really running. Keep it in sync with
// control / Info.plist / get-version.sh.
#define XE_HUD_VERSION "1.8.4"

// Bare-bones MTKView forward decl so we dodge MetalKit's umbrella header under
// Theos. Real class comes from MetalKit.framework at link time.
@class MTKView;
@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(MTKView *)view;
@end
@interface MTKView : UIView
@property (nullable, nonatomic, strong) id<MTLDevice> device;
@property (nullable, nonatomic, weak) id<MTKViewDelegate> delegate;
@property (nonatomic) MTLClearColor clearColor;
@property (nullable, nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nullable, nonatomic, readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property (nonatomic) NSInteger preferredFramesPerSecond;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic) BOOL enableSetNeedsDisplay;
- (void)draw;
@end

// Two ways touches reach ImGui (same idea as Pasted's ImGuiDrawView):
//   1. real UITouches delivered to the view (TSEventFetcher in main.mm) -> gUIKit*.
//      the good ones, correct coords.
//   2. raw AX points injected from the HID callback -> gInj*. just a fallback for
//      when there's no real touch around.
// drawInMTKView trusts (1) whenever it's fresh so the sketchy injected point can't
// stomp on MousePos.
static __weak UIView *gImGuiHostView = nil;

static CGPoint        gUIKitPoint = {0, 0};
static bool           gUIKitDown  = false;
static bool           gHasUIKit   = false;
static CFTimeInterval gLastUIKitTime = 0.0;

static CGPoint        gInjPoint = {0, 0};
static bool           gInjDown  = false;
static bool           gHasInj   = false;
static CFTimeInterval gLastInjTime = 0.0;

// Debug counters (shown live in the HUD window to diagnose touch delivery).
int gHIDFireCount = 0;     // HID callback fired (main.mm)
int gAXInjectCount = 0;    // AX-decoded touch injected
int gUIKitTouchCount = 0;  // UIKit touchesBegan/Moved reached the VC
int gEvDispFound = 0;      // event dispatcher found in app init
int gEvInstalled = 0;      // _installEventRunLoopSources ran
int gHIDRegistered = 0;    // BKSHIDEventRegisterEventCallback was called
int gHIDRegRetNonNull = 0; // its return value was non-null (backboardd accepted)
int gEvFetcherSet = 0;     // UIEventFetcher set on the application (opens HID stream)
int gGSRan = 0;            // GSEventInitialize/PushRunLoopMode ran (iOS>=15 path)
int gEUID = -1;            // effective uid the HUD runs as (0=root, 501=mobile)
int gOSMajor = 0;          // iOS major version at runtime
int gHIDReg2 = 0;          // 2nd HID registration (after plugin start) accepted

extern "C" void XEHIDDidFire(void) { gHIDFireCount++; }

extern "C" void XEInjectImGuiTouch(CGPoint point, NSInteger phase, UIWindow *window) {
    UIView *host = gImGuiHostView;
    if (!host || !window) return;
    gInjPoint = [host convertPoint:point fromView:window];
    gInjDown  = (phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled);
    gHasInj   = true;
    gLastInjTime = CACurrentMediaTime();
    gAXInjectCount++;
}

// Screen-space rect of the ImGui window, updated each frame (diagnostics only).
static CGRect gImGuiWindowRect = CGRectZero;

// Rotation angle for a hosted (non-auto-rotating) window — same mapping the
// UIKit HUD uses.
static inline CGFloat XEImGuiOrientationAngle(UIInterfaceOrientation o) {
    switch (o) {
        case UIInterfaceOrientationPortraitUpsideDown: return M_PI;
        case UIInterfaceOrientationLandscapeLeft:      return -M_PI_2;
        case UIInterfaceOrientationLandscapeRight:     return M_PI_2;
        default:                                       return 0.0;
    }
}

// Fullscreen child MTKView, copied from Pasted's TouchableMTKView. hitTest
// always returns self, so the container resolves every touch onto this view (which
// isn't the container), and the window grabs it instead of leaking it to the game.
// Touches get forwarded up to the view controller via touchDelegate.
@interface XETouchableMTKView : MTKView
@property (nonatomic, weak) id touchDelegate;
@end
@implementation XETouchableMTKView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return self; }
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    if ([self.touchDelegate respondsToSelector:@selector(touchesBegan:withEvent:)]) [self.touchDelegate touchesBegan:t withEvent:e];
}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    if ([self.touchDelegate respondsToSelector:@selector(touchesMoved:withEvent:)]) [self.touchDelegate touchesMoved:t withEvent:e];
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    if ([self.touchDelegate respondsToSelector:@selector(touchesEnded:withEvent:)]) [self.touchDelegate touchesEnded:t withEvent:e];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    if ([self.touchDelegate respondsToSelector:@selector(touchesCancelled:withEvent:)]) [self.touchDelegate touchesCancelled:t withEvent:e];
}
@end

@interface XEImGuiHUDViewController () <MTKViewDelegate>
@end

@implementation XEImGuiHUDViewController {
    id<MTLDevice>       _device;
    id<MTLCommandQueue> _queue;
    XETouchableMTKView *_mtk;
    UIView             *_caPoke;     // forces CA transactions so the hosted window recomposites
    CADisplayLink      *_link;
    XEMetrics          *_metrics;

    NSArray<NSString *> *_lines;
    NSTimeInterval _lastSample;

    // cached settings
    BOOL   _showAppName, _showSession, _showClock, _showBattery, _showRAM, _showCPU, _showNet, _showFPS;
    double _fontSize, _bgOpacity, _interval;
    float  _r, _g, _b;
    BOOL   _hideCapture;
    NSInteger _position;   // XEHUDPosition anchor (mirrors the UIKit HUD)

    // Orientation (hosted windows don't auto-rotate)
    FBSOrientationObserver *_orientationObserver;
    UIInterfaceOrientation   _orientation;
}

- (instancetype)init {
    if ((self = [super init])) {
        _metrics = [XEMetrics new];
        _lines = @[];

        _device = MTLCreateSystemDefaultDevice();
        _queue  = [_device newCommandQueue];

        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGuiIO &io = ImGui::GetIO();
        io.IniFilename = NULL;
        ImGui::StyleColorsDark();
        io.Fonts->AddFontDefault();

        ImGui_ImplMetal_Init(_device);
    }
    return self;
}

// Same layout as Pasted: rootVC.view is a plain container with a
// fullscreen TouchableMTKView living inside it. The window hands hit tests to the
// container and only passes through when nothing real got hit. Since the MTKView
// fills the screen and always claims the touch, the HUD eats everything over it —
// which is the piece we were missing before.
- (void)loadView {
    UIWindow *win = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    CGRect b = win ? win.bounds : [UIScreen mainScreen].bounds;

    UIView *container = [[UIView alloc] initWithFrame:b];
    container.backgroundColor = [UIColor clearColor];
    container.opaque = NO;
    container.userInteractionEnabled = YES;
    container.multipleTouchEnabled = YES;

    XETouchableMTKView *mtk = [[XETouchableMTKView alloc] initWithFrame:b];
    mtk.device = _device;
    mtk.delegate = self;
    mtk.clearColor = MTLClearColorMake(0, 0, 0, 0);
    mtk.backgroundColor = [UIColor clearColor];
    mtk.opaque = NO;
    mtk.userInteractionEnabled = YES;      // capture touches
    mtk.multipleTouchEnabled = YES;
    mtk.touchDelegate = self;              // forward to our touchesBegan/…
    mtk.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // We pump the draws ourselves so every Metal frame lines up with a CA commit.
    mtk.paused = YES;
    mtk.enableSetNeedsDisplay = NO;
    [container addSubview:mtk];

    _mtk = mtk;
    self.view = container;
    gImGuiHostView = mtk;                   // target for HID touch injection
}

#pragma mark - Touches (delivered when over the ImGui window) → ImGui input

- (void)_feedTouches:(NSSet<UITouch *> *)touches down:(BOOL)down {
    UITouch *t = touches.anyObject;
    if (!t) return;
    CGPoint p = [t locationInView:self.view];
    gUIKitPoint = p;
    gUIKitDown  = down;
    gHasUIKit   = true;
    gLastUIKitTime = CACurrentMediaTime();
    if (down) gHasInj = false;   // real touch wins, drop the injected fallback
    gUIKitTouchCount++;
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self _feedTouches:t down:YES]; }
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self _feedTouches:t down:YES]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self _feedTouches:t down:NO];  }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self _feedTouches:t down:NO];  }

- (void)viewDidLoad {
    [super viewDidLoad];

    // Little invisible view we poke every frame. Touching a CALayer prop kicks off
    // a CA transaction, which makes backboardd recomposite the hosted window so the
    // fresh Metal frame actually shows up. Without it a Metal-only window just
    // freezes on its first empty frame. Dumb, but it works.
    _caPoke = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 2, 2)];
    _caPoke.backgroundColor = [UIColor clearColor];
    _caPoke.userInteractionEnabled = NO;
    [self.view addSubview:_caPoke];

    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step)];
    _link.preferredFramesPerSecond = 60;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

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
    __weak XEImGuiHUDViewController *weakSelf = self;
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

    // Spin the container; the fullscreen MTKView rides along (flexible autoresize),
    // so ImGui's DisplaySize just picks up the new landscape size on its own.
    [UIView animateWithDuration:duration animations:^{
        self.view.bounds = bounds;
        self.view.transform = CGAffineTransformMakeRotation(XEImGuiOrientationAngle(orientation));
        [self.view layoutIfNeeded];
    }];
}

- (void)step {
    [_mtk draw];                                                  // one Metal/ImGui frame
    _caPoke.layer.opacity = (_caPoke.layer.opacity < 0.99f) ? 1.0f : 0.98f;  // poke a CA commit
}

- (void)dealloc {
    [_link invalidate];
}

#pragma mark - XEHUDRenderer

- (void)reloadSettings {
    _showAppName = [XEHelper boolForKey:@"ShowAppName" defaultValue:YES];
    _showSession = [XEHelper boolForKey:@"ShowSession" defaultValue:YES];
    _showClock   = [XEHelper boolForKey:@"ShowClock"   defaultValue:YES];
    _showBattery = [XEHelper boolForKey:@"ShowBattery" defaultValue:YES];
    _showRAM     = [XEHelper boolForKey:@"ShowRAM"     defaultValue:NO];
    _showCPU     = [XEHelper boolForKey:@"ShowCPU"     defaultValue:NO];
    _showNet     = [XEHelper boolForKey:@"ShowNet"     defaultValue:YES];
    _showFPS     = [XEHelper boolForKey:@"ShowFPS"     defaultValue:YES];

    [_metrics setTargetBundleId:[XEHelper stringForKey:@"TargetBundleId" defaultValue:@""]
                           name:[XEHelper stringForKey:@"TargetName" defaultValue:@""]];

    _fontSize  = [XEHelper doubleForKey:@"FontSize" defaultValue:12.0];
    _bgOpacity = [XEHelper doubleForKey:@"BgOpacity" defaultValue:0.45];
    _interval  = [XEHelper doubleForKey:@"UpdateInterval" defaultValue:1.0];
    _hideCapture = [XEHelper boolForKey:@"HideFromCapture" defaultValue:NO];
    _position  = [XEHelper integerForKey:@"Position" defaultValue:1];   // default top-center

    UIColor *c = [XEHelper colorFromHex:[XEHelper stringForKey:@"TextColor" defaultValue:@"#00FF66"]];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    _r = r; _g = g; _b = b;

    [_mtk xe_hideFromCapture:_hideCapture];
    _lastSample = 0;
}

- (void)resetSession { [_metrics resetSession]; }

#pragma mark - Content (ASCII only — the stock font has no emoji/Cyrillic glyphs)

- (void)refreshLines {
    [_metrics sample];
    NSMutableArray<NSString *> *p = [NSMutableArray array];
    if (_showAppName) [p addObject:[NSString stringWithFormat:@"APP %@", [self ascii:[_metrics appNameString]]]];
    if (_showSession) [p addObject:[NSString stringWithFormat:@"SES %@", [_metrics sessionString]]];
    if (_showClock)   [p addObject:[NSString stringWithFormat:@"CLK %@", [_metrics clockString]]];
    if (_showBattery) [p addObject:[NSString stringWithFormat:@"BAT %@", [_metrics batteryString]]];
    if (_showCPU)     [p addObject:[NSString stringWithFormat:@"CPU %@", [_metrics cpuString]]];
    if (_showRAM)     [p addObject:[NSString stringWithFormat:@"RAM %@", [_metrics ramString]]];
    if (_showNet) {
        NSString *net = [[[_metrics netString] stringByReplacingOccurrencesOfString:@"↓" withString:@"v"]
                                               stringByReplacingOccurrencesOfString:@"↑" withString:@"^"];
        [p addObject:[NSString stringWithFormat:@"NET %@", net]];
    }
    _lines = p;
}

- (NSString *)ascii:(NSString *)s {
    NSData *d = [s dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *o = [[[NSString alloc] initWithData:d encoding:NSASCIIStringEncoding]
                   stringByReplacingOccurrencesOfString:@"?" withString:@""];
    return o.length ? o : @"app";
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        ImGuiIO &io = ImGui::GetIO();
        io.DisplaySize = ImVec2((float)view.bounds.size.width, (float)view.bounds.size.height);
        CGFloat scale = view.window.screen.scale ?: [UIScreen mainScreen].scale;
        io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);
        io.DeltaTime = 1.0f / 60.0f;

        // Feed touch in before NewFrame locks it in. Real UITouches win while
        // they're fresh or still held down; otherwise fall back to the AX point.
        CFTimeInterval tnow = CACurrentMediaTime();
        BOOL preferUIKit = gHasUIKit && ((tnow - gLastUIKitTime) < 0.35 || gUIKitDown);
        if (preferUIKit) {
            io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
            io.MousePos     = ImVec2((float)gUIKitPoint.x, (float)gUIKitPoint.y);
            io.MouseDown[0] = gUIKitDown;
        } else if (gHasInj) {
            io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
            io.MousePos     = ImVec2((float)gInjPoint.x, (float)gInjPoint.y);
            io.MouseDown[0] = gInjDown;
        }

        NSTimeInterval now = CACurrentMediaTime();
        if (_lastSample == 0 || now - _lastSample >= MAX(0.25, _interval)) {
            [self refreshLines];
            _lastSample = now;
        }

        id<MTLCommandBuffer> cb = [_queue commandBuffer];
        MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
        if (rpd != nil) {
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];

            ImGui_ImplMetal_NewFrame(rpd);
            ImGui::NewFrame();
            [self drawHUDWindow];
            ImGui::Render();
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);

            [enc endEncoding];
            [cb presentDrawable:view.currentDrawable];
        }
        [cb commit];
    }
}

// Pin the window to one of the 9 screen spots from settings (same XEHUDPosition
// the UIKit HUD uses). No title bar, no dragging — it just sits where you put it.
- (void)drawHUDWindow {
    ImGuiIO &io = ImGui::GetIO();

    const float mX = 8.0f, mTop = 8.0f, mBot = 8.0f;
    float px, py, ax, ay;
    switch (_position) {
        case 0: px = mX;                     py = mTop;                      ax = 0.0f; ay = 0.0f; break; // top-left
        case 2: px = io.DisplaySize.x - mX;  py = mTop;                      ax = 1.0f; ay = 0.0f; break; // top-right
        case 3: px = mX;                     py = io.DisplaySize.y * 0.5f;   ax = 0.0f; ay = 0.5f; break; // mid-left
        case 4: px = io.DisplaySize.x * 0.5f;py = io.DisplaySize.y * 0.5f;   ax = 0.5f; ay = 0.5f; break; // center
        case 5: px = io.DisplaySize.x - mX;  py = io.DisplaySize.y * 0.5f;   ax = 1.0f; ay = 0.5f; break; // mid-right
        case 6: px = mX;                     py = io.DisplaySize.y - mBot;   ax = 0.0f; ay = 1.0f; break; // bottom-left
        case 7: px = io.DisplaySize.x * 0.5f;py = io.DisplaySize.y - mBot;   ax = 0.5f; ay = 1.0f; break; // bottom-center
        case 8: px = io.DisplaySize.x - mX;  py = io.DisplaySize.y - mBot;   ax = 1.0f; ay = 1.0f; break; // bottom-right
        case 1: default: px = io.DisplaySize.x * 0.5f; py = mTop;            ax = 0.5f; ay = 0.0f; break; // top-center
    }
    ImGui::SetNextWindowPos(ImVec2(px, py), ImGuiCond_Always, ImVec2(ax, ay));
    ImGui::SetNextWindowBgAlpha(MAX(0.35f, (float)_bgOpacity));

    // Locked-down overlay: no title bar, no moving, no resizing.
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove |
                             ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                             ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_AlwaysAutoResize |
                             ImGuiWindowFlags_NoNav;

    // Flat like the UIKit HUD — square corners, no border, snug padding.
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(8.0f, 6.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6.0f, 3.0f));

    ImGui::Begin("XExternalHUD", nullptr, flags);

    // Remember where the window landed (screen points) for hit testing.
    ImVec2 wp = ImGui::GetWindowPos(), ws = ImGui::GetWindowSize();
    gImGuiWindowRect = CGRectMake(wp.x, wp.y, ws.x, ws.y);

    ImGui::SetWindowFontScale(MAX(1.0f, (float)_fontSize / 13.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(_r, _g, _b, 1.0f));
    if (_lines.count == 0) {
        ImGui::TextUnformatted("HUD running...");
    }
    for (NSString *line in _lines) {
        ImGui::TextUnformatted(line.UTF8String);
    }
    ImGui::PopStyleColor();

    // FPS line, color-coded: red under 30, yellow under 60, green above.
    if (_showFPS) {
        float fps = (float)[_metrics currentFPS];
        ImVec4 col = (fps < 30.0f) ? ImVec4(1, 0.25f, 0.25f, 1)
                   : (fps < 60.0f) ? ImVec4(1, 0.85f, 0.2f, 1)
                                   : ImVec4(0.3f, 1, 0.4f, 1);
        ImGui::TextColored(col, "FPS %.0f", fps);
    }

#if 0   // touch-debug readout — flip to 1 when chasing input bugs
    extern int gHIDFireCount, gAXInjectCount, gUIKitTouchCount, gEvDispFound, gEvInstalled, gHIDRegistered, gEvFetcherSet, gHIDRegRetNonNull;
    ImGui::Separator();
    ImGui::Text("XExternalHUD v" XE_HUD_VERSION);   // build id (title bar removed)
    ImGui::Text("disp=%d inst=%d hidreg=%d fetch=%d ret=%d", gEvDispFound, gEvInstalled, gHIDRegistered, gEvFetcherSet, gHIDRegRetNonNull);
    extern int gGSRan, gEUID, gOSMajor, gHIDReg2;
    ImGui::Text("gs=%d euid=%d iOS=%d hidreg2=%d", gGSRan, gEUID, gOSMajor, gHIDReg2);
    ImGui::Text("HID fires : %d", gHIDFireCount);
    ImGui::Text("AX inject : %d", gAXInjectCount);
    ImGui::Text("UIKit tch : %d", gUIKitTouchCount);
    ImGui::Text("MousePos  : %.0f, %.0f", io.MousePos.x, io.MousePos.y);
    ImGui::Text("MouseDown : %d", io.MouseDown[0] ? 1 : 0);
    ImGui::Text("gUIKit    : %.0f,%.0f d=%d", gUIKitPoint.x, gUIKitPoint.y, gUIKitDown ? 1 : 0);
    ImGui::Text("gInj      : %.0f,%.0f d=%d", gInjPoint.x, gInjPoint.y, gInjDown ? 1 : 0);
    ImGui::Text("WantMouse : %d", io.WantCaptureMouse ? 1 : 0);
    ImGui::Text("WinRect   : %.0f,%.0f %.0fx%.0f",
                gImGuiWindowRect.origin.x, gImGuiWindowRect.origin.y,
                gImGuiWindowRect.size.width, gImGuiWindowRect.size.height);
    ImGui::Button("TAP TEST", ImVec2(140, 40));
    ImGui::Text(ImGui::IsItemActive() ? "BTN: ACTIVE" : (ImGui::IsItemHovered() ? "BTN: HOVER" : "BTN: idle"));
#endif

    ImGui::End();
    ImGui::PopStyleVar(4);
}

@end
