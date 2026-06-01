#import "XEHUDWindow.h"
#import "XEPrivate.h"

@implementation XEHUDWindow

// Build the window detached from the default scene. A scene-attached window gets
// its hit-testing hijacked by the render server, so touches never reach us — going
// detached + doing our own hit test fixes that. Older iOS might not have the
// private init, so fall back just in case.
- (instancetype)initWithFrame:(CGRect)frame {
    if ([UIWindow instancesRespondToSelector:@selector(_initWithFrame:attached:)]) {
        self = [super _initWithFrame:frame attached:NO];
    } else {
        self = [super initWithFrame:frame];
    }
    if (self) {
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

// Same flags AssistiveTouch / TrollSpeed use to float a window above every app.
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }

// Do the hit-testing here in-process, not in the render server. Skip this and the
// window just won't get any touches — burned a whole night on that one.
- (BOOL)_usesWindowServerHitTesting { return NO; }

// Heads up: don't make the window/context secure. Secure context = no Metal
// drawable = ImGui renders nothing. Screen-capture hiding is per-view instead
// (xe_hideFromCapture).

// UIKit HUD just lets everything through. ImGui HUD: ask the root container what
// got hit — if it's the bare container (or nothing) we pass through to the game,
// otherwise it's the fullscreen MTKView so we grab the touch.
- (BOOL)_ignoresHitTest { return !_xeWantsTouches; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_xeWantsTouches) return nil;
    UIView *root = self.rootViewController.view;
    UIView *hit = [root hitTest:point withEvent:event];
    if (!hit || hit == root) return nil;
    return hit;
}

@end
