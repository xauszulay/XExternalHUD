#import "XEHelper.h"
#import "XEPrivate.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <errno.h>

extern char **environ;

@implementation XEHelper

#pragma mark - Preferences (shared file)

+ (NSMutableDictionary *)_load {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:@(XE_PREFS_PATH)];
    return d ?: [NSMutableDictionary dictionary];
}

+ (id)_valueForKey:(NSString *)key {
    return [self _load][key];
}

+ (void)setObject:(id)value forKey:(NSString *)key {
    NSMutableDictionary *d = [self _load];
    if (value) d[key] = value; else [d removeObjectForKey:key];
    [d writeToFile:@(XE_PREFS_PATH) atomically:YES];
}

+ (void)removeObjectForKey:(NSString *)key {
    NSMutableDictionary *d = [self _load];
    [d removeObjectForKey:key];
    [d writeToFile:@(XE_PREFS_PATH) atomically:YES];
}

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def {
    id v = [self _valueForKey:key];
    return v ? [v boolValue] : def;
}

+ (double)doubleForKey:(NSString *)key defaultValue:(double)def {
    id v = [self _valueForKey:key];
    return v ? [v doubleValue] : def;
}

+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)def {
    id v = [self _valueForKey:key];
    return v ? [v integerValue] : def;
}

+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)def {
    id v = [self _valueForKey:key];
    return [v isKindOfClass:[NSString class]] ? v : def;
}

#pragma mark - Darwin notifications

+ (void)postNotification:(const char *)name {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8),
                                         NULL, NULL, YES);
}

static void _xeNotifyCallback(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_block_t block = (__bridge dispatch_block_t)observer;
    if (block) block();
}

+ (void)observeNotification:(const char *)name block:(dispatch_block_t)block {
    // Yeah, we hold onto the block for the whole process. That's on purpose.
    dispatch_block_t copied = [block copy];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge_retained void *)copied,
                                    _xeNotifyCallback,
                                    CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8),
                                    NULL, CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - HUD lifecycle

+ (pid_t)_readPid {
    NSString *s = [NSString stringWithContentsOfFile:@(XE_PID_PATH) encoding:NSUTF8StringEncoding error:nil];
    return (pid_t)s.intValue;
}

+ (const char *)_executablePath {
    return [[[NSBundle mainBundle] executablePath] fileSystemRepresentation];
}

// Flip to 1 to launch the HUD as a root persona (uid/gid 0). Leave it OFF.
// Pasted runs the HUD as plain mobile, and that's actually required — a
// root-persona process still gets its window hosted, but backboardd refuses to
// hand it the HID/touch stream (you get a visible HUD, HID fires == 0, and every
// tap falls through). Cost me a long night to figure that out.
#define XE_SPAWN_AS_ROOT 0

// Spawns "<self> <arg>". Returns the child pid, or -1 on failure. When
// waitForExit is YES the exit status is written through *exitStatus.
+ (pid_t)_spawnSelfWithArg:(const char *)arg
                  setPgrp:(BOOL)setPgrp
              waitForExit:(BOOL)waitForExit
               exitStatus:(int *)exitStatus {
    const char *path = [self _executablePath];
    if (!path) return -1;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
#if XE_SPAWN_AS_ROOT
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif
    if (setPgrp) {
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    }

    pid_t pid = -1;
    const char *args[] = { path, arg, NULL };
    int rc = posix_spawn(&pid, path, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) return -1;

    if (waitForExit) {
        int status = 0;
        while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}
        if (exitStatus) *exitStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }
    return pid;
}

+ (BOOL)isHUDRunningByPid {
    pid_t pid = [self _readPid];
    if (pid <= 0) return NO;
    return (kill(pid, 0) == 0);
}

+ (BOOL)isHUDRunning {
    // Ask a short-lived "-check" helper whether the HUD pid is alive — more robust
    // than poking kill(pid,0) ourselves across launch contexts.
    int status = 0;
    pid_t pid = [self _spawnSelfWithArg:"-check" setPgrp:NO waitForExit:YES exitStatus:&status];
    if (pid < 0) return [self isHUDRunningByPid];   // fallback
    return status != 0;   // -check returns EXIT_FAILURE(1) when running
}

+ (void)writePidFile {
    NSString *s = [NSString stringWithFormat:@"%d", getpid()];
    [s writeToFile:@(XE_PID_PATH) atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (void)startHUD {
    if ([self isHUDRunning]) return;
    [self _spawnSelfWithArg:"-hud" setPgrp:YES waitForExit:NO exitStatus:NULL];
}

+ (void)stopHUD {
    // The HUD tears itself down when it sees this notification.
    [self postNotification:XE_NOTIFY_DISMISS];
    // Belt-and-suspenders: fire an "-exit" helper after the fade in case it didn't.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self _spawnSelfWithArg:"-exit" setPgrp:NO waitForExit:YES exitStatus:NULL];
    });
}

+ (void)killHUDByPid {
    pid_t pid = [self _readPid];
    if (pid > 0) kill(pid, SIGKILL);
    unlink(XE_PID_PATH);
}

#pragma mark - Colors

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]]) return [UIColor whiteColor];
    NSString *s = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (s.length != 6) return [UIColor whiteColor];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:s] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

+ (NSString *)hexFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

@end
