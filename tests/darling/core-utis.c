// Probe Darling's core type table (patch 0010) with the questions TextEdit
// asks while opening and saving a plain-text document.
#include <stdio.h>
#include <string.h>
#include "UTCoreTypesTable.h"

static int failures;

static void expect_conforms(const char *type, const char *parent, int expected) {
    if (_UTCoreTypeConformsTo(type, parent) != expected) {
        fprintf(stderr, "conforms(%s, %s) != %d\n", type, parent, expected);
        failures++;
    }
}

static void expect_extension(const char *extension, const char *expected) {
    const char *type = _UTCoreTypeForExtension(extension);
    if ((type == NULL) != (expected == NULL) || (type && strcmp(type, expected))) {
        fprintf(stderr, "type(%s) = %s, expected %s\n", extension, type ? type : "NULL", expected ? expected : "NULL");
        failures++;
    }
}

int main(void) {
    expect_conforms("public.plain-text", "public.plain-text", 1);
    expect_conforms("PUBLIC.Plain-Text", "public.plain-text", 1);
    expect_conforms("public.plain-text", "public.text", 1);
    expect_conforms("public.plain-text", "public.data", 1);
    expect_conforms("public.plain-text", "public.item", 1);
    expect_conforms("public.rtf", "public.text", 1);
    expect_conforms("com.apple.rtfd", "public.directory", 1);
    expect_conforms("public.html", "public.text", 1);
    expect_conforms("com.microsoft.word.wordml", "public.text", 1);
    expect_conforms("public.text", "public.plain-text", 0);
    expect_conforms("public.rtf", "public.plain-text", 0);
    expect_conforms("public.rtf", "public.html", 0);
    expect_conforms("org.example.unknown", "public.data", 0);
    expect_conforms(NULL, "public.data", 0);
    expect_conforms("public.text", NULL, 0);

    expect_extension("txt", "public.plain-text");
    expect_extension("TXT", "public.plain-text");
    expect_extension("rtf", "public.rtf");
    expect_extension("rtfd", "com.apple.rtfd");
    expect_extension("htm", "public.html");
    expect_extension("unknownext", NULL);
    expect_extension(NULL, NULL);

    const char *const *extensions = _UTCoreTypeExtensions("public.plain-text");
    if (!extensions || strcmp(extensions[0], "txt")) {
        fprintf(stderr, "public.plain-text must prefer .txt\n");
        failures++;
    }
    if (_UTCoreTypeExtensions("public.text") || _UTCoreTypeExtensions("org.example.unknown")) {
        fprintf(stderr, "abstract and unknown types have no extension\n");
        failures++;
    }
    if (!_UTCoreTypeIsDeclared("public.text") || _UTCoreTypeIsDeclared("org.example.unknown")) {
        fprintf(stderr, "declaration lookup is wrong\n");
        failures++;
    }
    if (failures)
        return 1;
    puts("core UTI table: conformance, extensions and declarations ok");
    return 0;
}
