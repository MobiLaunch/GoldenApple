// Exercise Cocotron's paragraph style tab stops (patch 0013) the way
// TextEdit prepares plain text: mutableCopy, clear the tab stops, set an
// interval, then copy. The pinned copy kept an immutable tab-stop array,
// so setTabStops: raised "attempting to mutate an immutable object".
#import <Foundation/Foundation.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSMutableParagraphStyle.h>
#import <AppKit/NSTextTab.h>
#include <stdio.h>

static int failures;
static void check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSParagraphStyle *base = [NSParagraphStyle defaultParagraphStyle];
    NSUInteger baseStops = [[base tabStops] count];

    NSMutableParagraphStyle *plain = [[base mutableCopy] autorelease];
    @try {
        [plain setTabStops: [NSArray array]];
        [plain setDefaultTabInterval: 28];
    } @catch (NSException *exception) {
        check(NO, [[exception reason] UTF8String]);
    }
    check([[plain tabStops] count] == 0, "a mutable copy's tab stops can be cleared");
    check([plain defaultTabInterval] == 28, "the tab interval is kept");
    check([[base tabStops] count] == baseStops, "editing a copy leaves the default style alone");

    NSParagraphStyle *frozen = [[plain copy] autorelease];
    NSTextTab *tab = [[[NSTextTab alloc] initWithType: NSLeftTabStopType location: 36] autorelease];
    NSTextTab *early = [[[NSTextTab alloc] initWithType: NSLeftTabStopType location: 12] autorelease];
    @try {
        [plain addTabStop: tab];
        [plain addTabStop: early];
        NSMutableParagraphStyle *again = [[frozen mutableCopy] autorelease];
        [again setTabStops: [NSArray arrayWithObject: tab]];
        check([[again tabStops] count] == 1, "a copy of a copy is editable too");
    } @catch (NSException *exception) {
        check(NO, [[exception reason] UTF8String]);
    }
    check([[plain tabStops] count] == 2 && [[[plain tabStops] objectAtIndex: 0] location] == 12,
          "added tab stops stay sorted");
    check([[frozen tabStops] count] == 0, "an immutable copy does not share the editable array");

    [pool release];
    if (failures)
        return 1;
    puts("paragraph style: editable tab stops in every copy ok");
    return 0;
}
