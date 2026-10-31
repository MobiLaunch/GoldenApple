#!/usr/bin/env python3
"""Reproduce Darwin sin/cos self recursion with pinned source and Clang.

Inspect actual Darwin assembly code generation, then execute the same patched source
against host libm for numeric checks. This is not a Darling GUI support claim.
"""
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
CC = os.environ.get('CC', 'clang')
CMAKE = os.environ.get('CMAKE', 'cmake')


def run(argv, cwd=None):
    result = subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout


def body(ir, name):
    match = re.search(r'^_' + re.escape(name) + r':[^\n]*\n.*?\.cfi_endproc', ir, re.S | re.M)
    if not match:
        raise RuntimeError('Missing assembly function ' + name)
    return match.group()


def main():
    source = Path(sys.argv[1]).resolve()
    def blob(path):
        return run(['git', '-C', str(source), 'show', LOCK['darling_commit'] + ':' + path])
    with tempfile.TemporaryDirectory(prefix='darling-sincos-') as directory:
        temp = Path(directory)
        libm = temp / 'src/libm'
        (libm / 'Source/architecture/i386').mkdir(parents=True)
        for path in ('CMakeLists.txt', 'Source/sincos.c', 'Source/math.h'):
            (libm / path).write_text(blob('src/libm/' + path))
        # Substitute the platform header's declarations only; retain the actual
        # upstream wrapper code, aggregate layout and build flag logic.
        (libm / 'Source/architecture/i386/math.h').write_text('''
#define M_PI 3.14159265358979323846264338327950288
extern double sin(double), cos(double);
extern float sinf(float), cosf(float);
''')
        (libm / 'control.c').write_text('#include "math.h"\ndouble control(double x) { return sin(x)+cos(x); }\n')
        (libm / 'numbers.c').write_text('''#include "math.h"
#include <assert.h>
#include <stdio.h>
static double absolute(double x) { return x < 0 ? -x : x; }
int main(void) {
    double values[] = {0, -0.0, 0.5, -0.5, 1, -1, 3.25, -3.25, 1000, -1000};
    int checks = 0;
    for (unsigned i=0; i<sizeof(values)/sizeof(values[0]); ++i) {
        double x=values[i]; float f=(float)x;
        struct __double2 d=__sincos_stret(x), p=__sincospi_stret(x);
        struct __float2 s=__sincosf_stret(f), q=__sincospif_stret(f);
        assert(absolute(d.__sinval-sin(x))<1e-12);
        assert(absolute(d.__cosval-cos(x))<1e-12);
        assert(absolute(p.__sinval-sin(x*M_PI))<1e-12);
        assert(absolute(p.__cosval-cos(x*M_PI))<1e-12);
        assert(absolute(s.__sinval-sinf(f))<1e-6);
        assert(absolute(s.__cosval-cosf(f))<1e-6);
        assert(absolute(q.__sinval-sinf((float)(f*M_PI)))<1e-6);
        assert(absolute(q.__cosval-cosf((float)(f*M_PI)))<1e-6);
        checks+=8;
    }
    assert(__builtin_signbit(__sincos_stret(-0.0).__sinval));
    assert(__builtin_signbit(__sincosf_stret(-0.0f).__sinval));
    struct __double2 n=__sincos_stret(__builtin_nan(""));
    struct __double2 inf=__sincos_stret(__builtin_inf());
    assert(n.__sinval != n.__sinval && n.__cosval != n.__cosval);
    assert(inf.__sinval != inf.__sinval && inf.__cosval != inf.__cosval);
    printf("%d numeric checks passed\\n",checks+4);
}
''')
        (temp / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.13)
project(SincosProbe C)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_subdirectory(src/libm)
''')
        def configure(mode, label):
            upstream = (libm / 'CMakeLists.txt').read_text()
            (libm / 'probe-flags.cmake').write_text(upstream[:upstream.index('set(libm_sources')])
            (libm / 'Probe.txt').write_text('''include(probe-flags.cmake)
add_library(guest OBJECT Source/sincos.c control.c)
target_include_directories(guest PRIVATE Source)
target_compile_options(guest PRIVATE -target x86_64-apple-darwin20 -S)
add_executable(numbers Source/sincos.c numbers.c)
target_include_directories(numbers PRIVATE Source)
set_source_files_properties(numbers.c PROPERTIES COMPILE_OPTIONS "-fno-builtin;-UNDEBUG")
target_link_libraries(numbers PRIVATE m)
''')
            # Use the probe as this subdirectory's CMakeLists while preserving
            # the complete pinned file separately for applying the real patch.
            pinned = libm / 'CMakeLists.txt'
            old = pinned.read_text(); pinned.write_text((libm / 'Probe.txt').read_text())
            build = temp / label
            try:
                run([CMAKE, '-S', str(temp), '-B', str(build), '-DCMAKE_C_COMPILER=' + CC,
                     '-DCMAKE_BUILD_TYPE=' + mode])
                run([CMAKE, '--build', str(build)])
            finally:
                pinned.write_text(old)
            return build
        baseline = configure('RelWithDebInfo', 'baseline')
        ir = (baseline / 'src/libm/CMakeFiles/guest.dir/Source/sincos.c.o').read_text()
        for name in ('__sincos_stret', '__sincosf_stret'):
            assert re.search(r'(?:callq|jmp)\s+_' + name + r'\b', body(ir, name)), 'Expected original self recursion'
        print('Baseline Darwin codegen reproduces double and float self recursion')
        run(['git', 'apply', str(VENDOR / 'patches/0008-sincos-recursion.patch')], cwd=temp)
        for mode in ('Release', 'RelWithDebInfo', 'Debug'):
            build = configure(mode, mode)
            ir = (build / 'src/libm/CMakeFiles/guest.dir/Source/sincos.c.o').read_text()
            for name, calls in (('__sincos_stret', ('sin', 'cos')), ('__sincosf_stret', ('sinf', 'cosf'))):
                function = body(ir, name)
                assert not re.search(r'(?:callq|jmp)\s+_' + name + r'\b', function), 'Patched wrapper recurses'
                for call in calls:
                    assert re.search(r'(?:callq|jmp)\s+_' + call + r'\b', function), 'Missing scalar math call'
            control = (build / 'src/libm/CMakeFiles/guest.dir/control.c.o').read_text()
            if mode != 'Debug':
                assert re.search(r'(?:callq|jmp)\s+___sincos_stret\b', body(control, 'control')), 'Other sources lost optimization'
            print(mode + ': ' + run([str(build / 'src/libm/numbers')]).strip())
        print('Darwin recursion prevented without disabling other source optimizations')


if __name__ == '__main__':
    main()
