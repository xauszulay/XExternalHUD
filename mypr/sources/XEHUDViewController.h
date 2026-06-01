#import <UIKit/UIKit.h>

// Common interface for both HUD render backends (UIKit / ImGui) so the app
// delegate can hold either one.
@protocol XEHUDRenderer <NSObject>
- (void)reloadSettings;
- (void)resetSession;
@end

// Renders the HUD content (the readout pill) and refreshes it on a timer.
// Reloads its layout/appearance whenever the settings app posts a reload.
@interface XEHUDViewController : UIViewController <XEHUDRenderer>
- (void)reloadSettings;
- (void)resetSession;
@end
