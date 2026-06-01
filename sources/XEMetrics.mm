#import "XEMetrics.h"
#import "XEPrivate.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <ifaddrs.h>
#import <net/if.h>

// libproc headers aren't in the iOS SDK, so just declare what we need by hand.
extern "C" int proc_listallpids(void *buffer, int buffersize);
extern "C" int proc_name(int pid, void *buffer, uint32_t buffersize);
extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define XE_PROC_PIDPATHINFO_MAXSIZE (4 * 1024)

// Is the target game running? We match on the full process path against the app's
// ".app" folder (e.g. "Standoff2.app"), which holds up even when the display name
// isn't the binary name. If that misses, fall back to a proc_name keyword (it's
// capped at ~15 chars, so match both directions). This is what fixed the "session
// works for some apps but not others" mess — old code keyed off the display name,
// which almost never matches a game's executable.
static BOOL XETargetRunning(NSString *appDir, NSString *keyword) {
    const char *dir = appDir.length ? appDir.UTF8String : NULL;
    const char *kw  = keyword.length ? keyword.UTF8String : NULL;
    if (!dir && !kw) return NO;

    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return NO;
    pid_t *pids = (pid_t *)calloc((size_t)count, sizeof(pid_t));
    if (!pids) return NO;
    count = proc_listallpids(pids, (int)(count * sizeof(pid_t)));

    BOOL found = NO;
    char path[XE_PROC_PIDPATHINFO_MAXSIZE];
    char name[256];
    for (int i = 0; i < count && !found; i++) {
        if (pids[i] <= 0) continue;
        if (dir) {
            path[0] = '\0';
            if (proc_pidpath(pids[i], path, sizeof(path)) > 0 && strstr(path, dir)) { found = YES; break; }
        }
        if (kw) {
            name[0] = '\0';
            if (proc_name(pids[i], name, sizeof(name)) > 0 && name[0] &&
                (strstr(name, kw) || strstr(kw, name))) { found = YES; break; }
        }
    }
    free(pids);
    return found;
}

@implementation XEMetrics {
    NSTimeInterval _sessionStart;

    // Foreground-app session state (auto mode)
    NSString *_currentBundleId;
    NSString *_currentAppName;
    NSTimeInterval _appSessionStart;
    BOOL _onHomeScreen;

    // Attached-target mode
    NSString *_targetBundleId;     // nil => auto mode
    NSString *_targetName;
    NSString *_targetProcKeyword;  // executable-name keyword for process detection
    NSString *_targetAppDir;       // "<Name>.app" — matched against the process path
    NSTimeInterval _accumulated;   // seconds the target has been active
    NSTimeInterval _resumeTime;
    BOOL _targetActive;

    // CPU sampling state
    processor_info_array_t _prevCPUInfo;
    mach_msg_type_number_t _prevCPUInfoCount;
    double _cpuUsage;

    // Network sampling state
    uint64_t _prevRx, _prevTx;
    NSTimeInterval _prevNetTime;
    double _rxRate, _txRate;

    NSDateFormatter *_clockFmt;

    // FPS — straight off a CADisplayLink, i.e. the screen/compositor refresh rate.
    CADisplayLink *_fpsLink;
    double _fps;
    CFTimeInterval _fpsLast;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sessionStart = CACurrentMediaTime();
        _clockFmt = [NSDateFormatter new];
        _clockFmt.dateFormat = @"HH:mm:ss";
        _prevCPUInfo = NULL;
        _prevCPUInfoCount = 0;
        _prevNetTime = 0;
        [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];

        // 0 = let it run at the display's real refresh, so the number tracks the
        // actual on-screen cadence and dips when things hitch.
        _fpsLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_fpsTick:)];
        _fpsLink.preferredFramesPerSecond = 0;
        [_fpsLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)_fpsTick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    if (_fpsLast > 0) {
        CFTimeInterval dt = now - _fpsLast;
        if (dt > 0) {
            double inst = 1.0 / dt;
            _fps = (_fps <= 0) ? inst : (_fps * 0.9 + inst * 0.1);   // smoothed
        }
    }
    _fpsLast = now;
}

- (double)currentFPS { return _fps; }
- (NSString *)fpsString { return [NSString stringWithFormat:@"%.0f", _fps]; }

- (void)resetSession {
    NSTimeInterval now = CACurrentMediaTime();
    _sessionStart = now;
    _appSessionStart = now;
    _accumulated = 0;
    _resumeTime = now;
}

- (void)setTargetBundleId:(NSString *)bundleId name:(NSString *)name {
    if ([bundleId isEqualToString:_targetBundleId]) return;   // unchanged
    _targetBundleId = bundleId.length ? bundleId : nil;
    _targetName = name;
    _targetAppDir = nil;
    _targetProcKeyword = nil;

    if (_targetBundleId) {
        // Grab the app's real ".app" folder + binary name so we can find its
        // process by path. Display name and binary name are usually different for
        // games, so this is what makes detection actually work across the board.
        Class proxyCls = objc_getClass("LSApplicationProxy");
        LSApplicationProxy *proxy = proxyCls ? [proxyCls applicationProxyForIdentifier:_targetBundleId] : nil;
        NSURL *url = nil;
        @try { url = [proxy bundleURL]; } @catch (__unused id e) {}
        NSString *appDir = [url lastPathComponent];                 // "<Name>.app"
        if (appDir.length) _targetAppDir = appDir;

        NSString *exe = nil;
        @try { exe = [proxy bundleExecutable]; } @catch (__unused id e) {}
        if (!exe.length && appDir.length)                            // "<Name>.app" -> "<Name>"
            exe = [appDir stringByDeletingPathExtension];
        NSString *kw = exe.length ? exe : (name.length ? name : [[bundleId componentsSeparatedByString:@"."] lastObject]);
        _targetProcKeyword = [kw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }

    _accumulated = 0;
    _targetActive = NO;
    _resumeTime = CACurrentMediaTime();
}

- (void)sample {
    [self _sampleFrontmostApp];
    [self _sampleCPU];
    [self _sampleNet];
}

#pragma mark - Foreground app detection

- (NSString *)_nameForBundleId:(NSString *)bid {
    Class proxyCls = objc_getClass("LSApplicationProxy");
    if (proxyCls && bid) {
        LSApplicationProxy *proxy = [proxyCls applicationProxyForIdentifier:bid];
        NSString *name = [proxy localizedName];
        if (name.length) return name;
    }
    // Fallback: last path component of the bundle id.
    return [[bid componentsSeparatedByString:@"."] lastObject] ?: bid;
}

- (void)_sampleFrontmostApp {
    NSString *bid = SBSCopyFrontmostApplicationDisplayIdentifier();
    NSTimeInterval now = CACurrentMediaTime();

    // Target mode: tick the clock while the game's process is alive (Pasted-style
    // attach). Works from our process; SBSCopyFrontmostApplicationDisplayIdentifier
    // tends to come back nil here, which is why the timer used to be stuck at
    // 00:00:00. Frontmost-bundle check is just a backup.
    if (_targetBundleId) {
        BOOL active = XETargetRunning(_targetAppDir, _targetProcKeyword);
        if (!active && bid.length) active = [bid isEqualToString:_targetBundleId];
        if (active && !_targetActive) {
            _targetActive = YES;
            _resumeTime = now;
        } else if (!active && _targetActive) {
            _targetActive = NO;
            _accumulated += now - _resumeTime;
        }
        return;
    }

    // --- Auto mode: track whatever app is frontmost ---
    BOOL isHome = (bid.length == 0) ||
                  [bid isEqualToString:@"com.apple.springboard"] ||
                  [bid isEqualToString:@"com.xexternal.hud"];

    if (isHome) {
        if (!_onHomeScreen) {
            _onHomeScreen = YES;
            _currentBundleId = nil;
            _currentAppName = nil;
        }
        return;
    }

    if (![bid isEqualToString:_currentBundleId]) {
        // New app in front — restart the session clock.
        _currentBundleId = bid;
        _currentAppName = [self _nameForBundleId:bid];
        _appSessionStart = now;
        _onHomeScreen = NO;
    }
}

#pragma mark - Session / clock

static NSString *XEFormatDuration(NSTimeInterval t) {
    if (t < 0) t = 0;
    int total = (int)t;
    return [NSString stringWithFormat:@"%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60];
}

- (NSString *)sessionString {
    if (_targetBundleId) {
        NSTimeInterval t = _accumulated + (_targetActive ? CACurrentMediaTime() - _resumeTime : 0);
        return XEFormatDuration(t);
    }
    if (!_currentBundleId) return @"--:--:--";   // on Home Screen
    return XEFormatDuration(CACurrentMediaTime() - _appSessionStart);
}

- (NSString *)appNameString {
    if (_targetBundleId) {
        return _targetActive ? _targetName : [NSString stringWithFormat:@"%@ (pause)", _targetName];
    }
    return _currentAppName ?: @"Home";
}

- (NSString *)clockString {
    return [_clockFmt stringFromDate:[NSDate date]];
}

#pragma mark - Battery

- (NSString *)batteryString {
    float level = [[UIDevice currentDevice] batteryLevel];
    if (level < 0) return @"--%";
    return [NSString stringWithFormat:@"%d%%", (int)roundf(level * 100)];
}

#pragma mark - RAM

- (NSString *)ramString {
    vm_size_t pageSize = 0;
    host_page_size(mach_host_self(), &pageSize);

    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &count) != KERN_SUCCESS) {
        return @"--";
    }

    double used = (double)(vmStats.active_count + vmStats.wire_count +
                           vmStats.inactive_count + vmStats.compressor_page_count) * pageSize;
    double total = (double)[[NSProcessInfo processInfo] physicalMemory];
    double usedGB = used / (1024.0 * 1024.0 * 1024.0);
    double totalGB = total / (1024.0 * 1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1f/%.1f GB", usedGB, totalGB];
}

#pragma mark - CPU

- (void)_sampleCPU {
    natural_t numCPU = 0;
    processor_info_array_t cpuInfo;
    mach_msg_type_number_t cpuInfoCount;

    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                           &numCPU, &cpuInfo, &cpuInfoCount);
    if (kr != KERN_SUCCESS) return;

    double totalTicks = 0, busyTicks = 0;
    for (natural_t i = 0; i < numCPU; i++) {
        int base = CPU_STATE_MAX * i;
        long user   = cpuInfo[base + CPU_STATE_USER];
        long system = cpuInfo[base + CPU_STATE_SYSTEM];
        long nice   = cpuInfo[base + CPU_STATE_NICE];
        long idle   = cpuInfo[base + CPU_STATE_IDLE];

        long pUser = 0, pSystem = 0, pNice = 0, pIdle = 0;
        if (_prevCPUInfo) {
            pUser   = _prevCPUInfo[base + CPU_STATE_USER];
            pSystem = _prevCPUInfo[base + CPU_STATE_SYSTEM];
            pNice   = _prevCPUInfo[base + CPU_STATE_NICE];
            pIdle   = _prevCPUInfo[base + CPU_STATE_IDLE];
        }
        double busy = (user - pUser) + (system - pSystem) + (nice - pNice);
        double tot  = busy + (idle - pIdle);
        busyTicks += busy;
        totalTicks += tot;
    }
    if (totalTicks > 0) _cpuUsage = (busyTicks / totalTicks) * 100.0;

    if (_prevCPUInfo) {
        vm_deallocate(mach_task_self(), (vm_address_t)_prevCPUInfo,
                      sizeof(integer_t) * _prevCPUInfoCount);
    }
    _prevCPUInfo = cpuInfo;
    _prevCPUInfoCount = cpuInfoCount;
}

- (NSString *)cpuString {
    return [NSString stringWithFormat:@"%d%%", (int)roundf(_cpuUsage)];
}

#pragma mark - Network

- (void)_sampleNet {
    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0) return;

    uint64_t rx = 0, tx = 0;
    for (struct ifaddrs *p = addrs; p; p = p->ifa_next) {
        if (p->ifa_addr == NULL || p->ifa_addr->sa_family != AF_LINK) continue;
        NSString *name = @(p->ifa_name);
        // Wi-Fi (en*) and cellular (pdp_ip*) only — skip loopback/bridge.
        if (![name hasPrefix:@"en"] && ![name hasPrefix:@"pdp_ip"]) continue;
        struct if_data *d = (struct if_data *)p->ifa_data;
        if (!d) continue;
        rx += d->ifi_ibytes;
        tx += d->ifi_obytes;
    }
    freeifaddrs(addrs);

    NSTimeInterval now = CACurrentMediaTime();
    if (_prevNetTime > 0) {
        double dt = now - _prevNetTime;
        if (dt > 0) {
            _rxRate = (rx >= _prevRx) ? (rx - _prevRx) / dt : 0;
            _txRate = (tx >= _prevTx) ? (tx - _prevTx) / dt : 0;
        }
    }
    _prevRx = rx;
    _prevTx = tx;
    _prevNetTime = now;
}

static NSString *XEFormatRate(double bytesPerSec) {
    if (bytesPerSec >= 1024.0 * 1024.0)
        return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSec / (1024.0 * 1024.0)];
    if (bytesPerSec >= 1024.0)
        return [NSString stringWithFormat:@"%.0f KB/s", bytesPerSec / 1024.0];
    return [NSString stringWithFormat:@"%.0f B/s", bytesPerSec];
}

- (NSString *)netString {
    return [NSString stringWithFormat:@"↓%@ ↑%@",
            XEFormatRate(_rxRate), XEFormatRate(_txRate)];
}

- (void)dealloc {
    [_fpsLink invalidate];
    if (_prevCPUInfo) {
        vm_deallocate(mach_task_self(), (vm_address_t)_prevCPUInfo,
                      sizeof(integer_t) * _prevCPUInfoCount);
    }
}

@end
