#!/usr/bin/env python3
"""Compile pinned objc4's configuration guard with its real CMake flags.

Only Darling's target/link graph is replaced by static probe targets. This
checks build configuration consistency, not execution of the complete runtime.
The supplied source checkout is read only; all builds use temporary copies.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'third_party/darling'
LOCK = json.loads((VENDOR / 'source.lock.json').read_text())
CMAKE = os.environ.get('CMAKE', 'cmake')


def run(args, *, cwd=None, succeeds=True):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if succeeds and result.returncode:
        raise RuntimeError(result.stdout)
    return result


def blob(repo, revision, path):
    return run(['git', '-C', str(repo), 'show', revision + ':' + path]).stdout


def main():
    source = Path(sys.argv[1]).resolve()
    objc = source / 'src/external/objc4'
    cmake_source = blob(objc, LOCK['objc4_commit'], 'runtime/CMakeLists.txt')
    config = blob(objc, LOCK['objc4_commit'], 'runtime/objc-config.h')
    implementation = blob(objc, LOCK['objc4_commit'], 'runtime/objc-runtime.mm')
    guard = re.search(r'^#if DEBUG != OBJC_IS_DEBUG_BUILD\n#error[^\n]+\n(?:^//[^\n]*\n)*#endif',
                      implementation, re.MULTILINE)
    if not guard:
        raise RuntimeError('pinned runtime debug consistency guard not found')
    header = blob(source, LOCK['darling_commit'], 'basic-headers/TargetConditionals.h')
    with tempfile.TemporaryDirectory(prefix='darling-build-modes-') as directory:
        temp = Path(directory)
        runtime = temp / 'runtime'
        runtime.mkdir()
        (runtime / 'CMakeLists.txt').write_text(cmake_source)
        (runtime / 'objc-config.h').write_text(config)
        (runtime / 'TargetConditionals.h').write_text(header)
        (temp / 'probe.cpp').write_text(
            '#include "objc-config.h"\n' + guard.group() + '\n'
            'static_assert(DEBUG == EXPECTED_DEBUG, "unexpected debug mode");\n'
            'int probe_cpp() { return DEBUG; }\n')
        (temp / 'probe.c').write_text(
            '#include "objc-config.h"\n' + guard.group() + '\n'
            '#if DEBUG != EXPECTED_DEBUG\n#error unexpected debug mode\n#endif\n'
            'int probe_c(void) { return DEBUG; }\n')
        (temp / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.13)
project(ObjcBuildModeProbe C CXX ASM)
add_compile_definitions(EXPECTED_DEBUG=${EXPECTED_DEBUG} TARGET_CPU_X86_64=1)
function(add_circular name)
    add_library(${name} STATIC "${CMAKE_SOURCE_DIR}/probe.cpp" "${CMAKE_SOURCE_DIR}/probe.c")
endfunction()
function(add_darling_library name)
    add_library(${name} STATIC "${CMAKE_SOURCE_DIR}/probe.cpp")
endfunction()
function(InstallSymlink)
endfunction()
add_subdirectory(runtime)
''')

        def build(label, mode, debug, succeeds=True):
            output = temp / ('build-' + label)
            run([CMAKE, '-S', str(temp), '-B', str(output), '-G', 'Unix Makefiles',
                 '-DCMAKE_BUILD_TYPE=' + mode, '-DEXPECTED_DEBUG=' + str(debug)])
            return run([CMAKE, '--build', str(output), '--target', 'objc', '-j', '2'],
                       succeeds=succeeds)

        # Prove that this harness detects the compiler failure seen in full CI.
        failure = build('baseline', 'RelWithDebInfo', 0, succeeds=False)
        if failure.returncode == 0 or 'mismatch in debug-ness macros' not in failure.stdout:
            raise AssertionError('pristine RelWithDebInfo must reproduce the runtime guard failure\n'
                                 + failure.stdout)
        for patch in LOCK['patches']:
            if patch.get('repository') != 'objc4':
                continue
            path = VENDOR / patch['path']
            if hashlib.sha256(path.read_bytes()).hexdigest() != patch['sha256']:
                raise RuntimeError('objc4 patch checksum mismatch')
            run(['git', 'apply', str(path)], cwd=temp)
        for mode, debug in [('Debug', 1), ('Release', 0), ('RelWithDebInfo', 0),
                            ('MinSizeRel', 0), ('', 1)]:
            build(mode or 'unspecified', mode, debug)
            print('PASS: patched C and C++ guard in ' + (mode or 'unspecified build mode'))
    print('PASS: pristine failure reproduced; patched standard build modes agree with objc-config.h')


if __name__ == '__main__':
    main()
