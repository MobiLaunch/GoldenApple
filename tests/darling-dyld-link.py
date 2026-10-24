#!/usr/bin/env python3
"""Reproduce dyld's relative-table link failure with pinned source and ld64.

This compiles the actual x86_64 register-name function, library CMake flags and
root target override. A tiny loader substitutes for full dyld. No guest binary
is executed and no source checkout is modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'third_party/darling'
LOCK = json.loads((VENDOR / 'source.lock.json').read_text())
CMAKE = os.environ.get('CMAKE', 'cmake')
CXX = os.environ.get('CXX', 'clang++')


def run(args, *, cwd=None, succeeds=True, timeout=120):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    if succeeds and result.returncode:
        raise RuntimeError(result.stdout)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--linker', type=Path, help='Reuse a locally built pinned ld64')
    args = parser.parse_args()
    source = args.source.resolve()

    def root_blob(path):
        return run(['git', '-C', str(source), 'show', LOCK['darling_commit'] + ':' + path]).stdout

    revisions = {}
    for name in ('libunwind', 'dyld', 'cctools-port'):
        revision = run(['git', '-C', str(source), 'rev-parse',
                        LOCK['darling_commit'] + ':src/external/' + name]).stdout.strip()
        repo = source / 'src/external' / name
        if run(['git', '-C', str(repo), 'rev-parse', 'HEAD']).stdout.strip() != revision:
            raise RuntimeError('unexpected pinned ' + name + ' revision')
        revisions[name] = revision

    def blob(name, path):
        return run(['git', '-C', str(source / 'src/external' / name), 'show',
                    revisions[name] + ':' + path]).stdout

    registers = blob('libunwind', 'libunwind/src/Registers.hpp')
    function = re.search(r'inline const char \*Registers_x86_64::getRegisterName\(int regNum\) '
                         r'\{.*?\n\}', registers, re.DOTALL)
    if function is None:
        raise RuntimeError('pinned register-name function missing')
    header = blob('libunwind', 'libunwind/include/libunwind.h')
    enums = '\n'.join(block for block in re.findall(r'enum \{.*?\n\};', header, re.DOTALL)
                      if 'UNW_REG_IP' in block or 'UNW_X86_64_RAX' in block)
    probe = enums + '\nnamespace libunwind {\n'
    probe += 'struct Registers_x86_64 { static const char *getRegisterName(int); };\n'
    probe += function.group() + '\n}\n'
    probe += ('extern "C" const char *_dyld_start(int reg) {\n'
              'return libunwind::Registers_x86_64::getRegisterName(reg);\n}\n')
    # Retain the pinned loader's chained-fixup and entry/link mode flags.
    dyld_cmake = blob('dyld', 'CMakeLists.txt')
    raw_flags = re.search(r'set_property\(TARGET system_loader APPEND_STRING PROPERTY LINK_FLAGS '
                          r'"([^"\n]*-fixup_chains[^"\n]*)"\)', dyld_cmake)
    if raw_flags is None:
        raise RuntimeError('pinned dyld chained-fixup linker flags missing')
    link_flags = []
    for word in shlex.split(raw_flags.group(1)):
        if word.startswith('-Wl,') and not word.startswith('-Wl,-exported_symbols_list,'):
            link_flags.extend(word[4:].split(','))

    with tempfile.TemporaryDirectory(prefix='darling-dyld-link-') as directory:
        temp = Path(directory)
        (temp / 'src/external/libunwind').mkdir(parents=True)
        (temp / 'src/CMakeLists.txt').write_text(root_blob('src/CMakeLists.txt'))
        (temp / 'src/external/libunwind/CMakeLists.txt').write_text(blob('libunwind', 'CMakeLists.txt'))
        # Stub only build graph helpers; preserve the actual library flag logic.
        (temp / 'darling_static_lib.cmake').write_text('')
        (temp / 'probe.cpp').write_text(probe)

        def harness():
            root_cmake = (temp / 'src/CMakeLists.txt').read_text()
            start = root_cmake.index('add_subdirectory(external/libunwind)')
            end = root_cmake.index('add_subdirectory(external/libmalloc)', start)
            (temp / 'src/probe.cmake').write_text(root_cmake[start:end])
            (temp / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.13)
project(DyldUnwindProbe C CXX ASM)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -target x86_64-apple-darwin20")
function(add_circular name)
    add_library(${name} OBJECT "${CMAKE_SOURCE_DIR}/probe.cpp")
endfunction()
function(add_darling_static_library name)
    add_library(${name} OBJECT "${CMAKE_SOURCE_DIR}/probe.cpp")
endfunction()
function(make_fat)
endfunction()
add_library(control OBJECT "${CMAKE_SOURCE_DIR}/probe.cpp")
add_subdirectory(src)
''')
            # The source-root entry point is the extracted actual call site.
            (temp / 'src/CMakeLists-probe.txt').write_text((temp / 'src/probe.cmake').read_text())

        linker = args.linker.resolve() if args.linker else None
        if linker is None:
            linker_source = temp / 'linker'
            linker_source.mkdir()
            upstream = source / 'src/external/cctools-port/cctools/ld64/src'
            (linker_source / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.13)
project(PinnedLd64 C CXX)
set(APPLE_TARGET_TRIPLET_PRIMARY x86_64-apple-darwin20)
set(TARGET_x86_64 ON)
add_subdirectory("''' + upstream.as_posix() + '''" ld64)
''')
            output = temp / 'linker-build'
            run([CMAKE, '-S', str(linker_source), '-B', str(output), '-DCMAKE_BUILD_TYPE=Release'])
            run([CMAKE, '--build', str(output), '-j', '2'], timeout=600)
            linker = output / 'ld64/x86_64-apple-darwin20-ld'

        def compile_probe(label):
            # Use the extracted root block without configuring the full root.
            harness()
            full_root = (temp / 'src/CMakeLists.txt').read_text()
            (temp / 'src/CMakeLists.txt').write_text((temp / 'src/CMakeLists-probe.txt').read_text())
            output = temp / ('build-' + label)
            try:
                run([CMAKE, '-S', str(temp), '-B', str(output), '-DCMAKE_BUILD_TYPE=RelWithDebInfo'])
                run([CMAKE, '--build', str(output), '--target', 'unwind_static', 'control', '-j', '2'])
            finally:
                (temp / 'src/CMakeLists.txt').write_text(full_root)
            commands = json.loads((output / 'compile_commands.json').read_text())
            for name in ('unwind_static', 'control'):
                entry = next(c for c in commands if 'CMakeFiles/' + name + '.dir/' in c['command'])
                command = shlex.split(entry['command'])
                index = command.index('-o')
                command[index + 1] = str(output / (name + '.s'))
                command[command.index('-c')] = '-S'
                run(command, cwd=entry['directory'])
            obj = next((output / 'src/external/libunwind').rglob('probe.cpp.o'))
            linked = output / 'probe.dyld'
            result = run([str(linker), '-arch', 'x86_64', '-macosx_version_min', '11.0',
                          '-sdk_version', '11.0', *link_flags, str(obj), '-o', str(linked)], succeeds=False)
            return output, result, linked

        baseline, failure, _ = compile_probe('baseline')
        if failure.returncode == 0 or 'chained binds not implemented yet' not in failure.stdout:
            raise AssertionError('original pinned lookup must reproduce chained-bind failure\n' + failure.stdout)
        assert 'l_reltable.' in (baseline / 'unwind_static.s').read_text()
        patch = next(p for p in LOCK['patches'] if p['path'].endswith('0007-dyld-static-unwind-tables.patch'))
        path = VENDOR / patch['path']
        if hashlib.sha256(path.read_bytes()).hexdigest() != patch['sha256']:
            raise RuntimeError('dyld unwind patch checksum mismatch')
        run(['git', 'apply', str(path)], cwd=temp)
        patched, success, linked = compile_probe('patched')
        if success.returncode:
            raise RuntimeError(success.stdout)
        assert 'l_reltable.' not in (patched / 'unwind_static.s').read_text()
        assert 'l_reltable.' in (patched / 'control.s').read_text(), 'other targets must retain normal codegen'
        data = linked.read_bytes()
        magic, cpu, _, filetype, count = struct.unpack_from('<5I', data)
        assert (magic, cpu, filetype) == (0xFEEDFACF, 0x01000007, 7), 'expected x86_64 Mach-O loader'
        offset, commands = 32, []
        for _ in range(count):
            command, size = struct.unpack_from('<2I', data, offset)
            commands.append(command)
            offset += size
        assert 0x80000034 in commands, 'chained fixups must remain enabled in the linked loader'
        # Check compiler-workaround semantics on the host; never run a guest loader.
        native = temp / 'native.cpp'
        native.write_text(probe + '#include <stdio.h>\nint main() {\n'
                          'for (int n = -64; n <= 128; ++n) puts(_dyld_start(n));\n}\n')
        outputs = []
        for label, flags in [('baseline', []), ('patched', ['-fno-jump-tables'])]:
            binary = temp / ('native-' + label)
            run([CXX, '-O2', *flags, str(native), '-o', str(binary)])
            outputs.append(run([str(binary)]).stdout)
        assert outputs[0] == outputs[1], 'register names and unknown-register behavior must stay identical'
    print('PASS: pinned ld64 rejects original table and links patched x86_64 Mach-O loader')
    print('PASS: static-only codegen change; 193 native register-name comparisons unchanged')


if __name__ == '__main__':
    main()
