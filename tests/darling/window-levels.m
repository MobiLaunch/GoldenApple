#ifdef NATIVE_APPKIT
#import <Cocoa/Cocoa.h>
#else
#include <CoreGraphics/CGWindowLevel.h>
#include "AppKitLevels.h"
#endif
#include <stdio.h>

int main(void) {
    const struct { CGWindowLevelKey key; int native; int appkit; } cases[] = {
        {kCGNormalWindowLevelKey, 0, NSNormalWindowLevel},
        {kCGFloatingWindowLevelKey, 3, NSFloatingWindowLevel},
        {kCGTornOffMenuWindowLevelKey, 3, NSTornOffMenuWindowLevel},
        {kCGMainMenuWindowLevelKey, 24, NSMainMenuWindowLevel},
        {kCGStatusWindowLevelKey, 25, NSStatusWindowLevel},
        {kCGModalPanelWindowLevelKey, 8, NSModalPanelWindowLevel},
        {kCGPopUpMenuWindowLevelKey, 101, NSPopUpMenuWindowLevel},
        {kCGScreenSaverWindowLevelKey, 1000, NSScreenSaverWindowLevel},
    };
    int failures = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int quartz = CGWindowLevelForKey(cases[i].key);
        if (quartz != cases[i].native || cases[i].appkit != cases[i].native) {
            fprintf(stderr, "key=%d quartz=%d appkit=%d expected=%d\n",
                    cases[i].key, quartz, cases[i].appkit, cases[i].native);
            failures++;
        }
    }
    printf("Window level ABI: 16 checks, %d failures\n", failures);
    return failures ? 1 : 0;
}
