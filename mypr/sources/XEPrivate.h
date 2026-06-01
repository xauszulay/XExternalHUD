// Private API declarations used by XExternalHUD.
// Mirrors the symbols TrollSpeed (MIT) relies on to host a window above all apps.
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <spawn.h>

#ifdef __cplusplus
extern "C" {
#endif

// GraphicsServices / BackBoardServices / UIKitCore private entry points used to
// bring up a UIApplication WITHOUT UIApplicationMain (the "run as plugin" path).
void GSInitialize(void);
void GSEventInitialize(Boolean registerPurple);
void GSEventPushRunLoopMode(CFStringRef mode);
void BKSDisplayServicesStart(void);
void UIApplicationInitialize(void);
void UIApplicationInstantiateSingleton(id aClass);

// Persona override bits — only used if you flip the HUD back to a root spawn
// (off by default; see XE_SPAWN_AS_ROOT in XEHelper).
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);

// Bundle identifier of the app currently in the foreground (nil on the Home
// Screen). Used to detect which game is running and time its session.
NSString *SBSCopyFrontmostApplicationDisplayIdentifier(void);

#ifdef __cplusplus
}
#endif

// Device orientation updates for the hosted window (it does not auto-rotate).
@interface FBSOrientationUpdate : NSObject
- (long long)orientation;
- (double)duration;
@end

@interface FBSOrientationObserver : NSObject
- (long long)activeInterfaceOrientation;
- (void)setHandler:(id)handler;
- (void)invalidate;
@end

// Resolve a bundle id to a human-readable app name + list installed apps.
@interface LSApplicationProxy : NSObject
+ (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSString *)applicationIdentifier;
- (NSString *)applicationType;   // @"User" / @"System"
- (NSURL *)bundleURL;            // …/<Name>.app  — used to match a running process by path
- (NSString *)bundleExecutable;  // CFBundleExecutable (actual binary name)
@end

@interface LSApplicationWorkspace : NSObject
+ (LSApplicationWorkspace *)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allApplications;
@end

// Private UIApplication hooks for the manual launch sequence + event delivery.
@interface UIApplication (XEPrivate)
- (void)_accessibilityInit;
- (void)__completeAndRunAsPlugin;
- (void)terminateWithSuccess;
- (void)_run;
- (void)suspend;   // background the settings app so the HUD overlay owns input
@end

// UIKit event plumbing — needed so the hosted HUD window actually receives touches.
@interface UIEventDispatcher : NSObject
- (void)_installEventRunLoopSources:(CFRunLoopRef)runLoop;
@end

@interface UIEventFetcher : NSObject
- (void)setEventFetcherSink:(id)sink;
@end

// Private UIWindow hooks: the render-server context id we hand to backboardd,
// and the private initializer Pasted uses so the hosted window is created
// detached from the default scene (required for it to sit in the input path).
@interface UIWindow (XEPrivate)
- (unsigned)_contextId;
- (instancetype)_initWithFrame:(CGRect)frame attached:(BOOL)attached;
@end

// The controller that registers our window with backboardd so it floats above
// every application (same mechanism AssistiveTouch uses). Obtained at runtime
// via objc_getClass — never linked directly.
@interface SBSAccessibilityWindowHostingController : NSObject
- (void)registerWindowWithContextID:(unsigned)contextID atLevel:(double)level;
@end

// Darwin notification names shared between the settings app and the HUD process.
#define XE_NOTIFY_RELOAD  "com.xexternal.hud/reload"
#define XE_NOTIFY_DISMISS "com.xexternal.hud/dismiss"
#define XE_NOTIFY_RESET   "com.xexternal.hud/reset"

// One shared prefs file for both the settings app and the HUD process. Just plist
// it to a known path instead of fighting CFPreferences across processes.
#define XE_PREFS_PATH     "/var/mobile/Library/Preferences/com.xexternal.hud.plist"

// Pid file written by the running HUD process so the settings app can stop it.
#define XE_PID_PATH       "/var/mobile/Library/Caches/com.xexternal.hud.pid"
