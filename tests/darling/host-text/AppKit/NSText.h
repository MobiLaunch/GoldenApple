// Host stand-in for Cocotron's NSText.h: only the text enums that
// NSParagraphStyle and NSTextTab use, without NSView and drawing.
#import <Foundation/Foundation.h>

#ifndef APPKIT_EXPORT
#define APPKIT_EXPORT extern
#endif

typedef enum {
    NSLeftTextAlignment,
    NSRightTextAlignment,
    NSCenterTextAlignment,
    NSJustifiedTextAlignment,
    NSNaturalTextAlignment
} NSTextAlignment;

typedef enum {
    NSWritingDirectionNatural = -1,
    NSWritingDirectionLeftToRight,
    NSWritingDirectionRightToLeft,
} NSWritingDirection;
