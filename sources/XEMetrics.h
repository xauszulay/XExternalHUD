#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Gathers all live readouts shown in the HUD. Holds sampling state
// (previous CPU ticks / network byte counters) between updates.
@interface XEMetrics : NSObject

// Resets the session stopwatch to zero.
- (void)resetSession;

// Attach the session timer to a specific app. Pass nil bundleId for "auto"
// (track whatever app is frontmost). In attached mode the timer only advances
// while the chosen app is in the foreground.
- (void)setTargetBundleId:(NSString *)bundleId name:(NSString *)name;

// Must be called once per refresh tick before reading the strings below.
- (void)sample;

// Formatted strings, ready to drop into the HUD label.
- (NSString *)sessionString;      // HH:MM:SS the current foreground app has been active
- (NSString *)appNameString;      // name of the foreground app (or "Home")
- (NSString *)clockString;        // local wall-clock time
- (NSString *)batteryString;      // e.g. "87%"
- (NSString *)ramString;          // e.g. "2.1/4.0 GB"
- (NSString *)cpuString;          // e.g. "23%"
- (NSString *)netString;          // e.g. "↓1.2 MB/s ↑0.1 MB/s"
- (NSString *)fpsString;          // screen/compositor refresh, e.g. "60"
- (double)currentFPS;             // raw value for colour coding

@end

NS_ASSUME_NONNULL_END
