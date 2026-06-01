#import "XEHUDApplication.h"
#import "XEHUDWindow.h"
#import "XEHUDViewController.h"
#import "XEImGuiHUD.h"
#import "XEHelper.h"
#import "XEPrivate.h"
#import "pac_helper.h"
#import <objc/runtime.h>

@interface XEHUDApplication ()
- (BOOL)xeInstallEventSourcesFallback:(UIEventDispatcher *)dispatcher;
@end

@implementation XEHUDApplication

// Wire up the UIKit event run-loop sources + fetcher by hand. We never went
// through UIApplicationMain, so nobody set these up for us, and without them the
// app gets zero touches. Lifted from TrollSpeed / Pasted.
- (instancetype)init {
    if ((self = [super init])) {
        extern int gEvDispFound, gEvInstalled;
        UIEventDispatcher *dispatcher = [self valueForKey:@"eventDispatcher"];
        if (dispatcher) {
            gEvDispFound = 1;
            if ([dispatcher respondsToSelector:@selector(_installEventRunLoopSources:)]) {
                [dispatcher _installEventRunLoopSources:CFRunLoopGetMain()];
                gEvInstalled = 1;
            } else {
                // inst=3 -> ARM64 scan found & called the inlined installer.
                // inst=2 -> scan FAILED (no event sources installed -> no touches).
                BOOL ok = [self xeInstallEventSourcesFallback:dispatcher];
                gEvInstalled = ok ? 3 : 2;
            }
            UIEventFetcher *fetcher = [[objc_getClass("UIEventFetcher") alloc] init];
            [dispatcher setValue:fetcher forKey:@"eventFetcher"];
            if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)])
                [fetcher setEventFetcherSink:dispatcher];
            else
                [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];

            // Don't forget to stick the fetcher on the app itself too — this is
            // the bit that actually opens the HID stream from backboardd. Miss it
            // and your callback is registered but never gets called. Fun bug.
            [self setValue:fetcher forKey:@"eventFetcher"];
            extern int gEvFetcherSet;
            gEvFetcherSet = 1;
        }
    }
    return self;
}

// On some iOS builds _installEventRunLoopSources: is inlined away, so we go
// digging for the call inside -[UIApplication _run] by scanning the ARM64. Hacky
// but it's the only way. Returns YES if we found it and called it.
- (BOOL)xeInstallEventSourcesFallback:(UIEventDispatcher *)dispatcher {
    IMP runIMP = class_getMethodImplementation([self class], @selector(_run));
    if (!runIMP) return NO;
    uint32_t *p = (uint32_t *)make_sym_readable((void *)runIMP);
    void (*fn)(id, SEL, CFRunLoopRef) = NULL;
    for (int i = 0; i < 0x140; i++) {
        if (p[i] != 0xaa0003e2 || (p[i + 1] & 0xff000000) != 0xaa000000) continue;  // mov x2,x0 ; mov x0,x?
        uint32_t bl = p[i + 2]; uint32_t *blp = &p[i + 2];
        if ((bl & 0xfc000000) != 0x94000000) continue;                              // bl ?
        int32_t off = bl & 0x03ffffff; if (off & 0x02000000) off |= 0xfc000000; off <<= 2;
        uint64_t addr = (uint64_t)blp + off;
        uint32_t cbz = *((uint32_t *)make_sym_readable((void *)addr));
        if ((cbz & 0xff000000) != 0xb4000000) continue;                             // cbz x0,?
        fn = (void (*)(id, SEL, CFRunLoopRef))make_sym_callable((void *)addr);
    }
    if (fn) { fn(dispatcher, @selector(_installEventRunLoopSources:), CFRunLoopGetMain()); return YES; }
    return NO;
}

@end

@implementation XEHUDAppDelegate {
    UIViewController<XEHUDRenderer> *_hud;
    SBSAccessibilityWindowHostingController *_hostingController;
}

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // Which renderer did they pick on the Home screen?
    NSString *backend = [XEHelper stringForKey:@"RenderBackend" defaultValue:@"uikit"];
    BOOL imgui = [backend isEqualToString:@"imgui"];
    if (imgui) {
        _hud = (UIViewController<XEHUDRenderer> *)[XEImGuiHUDViewController new];
    } else {
        _hud = [XEHUDViewController new];
    }

    XEHUDWindow *w = [[XEHUDWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.xeWantsTouches = imgui;                              // ImGui needs touch input
    self.window = w;
    self.window.rootViewController = _hud;
    self.window.windowLevel = (UIWindowLevel)10000010.0;   // above status bar / alerts
    self.window.backgroundColor = [UIColor clearColor];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    // The money step: hand our render-server context to backboardd so it draws
    // on top of every app, system-wide.
    Class hostCls = objc_getClass("SBSAccessibilityWindowHostingController");
    _hostingController = [[hostCls alloc] init];
    unsigned contextId = [self.window _contextId];
    double level = self.window.windowLevel;
    [_hostingController registerWindowWithContextID:contextId atLevel:level];

    // Listen for settings reloads / stop / session reset. These blocks stick
    // around for the whole process, so capturing strongly is fine here.
    UIViewController<XEHUDRenderer> *hud = _hud;
    UIWindow *window = self.window;
    [XEHelper observeNotification:XE_NOTIFY_RELOAD block:^{
        [hud reloadSettings];
    }];
    [XEHelper observeNotification:XE_NOTIFY_RESET block:^{
        [hud resetSession];
    }];
    [XEHelper observeNotification:XE_NOTIFY_DISMISS block:^{
        [UIView animateWithDuration:0.25 animations:^{
            window.alpha = 0.0;
        } completion:^(BOOL finished) {
            exit(0);
        }];
    }];

    return YES;
}

@end
