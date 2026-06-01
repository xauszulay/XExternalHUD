#import <UIKit/UIKit.h>

// UIApplication subclass for the spawned HUD process. Kept minimal — exists so
// the principal class is explicit and easy to extend later.
@interface XEHUDApplication : UIApplication
@end

@interface XEHUDAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
