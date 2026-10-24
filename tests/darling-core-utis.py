#!/usr/bin/env python3
"""Compile Darling's patched core type table and probe it (patch 0010).

Pinned Darling has no declarations for core types such as public.plain-text,
so document-based apps like TextEdit cannot open or save text files. Run on
a tree prepared by tools/darling/build.py apply_patches.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
services = source / 'src/frameworks/CoreServices/src/LaunchServices'
table = services / 'UTCoreTypesTable.c'
assert table.is_file(), 'patch 0010 is not applied: UTCoreTypesTable.c is missing'
assert 'UTCoreTypesTable.c' in (services / 'CMakeLists.txt').read_text(), 'table is not built'
uttype = (services / 'UTType.m').read_text()
for fallback in ('coreIdentifiersForTag(inTagClass', 'coreTagsWithClass(inUTI', 'conformsTo(inUTI, inConformsToUTI, 0)',
                 '_UTCoreTypeIsDeclared('):
    assert fallback in uttype, f'UTType.m does not use the core table: {fallback}'

# Every parent must itself be declared, or transitive conformance stops
# early; an extension may name only one type.
text = table.read_text()
entries = re.findall(r'\{ "([^"]+)", (NONE|LIST\(([^)]*)\)), (NONE|LIST\(([^)]*)\)) \}', text)
declared = {entry[0] for entry in entries}
assert len(entries) == len(declared) > 20, 'core type table did not parse'
extensions = {}
for identifier, _, parents, _, exts in entries:
    for parent in re.findall(r'"([^"]+)"', parents):
        assert parent in declared, f'{identifier} conforms to undeclared {parent}'
    for extension in re.findall(r'"([^"]+)"', exts):
        assert extension not in extensions, f'.{extension} maps to {extensions[extension]} and {identifier}'
        extensions[extension] = identifier

with tempfile.TemporaryDirectory() as directory:
    probe = Path(directory) / 'core-utis'
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Werror', '-I' + str(services), str(table),
                    str(ROOT / 'tests/darling/core-utis.c'), '-o', str(probe)], check=True)
    result = subprocess.run([str(probe)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    print(result.stdout.strip())
