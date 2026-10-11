#import <Foundation/Foundation.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSLayoutConstraint.h>
#include <stdio.h>

NSString *const NSNibOwner = @"NSOwner";
static int failures, parentDecodes, releasedViews, releasedObjects;
static void check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}
@implementation NSResponder
- (id)initWithCoder:(NSCoder *)coder { parentDecodes++; return [super init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
@end
@interface NSView : NSObject @end
@implementation NSView
- (void)dealloc { releasedViews++; [super dealloc]; }
@end
@interface OwnedObject : NSObject @end
@implementation OwnedObject
- (void)dealloc { releasedObjects++; [super dealloc]; }
@end
@interface ProgramController : NSViewController {
@public int loads, callbacks, stage; BOOL failNext, failAfterSettingView;
}
@end
@implementation ProgramController
- (void)loadView {
    loads++;
    check([self view] == nil, "recursive access during loading does not reload");
    stage = 1;
    if (failNext) { failNext = NO; [NSException raise:@"TestFailure" format:@"retry"]; }
    [self setView:[[[NSView alloc] init] autorelease]];
    check(callbacks == 0 || loads > 1, "programmatic callback waits until loadView returns");
    if (failAfterSettingView) { failAfterSettingView = NO; [NSException raise:@"TestFailure" format:@"partial"]; }
    stage = 2;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    callbacks++;
    check([self view] == [self viewIfLoaded], "callback can read view without recursion");
    check([self isViewLoaded], "callback sees loaded view");
}
@end
@interface FakeBundle : NSBundle { @public int stage, callbacks; } @end
@interface NibController : NSViewController @end
@implementation NibController
- (void)viewDidLoad {
    [super viewDidLoad];
    FakeBundle *bundle = (FakeBundle *)[self nibBundle];
    check(bundle->stage == 1, "nib callback occurs immediately at outlet assignment");
    bundle->callbacks++;
}
@end
@implementation FakeBundle
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type { return @"fixture.nib"; }
- (BOOL)loadNibFile:(NSString *)path externalNameTable:(NSDictionary *)table withZone:(NSZone *)zone {
    stage = 1;
    [[table objectForKey:NSNibOwner] setView:[[[NSView alloc] init] autorelease]];
    check(callbacks == 1, "nib callback precedes completion of unarchiving");
    stage = 2;
    return YES;
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    ProgramController *c = [[ProgramController alloc] initWithNibName:nil bundle:nil];
    check(![c isViewLoaded] && [c viewIfLoaded] == nil && c->loads == 0,
          "loaded-state queries do not create a view");
    NSView *first = [c view];
    check(first != nil && c->loads == 1 && c->callbacks == 1 && c->stage == 2,
          "first view access loads and initializes once");
    [c loadViewIfNeeded];
    check([c view] == first && c->loads == 1 && c->callbacks == 1, "repeated access is idempotent");
    [c setView:first];
    check(c->callbacks == 1, "assigning same view does not repeat callback");
    [c setView:nil];
    check(![c isViewLoaded] && [c viewIfLoaded] == nil, "clearing view resets loaded state");
    [c loadViewIfNeeded];
    check(c->loads == 2 && c->callbacks == 2, "cleared controller can load again");
    [c release];

    c = [[ProgramController alloc] initWithNibName:nil bundle:nil];
    c->failNext = YES;
    @try { [c loadViewIfNeeded]; check(NO, "failed load propagates exception"); }
    @catch (NSException *e) { check(![c isViewLoaded], "failed load stays unloaded"); }
    [c loadViewIfNeeded];
    check(c->loads == 2 && c->callbacks == 1, "load retries after exception");
    [c release];

    c = [[ProgramController alloc] initWithNibName:nil bundle:nil];
    c->failAfterSettingView = YES;
    @try { [c loadViewIfNeeded]; } @catch (NSException *e) {}
    check(c->callbacks == 0, "partial failed load did not deliver callback");
    [c loadViewIfNeeded];
    check(c->loads == 1 && c->callbacks == 1, "existing view receives deferred callback on retry");
    [c release];

    FakeBundle *bundle = [FakeBundle new];
    NibController *nib = [[NibController alloc] initWithNibName:@"fixture" bundle:bundle];
    [nib loadViewIfNeeded]; [nib loadViewIfNeeded];
    check([nib isViewLoaded] && bundle->callbacks == 1 && bundle->stage == 2,
          "nib loading notifies once at the correct point");
    [nib release]; [bundle release];

    NSViewController *manual = [[NSViewController alloc] initWithNibName:nil bundle:nil];
    NSView *owned = [NSView new];
    OwnedObject *represented = [OwnedObject new];
    [manual setView:owned]; [manual setRepresentedObject:represented];
    [owned release]; [represented release];
    int beforeViews = releasedViews, beforeObjects = releasedObjects;
    [manual release];
    check(releasedViews == beforeViews + 1 && releasedObjects == beforeObjects + 1,
          "controller releases its owned view and represented object");

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:@"fixture" forKey:@"NSNibName"];
    [archiver finishEncoding]; [archiver release];
    NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    NSViewController *decoded = [[NSViewController alloc] initWithCoder:decoder];
    check(parentDecodes == 1 && [[decoded nibName] isEqual:@"fixture"], "decoding initializes superclass and metadata");
    [decoded release]; [decoder release];
    check(NSViewNoIntrinsicMetric == -1.0 && NSViewNoInstrinsicMetric == -1.0,
          "both layout sentinel exports are numeric minus one");
    [pool drain];
    if (!failures) puts("PASS: patched Darling controller runtime and layout sentinel");
    return failures ? 1 : 0;
}
