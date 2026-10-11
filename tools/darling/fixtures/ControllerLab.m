// Native Cocoa GUI fixture. Build once on macOS, then run the same Mach-O
// bundle on both macOS and Darling. No conditional Darling-specific app code.
#import <Cocoa/Cocoa.h>

@interface LabController : NSViewController {
    NSTextView *_editor;
    NSTextField *_status;
}
@end
@implementation LabController
- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 380)];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self setView:root];
    [root release];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSView *root = [self view];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 72, 560, 288)];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    _editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 560, 288)];
    [_editor setString:@"Darling Controller Lab\n\nEdit this text, resize the window, then click Save.\n"];
    [_editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setDocumentView:_editor];
    [root addSubview:scroll];
    [_editor release]; [scroll release];
    NSButton *save = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 90, 32)];
    [save setTitle:@"Save"]; [save setTarget:self]; [save setAction:@selector(saveDocument:)];
    [root addSubview:save]; [save release];
    _status = [[NSTextField alloc] initWithFrame:NSMakeRect(122, 24, 458, 24)];
    [_status setEditable:NO]; [_status setBezeled:NO]; [_status setDrawsBackground:NO];
    [_status setStringValue:@"View initialized through viewDidLoad."];
    [_status setAutoresizingMask:NSViewWidthSizable];
    [root addSubview:_status]; [_status release];
}
- (void)saveDocument:(id)sender {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Darling-ControllerLab.txt"];
    NSError *error = nil;
    BOOL ok = [[_editor string] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    [_status setStringValue:ok ? [@"Saved: " stringByAppendingString:path] : [error localizedDescription]];
}
@end

@interface LabDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    LabController *_controller;
}
@end
@implementation LabDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _controller = [[LabController alloc] initWithNibName:nil bundle:nil];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 600, 380)
        styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
        backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO];
    [_window setTitle:@"Darling Controller Lab"];
    [_window setContentView:[_controller view]];
    [_window center]; [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)dealloc { [_window release]; [_controller release]; [super dealloc]; }
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSApplication *app = [NSApplication sharedApplication];
    LabDelegate *delegate = [LabDelegate new];
    [app setDelegate:delegate]; [app run];
    [app setDelegate:nil]; [delegate release]; [pool drain];
    return 0;
}
