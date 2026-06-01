#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Anchor positions for the HUD on screen.
typedef NS_ENUM(NSInteger, XEHUDPosition) {
    XEHUDPositionTopLeft = 0,
    XEHUDPositionTopCenter,
    XEHUDPositionTopRight,
    XEHUDPositionMidLeft,
    XEHUDPositionCenter,
    XEHUDPositionMidRight,
    XEHUDPositionBottomLeft,
    XEHUDPositionBottomCenter,
    XEHUDPositionBottomRight,
};

// Thin wrapper over CFPreferences + Darwin notifications + process control.
// Both the settings app and the spawned HUD process talk through this.
@interface XEHelper : NSObject

// --- Preferences (shared across processes) ---
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def;
+ (double)doubleForKey:(NSString *)key defaultValue:(double)def;
+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)def;
+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)def;
+ (void)setObject:(id)value forKey:(NSString *)key;
+ (void)removeObjectForKey:(NSString *)key;

// --- Darwin notifications ---
+ (void)postNotification:(const char *)name;
+ (void)observeNotification:(const char *)name block:(dispatch_block_t)block;

// --- HUD process lifecycle ---
+ (BOOL)isHUDRunning;        // spawns "<self> -check" as root and reads exit code
+ (BOOL)isHUDRunningByPid;   // local pidfile check (used inside "-check")
+ (void)startHUD;            // spawns "<self> -hud" as root persona
+ (void)stopHUD;             // graceful dismiss + "-exit" fallback
+ (void)writePidFile;        // called from inside the HUD process
+ (void)killHUDByPid;        // called from "<self> -exit"

// --- Color helpers ---
+ (UIColor *)colorFromHex:(NSString *)hex;
+ (NSString *)hexFromColor:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
