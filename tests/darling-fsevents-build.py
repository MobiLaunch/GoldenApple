#!/usr/bin/env python3
"""Check pinned FSEvents CMake and fanotify ABI with Darwin-target compilation.

The source checkout is read only. A static probe replaces the daemon's source
and link graph; this tests header discovery and ABI layout, not daemon behavior.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'third_party/darling'
LOCK = json.loads((VENDOR / 'source.lock.json').read_text())
CMAKE = os.environ.get('CMAKE', 'cmake')
CC = os.environ.get('CC', 'clang')
FSEVENTS = 'src/frameworks/CoreServices/src/FSEvents'
FIELDS = {
    'metadata_size': 'sizeof(struct fanotify_event_metadata)',
    'metadata_alignment': '_Alignof(struct fanotify_event_metadata)',
    'mask_offset': '__builtin_offsetof(struct fanotify_event_metadata, mask)',
    'fd_offset': '__builtin_offsetof(struct fanotify_event_metadata, fd)',
    'pid_offset': '__builtin_offsetof(struct fanotify_event_metadata, pid)',
    'info_size': 'sizeof(struct fanotify_event_info_header)',
    'fid_size': 'sizeof(struct fanotify_event_info_fid)',
    'fsid_offset': '__builtin_offsetof(struct fanotify_event_info_fid, fsid)',
    'handle_offset': '__builtin_offsetof(struct fanotify_event_info_fid, handle)',
    'response_size': 'sizeof(struct fanotify_response)',
}


def run(args, *, cwd=None, succeeds=True):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if succeeds and result.returncode:
        raise RuntimeError(result.stdout)
    return result


def main():
    source = Path(sys.argv[1]).resolve()

    def blob(path):
        return run(['git', '-C', str(source), 'show', LOCK['darling_commit'] + ':' + path]).stdout

    with tempfile.TemporaryDirectory(prefix='darling-fsevents-') as directory:
        temp = Path(directory)
        runtime = temp / FSEVENTS
        (runtime / 'linux').mkdir(parents=True)
        cmake_source = blob(FSEVENTS + '/CMakeLists.txt')
        (runtime / 'CMakeLists.txt').write_text(cmake_source)
        (runtime / 'linux/fanotify.h').write_text(blob(FSEVENTS + '/linux/fanotify.h'))
        (temp / 'create_symlink.cmake').write_text(blob('cmake/create_symlink.cmake'))
        # The host compiler finds native Linux asm headers, providing the ABI
        # reference against which the Darwin-target object is checked.
        native = '#include <stdio.h>\n#include "linux/fanotify.h"\nint main(void) {\n'
        native += ''.join(f'printf("{name}=%zu\\n", (size_t)({expr}));\n'
                          for name, expr in FIELDS.items())
        (temp / 'native.c').write_text(native + 'return 0;\n}\n')
        run([CC, '-I', str(runtime), str(temp / 'native.c'), '-o', str(temp / 'native')])
        values = dict(line.split('=') for line in run([str(temp / 'native')]).stdout.splitlines())
        probe = '#include "linux/fanotify.h"\n'
        probe += ''.join(f'_Static_assert(({expr}) == {values[name]}, "{name} ABI mismatch");\n'
                         for name, expr in FIELDS.items())
        (temp / 'probe.m').write_text(probe + 'int probe(void) { return FAN_REPORT_FID; }\n')
        (temp / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.13)
project(FSEventsHeaderProbe C)
set(CMAKE_FIND_ROOT_PATH "${UAPI_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
include("${CMAKE_SOURCE_DIR}/create_symlink.cmake")
function(generate_sdk_subframework)
endfunction()
function(add_framework)
endfunction()
function(add_darling_executable name)
    add_library(${name} STATIC "${CMAKE_SOURCE_DIR}/probe.m")
    target_compile_options(${name} PRIVATE -target x86_64-apple-darwin20 -nostdinc
        -idirafter "${UAPI_ROOT}/usr/include")
    target_include_directories(${name} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
endfunction()
add_subdirectory(src/frameworks/CoreServices/src/FSEvents)
''')
        # Model the real distro layouts with actual Linux UAPI headers. Keep
        # host libc out of both the synthetic SDK and the guest include path.
        host_asm = next((p for p in (Path('/usr/include/x86_64-linux-gnu/asm'),
                                     Path('/usr/include/asm')) if (p / 'types.h').is_file()), None)
        if host_asm is None:
            raise RuntimeError('Install Linux userspace kernel headers to run this check')
        for layout in ('multiarch', 'flat', 'missing'):
            include = temp / layout / 'usr/include'
            include.mkdir(parents=True)
            for name in ('linux', 'asm-generic'):
                shutil.copytree(Path('/usr/include') / name, include / name)
            if layout != 'missing':
                destination = include / ('x86_64-linux-gnu/asm' if layout == 'multiarch' else 'asm')
                shutil.copytree(host_asm, destination)

        def configure(label, layout, succeeds=True):
            output = temp / ('build-' + label)
            result = run([CMAKE, '-S', str(temp), '-B', str(output), '-G', 'Unix Makefiles',
                          '-DUAPI_ROOT=' + str(temp / layout)], succeeds=succeeds)
            return output, result

        output, _ = configure('baseline', 'multiarch')
        failure = run([CMAKE, '--build', str(output), '--target', 'fseventsd'], succeeds=False)
        if failure.returncode == 0 or "'asm/types.h' file not found" not in failure.stdout:
            raise AssertionError('pristine multiarch build must reproduce missing asm/types.h\n'
                                 + failure.stdout)
        patches = [p for p in LOCK['patches'] if p['path'].endswith('0006-fsevents-linux-uapi.patch')]
        if len(patches) != 1:
            raise RuntimeError('locked FSEvents patch not found')
        patch = VENDOR / patches[0]['path']
        if hashlib.sha256(patch.read_bytes()).hexdigest() != patches[0]['sha256']:
            raise RuntimeError('FSEvents patch checksum mismatch')
        run(['git', 'apply', str(patch)], cwd=temp)
        for layout in ('multiarch', 'flat'):
            output, _ = configure(layout, layout)
            # Reconfiguration must preserve the private symlink correctly.
            configure(layout, layout)
            run([CMAKE, '--build', str(output), '--target', 'fseventsd'])
            private = output / FSEVENTS / 'linux-uapi'
            assert {p.name for p in private.iterdir()} == {'asm'}, 'only asm headers may be exposed'
            assert (private / 'asm').resolve().is_relative_to(temp / layout)
            print(f'PASS: {layout} headers; Darwin target agrees with all {len(FIELDS)} host ABI checks')
        _, missing = configure('missing', 'missing', succeeds=False)
        if missing.returncode == 0 or 'fseventsd needs Linux userspace asm headers' not in missing.stdout:
            raise AssertionError('missing kernel headers must fail at configuration\n' + missing.stdout)
    print('PASS: original failure reproduced, private header discovery, ABI and missing-header rejection')


if __name__ == '__main__':
    main()
