// Exercise Cocotron's plain-text document coding (patch 0012): TextEdit
// reads a .txt file into its text storage and writes it back on save.
#import <Foundation/Foundation.h>
#import "NSPlainTextCoding.h"
#include <stdio.h>
#include <string.h>

static int failures;
static void check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}

static NSData *bytes(const char *text, size_t length) {
    return [NSData dataWithBytes: text length: length];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSStringEncoding used = 0;

    NSString *ascii = _NSPlainTextDecode(bytes("Golden Gate\nline two\n", strlen("Golden Gate\nline two\n")), nil, &used);
    check([ascii isEqualToString: @"Golden Gate\nline two\n"], "ASCII text decodes unchanged");
    check(used == NSUTF8StringEncoding, "ASCII reports UTF-8, which saving reuses");

    NSString *utf8 = _NSPlainTextDecode(bytes("caf\xc3\xa9", 5), nil, &used);
    check([utf8 length] == 4 && [utf8 characterAtIndex: 3] == 0xE9, "UTF-8 is detected");

    NSString *bom = _NSPlainTextDecode(bytes("\xef\xbb\xbfhi", 5), nil, &used);
    check([bom isEqualToString: @"hi"] && used == NSUTF8StringEncoding, "a UTF-8 BOM is dropped");

    NSString *utf16 = _NSPlainTextDecode(bytes("\xff\xfeh\0i\0", 6), nil, &used);
    check([utf16 isEqualToString: @"hi"] && used == NSUnicodeStringEncoding, "a UTF-16 BOM selects UTF-16");

    NSString *latin = _NSPlainTextDecode(bytes("caf\xe9", 4), nil, &used);
    check([latin length] == 4 && [latin characterAtIndex: 3] == 0xE9 && used != NSUTF8StringEncoding,
          "invalid UTF-8 falls back to a Latin encoding");

    NSNumber *ascii7 = [NSNumber numberWithUnsignedInteger: NSASCIIStringEncoding];
    check(_NSPlainTextDecode(bytes("caf\xc3\xa9", 5), ascii7, &used) == nil, "a requested encoding is not overridden");
    check(_NSPlainTextDecode(nil, nil, &used) == nil, "missing data is an error");
    check([_NSPlainTextDecode([NSData data], nil, &used) isEqualToString: @""], "an empty file is an empty document");

    NSError *error = nil;
    NSString *edited = @"Golden Gate [session 1] café\n";
    NSData *saved = _NSPlainTextEncode(edited, [NSNumber numberWithUnsignedInteger: used = NSUTF8StringEncoding], &error);
    check(saved != nil && [_NSPlainTextDecode(saved, nil, &used) isEqualToString: edited], "UTF-8 save round-trips");
    check(_NSPlainTextEncode(@"plain", nil, &error) != nil, "UTF-8 is the default save encoding");

    error = nil;
    check(_NSPlainTextEncode(@"café", ascii7, &error) == nil, "lossy saves are refused");
    check([error code] == NSFileWriteInapplicableStringEncodingError &&
          [[[error userInfo] objectForKey: NSStringEncodingErrorKey] unsignedIntegerValue] == NSASCIIStringEncoding,
          "a refused save names the encoding");

    [pool release];
    if (failures)
        return 1;
    puts("plain text: detection, explicit encodings and lossless saves ok");
    return 0;
}
