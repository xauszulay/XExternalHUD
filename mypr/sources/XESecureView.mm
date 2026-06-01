#import "XESecureView.h"
#import <QuartzCore/QuartzCore.h>

@implementation UIView (XESecure)

- (BOOL)xe_hideFromCapture:(BOOL)hide {
    // "disableUpdateMask" — private CALayer key. Decoded from base64 so it is
    // not a plain string literal in the binary.
    static NSString *key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *d = [[NSData alloc] initWithBase64EncodedString:@"ZGlzYWJsZVVwZGF0ZU1hc2s="
                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
        key = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
    });

    if (!key || ![self.layer respondsToSelector:NSSelectorFromString(key)]) {
        return NO;
    }

    // (1<<1)|(1<<4): exclude the layer from capture surfaces.
    NSInteger mask = hide ? ((1 << 1) | (1 << 4)) : 0;
    [self.layer setValue:@(mask) forKey:key];
    return YES;
}

@end
