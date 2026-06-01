#import <UIKit/UIKit.h>

// A borderless, secure, system-level window that backboardd hosts above every
// other app. It never intercepts touches (full passthrough) so it cannot
// interfere with the game running underneath.
@interface XEHUDWindow : UIWindow
// NO (default) = full passthrough (UIKit HUD). YES = normal hit testing so the
// ImGui content can receive touches; areas its container rejects pass through.
@property (nonatomic) BOOL xeWantsTouches;
@end
