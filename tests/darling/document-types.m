// Exercise Cocotron's document type resolution (patch 0011) with TextEdit's
// CFBundleDocumentTypes, which declare UTIs only through LSItemContentTypes.
#import <Foundation/Foundation.h>
#import "NSDocumentTypes.h"
#include <stdio.h>

static int failures;
static void check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}

// A small stand-in for LaunchServices conformance.
static BOOL conforms(NSString *type, NSString *parent) {
    NSDictionary *parents = @{
        @"public.plain-text": @"public.text", @"public.xml": @"public.text",
        @"public.rtf": @"public.text", @"public.text": @"public.data",
    };
    for (NSString *current = type; current != nil; current = [parents objectForKey: current])
        if ([current isEqualToString: parent])
            return YES;
    return NO;
}

static NSDictionary *type(NSString *name, NSArray *utis, NSString *role) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject: @"Document" forKey: @"NSDocumentClass"];
    if (name) [info setObject: name forKey: @"CFBundleTypeName"];
    if (utis) [info setObject: utis forKey: @"LSItemContentTypes"];
    if (role) [info setObject: role forKey: @"CFBundleTypeRole"];
    return info;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    {
        NSArray *textEdit = @[
            type(@"NSRTFPboardType", @[@"public.rtf"], @"Editor"),
            type(@"Apple HTML document", @[@"public.html"], @"Editor"),
            type(nil, @[@"org.openoffice.text"], @"Viewer"),
            type(@"NSStringPboardType", @[@"public.text"], @"Editor"),
            type(@"NSStringPboardType", @[@"public.plain-text"], @"Editor"),
            type(@"Unknown document", @[@"public.data"], @"Viewer"),
        ];

        // The pinned controller matched names only, so TextEdit's default
        // type and every file it opened resolved to no document class.
        check(_NSDocumentTypeInfo(textEdit, @"public.text", conforms) == [textEdit objectAtIndex: 3],
              "TextEdit's default type public.text has a declaration");
        check(_NSDocumentTypeInfo(textEdit, @"public.plain-text", conforms) == [textEdit objectAtIndex: 4],
              "an exact UTI wins over a conforming one");
        check(_NSDocumentTypeInfo(textEdit, @"PUBLIC.PLAIN-TEXT", NULL) == [textEdit objectAtIndex: 4],
              "UTIs compare case-insensitively");
        check(_NSDocumentTypeInfo(textEdit, @"NSRTFPboardType", NULL) == [textEdit objectAtIndex: 0],
              "names still resolve");
        check(_NSDocumentTypeInfo(textEdit, @"public.xml", conforms) == [textEdit objectAtIndex: 3],
              "a type resolves through conformance");
        check(_NSDocumentTypeInfo(textEdit, @"public.xml", NULL) == nil,
              "conformance is required for an undeclared type");
        check(_NSDocumentTypeInfo(textEdit, nil, conforms) == nil, "nil type has no declaration");

        check([_NSDocumentTypeForUTI(textEdit, @"public.plain-text", conforms) isEqualToString: @"public.plain-text"],
              "a UTI app's document type is the file's UTI");
        check([_NSDocumentTypeForUTI(textEdit, @"public.xml", conforms) isEqualToString: @"public.xml"],
              "a conforming file keeps its own UTI for the document to generalize");
        check(_NSDocumentTypeForUTI(textEdit, @"com.example.binary", conforms) == nil,
              "an unaccepted UTI has no document type");

        NSArray *legacy = @[type(@"Text", nil, @"Editor")];
        [(NSMutableDictionary *) [legacy objectAtIndex: 0] setObject: @[@"txt"] forKey: @"CFBundleTypeExtensions"];
        check(_NSDocumentTypeForUTI(legacy, @"public.plain-text", conforms) == nil,
              "name-only apps fall back to extensions");
        check([_NSDocumentDefaultType(legacy) isEqualToString: @"Text"], "name-only default type is the name");

        check([_NSDocumentDefaultType(textEdit) isEqualToString: @"public.rtf"], "default type is the first Editor UTI");
        NSArray *viewerFirst = @[[textEdit objectAtIndex: 2], [textEdit objectAtIndex: 4]];
        check([_NSDocumentDefaultType(viewerFirst) isEqualToString: @"public.plain-text"], "Viewer types are skipped");
        check(_NSDocumentDefaultType(@[]) == nil, "no declarations, no default type");
    }
    [pool release];
    if (failures)
        return 1;
    puts("document types: UTI declarations, conformance and defaults ok");
    return 0;
}
