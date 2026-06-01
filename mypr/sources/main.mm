#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import <string.h>
#import "XEPrivate.h"
#import "XEHelper.h"
#import "TSEventFetcher.h"

// Global HID touch monitor that feeds ImGui. Grabbed from Pasted.
typedef struct __IOHIDEvent   *IOHIDEventRef;
typedef struct __IOHIDService *IOHIDServiceRef;

extern "C" void *BKSHIDEventRegisterEventCallback(void (*)(void *, void *, IOHIDServiceRef, IOHIDEventRef));
extern "C" void  XEInjectImGuiTouch(CGPoint point, NSInteger phase, UIWindow *window);  // in XEImGuiHUD.mm
extern "C" void  XEHIDDidFire(void);                                                    // debug counter

@interface UIApplication (XEHID)
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

// AX hand/path info — used to pull a stable pointer id for synthetic UITouches.
@interface AXEventPathInfoRepresentation : NSObject
@property (assign, nonatomic) unsigned char pathIdentity;
@end

@interface AXEventHandInfoRepresentation : NSObject
- (NSArray<AXEventPathInfoRepresentation *> *)paths;
@end

// Decodes a raw HID event into touch phase + location.
@interface AXEventRepresentation : NSObject
@property (nonatomic, readonly) BOOL isTouchDown;
@property (nonatomic, readonly) BOOL isMove;
@property (nonatomic, readonly) BOOL isChordChange;
@property (nonatomic, readonly) BOOL isLift;
@property (nonatomic, readonly) BOOL isInRange;
@property (nonatomic, readonly) BOOL isInRangeLift;
@property (nonatomic, readonly) BOOL isCancel;
+ (instancetype)representationWithHIDEvent:(IOHIDEventRef)event hidStreamIdentifier:(NSString *)identifier;
- (AXEventHandInfoRepresentation *)handInfo;
- (CGPoint)location;
@end

static UIWindow *XEHudWindow(UIApplication *app) {
    for (UIWindow *w in app.windows.reverseObjectEnumerator)
        if ([NSStringFromClass([w class]) isEqualToString:@"XEHUDWindow"]) return w;
    return app.windows.lastObject ?: app.keyWindow;
}

static void XEHIDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    XEHIDDidFire();
    // Push the event into our UIKit pipeline so the hosted window gets real
    // touchesBegan/Moved/Ended (dispatcher was set up back in XEHUDApplication).
    UIApplication *app0 = [UIApplication sharedApplication];
    if ([app0 respondsToSelector:@selector(_enqueueHIDEvent:)]) {
        [app0 _enqueueHIDEvent:event];
    }

    static Class axCls = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
        axCls = objc_getClass("AXEventRepresentation");
    });
    if (!axCls) return;

    AXEventRepresentation *rep = [axCls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    if (!rep) return;

    UITouchPhase phase = UITouchPhaseEnded;
    if ([rep isTouchDown])                          phase = UITouchPhaseBegan;
    else if ([rep isMove] || [rep isChordChange])   phase = UITouchPhaseMoved;
    else if ([rep isCancel])                        phase = UITouchPhaseCancelled;
    else if ([rep isLift] || [rep isInRange] || [rep isInRangeLift]) phase = UITouchPhaseEnded;

    CGPoint global = [rep location];
    NSInteger pointerId = [[[[rep handInfo] paths] firstObject] pathIdentity];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *w = XEHudWindow(app);
        if (!w) return;

        // Cheap fallback: shove the raw point straight into ImGui. Only matters
        // when there's no real UITouch in flight (see XEImGuiHUD drawInMTKView).
        XEInjectImGuiTouch(global, phase, w);

        // The real deal: build an actual UITouch and send it through sendEvent: so
        // the view hierarchy gets proper touchesBegan/Moved/Ended at the right
        // coords. This is the KIF trick from Pasted — raw injection on its own
        // hands you garbage positions in a backboard-hosted window.
        UIView *keyView = [w.rootViewController.view hitTest:global withEvent:nil];
        if (!keyView) keyView = w.rootViewController.view;
        // A few HID streams hand back a 0 path id — just use 1 so we don't drop
        // the touch on the floor.
        NSInteger pid = MIN(MAX(pointerId, 1), 98);
        [TSEventFetcher receiveAXEventID:pid
                      atGlobalCoordinate:global
                          withTouchPhase:phase
                                inWindow:w
                                  onView:keyView];
    });
}

// XExternalHUD entry point.
//   <no args>  -> settings app (UIApplicationMain)
//   -hud       -> floating overlay process (manual "run as plugin" bring-up)
//   -exit      -> kill the running HUD (used as a fallback)
//   -check     -> exit code reports whether the HUD is running
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc <= 1) {
            return UIApplicationMain(argc, argv, nil, @"XESettingsAppDelegate");
        }

        if (strcmp(argv[1], "-exit") == 0) {
            [XEHelper killHUDByPid];
            return EXIT_SUCCESS;
        }

        if (strcmp(argv[1], "-check") == 0) {
            // EXIT_FAILURE (1) means "running", EXIT_SUCCESS (0) means "not running".
            return [XEHelper isHUDRunningByPid] ? EXIT_FAILURE : EXIT_SUCCESS;
        }

        if (strcmp(argv[1], "-hud") == 0) {
            [XEHelper writePidFile];

            // Spin up UIKit by hand (no UIApplicationMain) so backboardd will host
            // our window over everything — same dance AssistiveTouch/TrollSpeed do.
            [UIScreen initialize];
            CFRunLoopGetCurrent();

            GSInitialize();
            BKSDisplayServicesStart();
            UIApplicationInitialize();

            UIApplicationInstantiateSingleton(objc_getClass("XEHUDApplication"));
            id delegate = [[objc_getClass("XEHUDAppDelegate") alloc] init];
            [UIApplication.sharedApplication setDelegate:delegate];
            [UIApplication.sharedApplication _accessibilityInit];

            [NSRunLoop currentRunLoop];

            // Always register the global HID monitor (like Pasted). It's a no-op
            // for the UIKit backend since XEInjectImGuiTouch bails when there's no
            // ImGui host. Used to gate this on a settings read — that just gave us
            // one more way to silently kill all touch input, so: always on.
            {
                extern int gHIDRegistered, gHIDRegRetNonNull;
                void *ret = BKSHIDEventRegisterEventCallback(XEHIDEventCallback);
                gHIDRegistered = 1;
                gHIDRegRetNonNull = (ret != NULL) ? 1 : 0;
            }

            extern int gGSRan, gEUID, gOSMajor, gHIDReg2;
            gEUID = (int)geteuid();
            gOSMajor = (int)[[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
            if (@available(iOS 15.0, *)) {
                GSEventInitialize(0);
                GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
                gGSRan = 1;
            }

            [UIApplication.sharedApplication __completeAndRunAsPlugin];

            // A few iOS builds wipe the HID callback while finishing plugin
            // startup, so register it a second time to be safe.
            {
                void *ret2 = BKSHIDEventRegisterEventCallback(XEHIDEventCallback);
                gHIDReg2 = (ret2 != NULL) ? 1 : 0;
            }

            // When SpringBoard relaunches (respring) just kill ourselves — the
            // launcher brings the HUD back, so this keeps it alive across resprings.
            static int bootToken;
            pid_t pid = getpid();
            notify_register_dispatch("SBSpringBoardDidLaunchNotification", &bootToken,
                                     dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                kill(pid, SIGKILL);
            });

            CFRunLoopRun();
            return EXIT_SUCCESS;
        }

        return EXIT_SUCCESS;
    }
}
