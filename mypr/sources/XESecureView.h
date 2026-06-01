#import <UIKit/UIKit.h>

// Hide a view's layer from screen recordings / mirroring / screenshots while
// keeping it visible on the physical screen. Uses the private CALayer
// "disableUpdateMask" property (same trick TrollSpeed forks use).
@interface UIView (XESecure)
- (BOOL)xe_hideFromCapture:(BOOL)hide;
@end
