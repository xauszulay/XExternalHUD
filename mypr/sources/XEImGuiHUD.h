#import <UIKit/UIKit.h>
#import "XEHUDViewController.h"   // for XEHUDRenderer protocol

// ImGui + Metal render backend for the HUD. Hosts an MTKView and draws the
// same metrics through Dear ImGui. Selected when RenderBackend == "imgui".
@interface XEImGuiHUDViewController : UIViewController <XEHUDRenderer>
- (void)reloadSettings;
- (void)resetSession;
@end
