#import <PIP/PIP.h>
#include <math.h>
#include <stdio.h>

static int failures, checks;
static void check(BOOL condition, const char *name) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", name); }
}
static BOOL raises(void (^block)(void)) {
    @try { block(); } @catch (NSException *exception) { return YES; }
    return NO;
}

@interface LabPIP : PIPViewController
@property(nonatomic) int layouts, disappearances;
@end
@implementation LabPIP
- (void)viewDidLayout { [super viewDidLayout]; self.layouts++; }
- (void)viewDidDisappear { [super viewDidDisappear]; self.disappearances++; }
@end

@interface LabDelegate : NSObject <PIPViewControllerDelegate, NSWindowDelegate>
@property(nonatomic) int willClose, didClose, plays, pauses;
@property(nonatomic, weak) NSViewController *videoController;
@end
@implementation LabDelegate
- (void)pipWillClose:(PIPViewController *)pip {
    self.willClose++;
    [pip dismissViewController:self.videoController]; // Must not recursively close.
}
- (void)pipDidClose:(PIPViewController *)pip { self.didClose++; }
- (void)pipActionPlay:(PIPViewController *)pip { self.plays++; }
- (void)pipActionPause:(PIPViewController *)pip { self.pauses++; }
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        LabPIP *pip = [LabPIP new];
        NSViewController *video = [NSViewController new];
        NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
        NSRect original = NSMakeRect(12, 20, 400, 200);
        video.view = [[NSView alloc] initWithFrame:original];
        [video.view setAutoresizingMask:NSViewMinXMargin];
        [parent addSubview:video.view];
        LabDelegate *delegate = [LabDelegate new];
        delegate.videoController = video;
        pip.delegate = delegate;
        pip.name = @"PIPLab";
        pip.aspectRatio = NSMakeSize(2, 1);

        __block PIPMutablePlaybackState *captured;
        [pip updatePlaybackStateUsingBlock:^(PIPMutablePlaybackState *state) {
            state.contentDuration = 90;
            state.contentType = 1;
            [state setPlaybackRate:1.5 elapsedTime:30 timeControlStatus:2];
            captured = state;
        }];
        check(pip.playing, "valid playing state is applied");
        [captured setPlaybackRate:0 elapsedTime:30 timeControlStatus:0];
        check(pip.playing, "retaining and changing update argument cannot mutate committed state");
        PIPPlaybackState *snapshot = [[pip valueForKey:@"playbackState"] copy];
        check(snapshot.contentDuration == 90 && snapshot.elapsedTime == 30 && snapshot.playbackRate == 1.5,
              "state copy preserves the complete playback snapshot");
        check(raises(^{ [pip updatePlaybackStateUsingBlock:^(PIPMutablePlaybackState *state) {
            [state setPlaybackRate:0 elapsedTime:0 timeControlStatus:0];
            state.contentDuration = NAN;
        }]; }), "invalid state update raises");
        check(pip.playing, "failed update does not partially commit");
        check(raises(^{ pip.aspectRatio = NSMakeSize(0, 1); }), "invalid aspect ratio is refused");

        [pip presentViewControllerAsPictureInPicture:video];
        NSWindow *floating = pip.view.window;
        check(floating && floating.isVisible && floating.level == NSFloatingWindowLevel,
              "presentation creates a visible floating window");
        check(video.view.superview == pip.view && video.view.window == floating,
              "the actual supplied view moves into the floating window");
        check(pip.layouts > 0, "subclass layout hook can call super");
        // IINA installs its own window delegate from viewDidLayout.
        floating.delegate = delegate;
        [pip presentViewControllerAsPictureInPicture:video];
        check(pip.view.window == floating, "repeated presentation is idempotent");
        NSViewController *other = [NSViewController new];
        check(raises(^{ [pip dismissViewController:other]; }), "wrong controller cannot dismiss the view");
        NSButton *playButton;
        for (NSView *view in pip.view.subviews) if ([view isKindOfClass:[NSButton class]]) playButton = (NSButton *)view;
        [playButton performClick:nil];
        check(delegate.pauses == 1 && delegate.plays == 0 && pip.playing,
              "pause control delegates intent without claiming playback changed");
        [pip updatePlaybackStateUsingBlock:^(PIPMutablePlaybackState *state) {
            [state setPlaybackRate:0 elapsedTime:30 timeControlStatus:0];
        }];
        [playButton performClick:nil];
        check(delegate.plays == 1 && !pip.playing, "play control delegates intent");

        [pip dismissViewController:video];
        check(delegate.willClose == 1 && delegate.didClose == 1,
              "close callbacks occur once even with reentrant dismissal and a replaced window delegate");
        check(video.view.superview == parent && NSEqualRects(video.view.frame, original)
              && video.view.autoresizingMask == NSViewMinXMargin,
              "dismissal restores parent, frame and autoresizing settings");
        check(!floating.isVisible && pip.disappearances == 1,
              "dismissal hides window and delivers subclass disappearance hook");
        if (floating.isVisible || pip.disappearances != 1)
            fprintf(stderr, "Close diagnostic: visible=%d disappearances=%d\n", floating.isVisible, pip.disappearances);
        [pip dismissViewController:video];
        check(delegate.didClose == 1, "repeat dismissal does not repeat callbacks");
        [pip presentViewControllerAsPictureInPicture:video];
        [pip.view.window close];
        check(delegate.didClose == 2 && video.view.superview == parent,
              "window close follows the same restoration path as dismissal");

        pip.delegate = nil;
        @autoreleasepool {
            LabDelegate *temporary = [LabDelegate new];
            pip.delegate = temporary;
            check(pip.delegate == temporary, "delegate can be read while alive");
        }
        check(pip.delegate == nil, "delegate ownership is zeroing weak");
        __weak LabPIP *weakPip;
        @autoreleasepool {
            LabPIP *temporary = [LabPIP new];
            weakPip = temporary;
            [temporary presentViewControllerAsPictureInPicture:video];
        }
        check(weakPip == nil && video.view.superview == parent,
              "controller teardown restores the view without an ownership cycle");

        NSDictionary *result = @{@"kind": @"pip-behavior", @"passed": @(failures == 0),
                                  @"checks": @(checks), @"failures": @(failures)};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        if (argc > 1) {
            NSError *error;
            BOOL saved = [json writeToFile:[NSString stringWithUTF8String:argv[1]] options:NSDataWritingAtomic error:&error];
            if (!saved) { fprintf(stderr, "Cannot save test result: %s\n", error.description.UTF8String); failures++; }
        }
        printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    }
    return failures ? 1 : 0;
}
