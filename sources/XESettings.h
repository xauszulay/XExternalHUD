#import <UIKit/UIKit.h>

@interface XESettingsAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

// Tab 1 — essentials: start/stop, target app, credits.
@interface XEHomeViewController : UIViewController
@end

// Tab 2 — detailed settings.
@interface XESettingsViewController : UITableViewController
@end

// Tab 3 — credits / links (TrollSpeed author + xauszulay).
@interface XECreditsViewController : UIViewController
@end

// Pushed from Home — pick which app's session to time.
@interface XEAppPickerViewController : UITableViewController
@end

// Custom colour picker (swatches + RGB sliders). We can't use
// UIColorPickerViewController — its SF-symbol rendering crashes CoreImage in
// this platform-application environment.
@interface XEColorPickerViewController : UIViewController
@end
