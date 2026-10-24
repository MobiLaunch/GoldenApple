#!/usr/bin/env python3
"""Test pinned root/Cocotron/objc4 patches in isolated repos; input is read only."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('darling_build', ROOT / 'tools/darling/build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = Path(sys.argv[1]).resolve()
lock = json.loads((ROOT / 'third_party/darling/source.lock.json').read_text())


def git(path, *args):
    return subprocess.check_output(['git', *args], cwd=path, stderr=subprocess.STDOUT)


def rejects(source, config, message):
    try:
        module.apply_patches(source, config)
    except RuntimeError:
        return
    raise AssertionError(message)


with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    coco = temp / 'src/external/cocotron'
    coco.mkdir(parents=True)
    objc = temp / 'src/external/objc4'
    objc.mkdir(parents=True)
    repositories = {'darling': temp, 'cocotron': coco, 'objc4': objc}
    upstream = {'darling': source, 'cocotron': source / 'src/external/cocotron',
                'objc4': source / 'src/external/objc4'}
    paths = {name: set() for name in repositories}
    new_paths = {name: set() for name in repositories}
    for patch in lock['patches']:
        name = patch.get('repository', 'cocotron')
        current = None
        for line in (module.VENDOR / patch['path']).read_text().splitlines():
            if line.startswith('diff --git '):
                current = line.split(' b/', 1)[1]
                paths[name].add(current)
            elif line.startswith('new file mode '):
                new_paths[name].add(current)
    for name, repo in repositories.items():
        git(repo, 'init', '-q')
        if name == 'darling':
            # Model the real root repository's submodule without treating its
            # separate working tree as untracked user work in this tiny fixture.
            (repo / '.git/info/exclude').write_text('src/external/cocotron/\nsrc/external/objc4/\n')
        for path in paths[name] - new_paths[name]:
            target = repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(git(upstream[name], 'show', lock[name + '_commit'] + ':' + path))
            git(repo, 'add', path)
        git(repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
            'commit', '--allow-empty', '-qm', 'pinned baseline blobs')
    config = copy.deepcopy(lock)
    for name, repo in repositories.items():
        config[name + '_commit'] = git(repo, 'rev-parse', 'HEAD').decode().strip()

    def snapshot():
        return {(name, path): (repo / path).read_bytes() if (repo / path).exists() else None
                for name, repo in repositories.items() for path in paths[name]}

    def reset():
        for name, repo in repositories.items():
            git(repo, 'restore', '.')
            for path in new_paths[name]:
                (repo / path).unlink(missing_ok=True)

    module.apply_patches(temp, config)
    first = snapshot()
    module.apply_patches(temp, config)
    assert snapshot() == first, 'all three repositories must be idempotent'
    for changed in (coco / 'AppKit/NSViewController.m', temp / 'src/private-frameworks/CMakeLists.txt',
                    temp / 'src/private-frameworks/PIP/src/PIP.m', objc / 'runtime/CMakeLists.txt',
                    temp / 'src/frameworks/CoreServices/src/FSEvents/CMakeLists.txt',
                    temp / 'src/CMakeLists.txt'):
        expected = changed.read_bytes()
        changed.write_bytes(expected + b'\n// unrelated local edit\n')
        before = snapshot()
        rejects(temp, config, 'same-file changes must be refused in every repository')
        assert snapshot() == before, 'preflight must preserve all local changes'
        changed.write_bytes(expected)
    for repo in repositories.values():
        extra = repo / 'unexpected.txt'
        extra.write_text('local work')
        rejects(temp, config, 'untracked edits must be refused')
        extra.unlink()
    for field in ('sha256', 'repository'):
        bad = copy.deepcopy(config)
        bad['patches'][0][field] = '0' * 64 if field == 'sha256' else 'unknown'
        rejects(temp, bad, 'invalid lock must be refused')
    for name in repositories:
        bad = copy.deepcopy(config)
        bad[name + '_commit'] = '0' * 40
        rejects(temp, bad, 'revision mismatch must be refused')

    reset()
    git(coco, 'apply', str(module.VENDOR / lock['patches'][0]['path']))
    before = snapshot()
    rejects(temp, config, 'partial Cocotron series must be refused before root changes')
    assert snapshot() == before
    reset()
    # A root conflict cannot result in Cocotron patches being applied first.
    root_file = temp / 'src/private-frameworks/CMakeLists.txt'
    root_file.write_text(root_file.read_text() + '\n# local work\n')
    before = snapshot()
    rejects(temp, config, 'root drift must be refused before mutating any repository')
    assert snapshot() == before
    reset()
    pristine = snapshot()
    actual_run = module.run

    def fail_second_group(args, *, cwd=None, env=None):
        if cwd == coco and args[1] == 'apply' and '--reverse' not in args:
            raise subprocess.CalledProcessError(1, args)
        actual_run(args, cwd=cwd, env=env)

    with mock.patch.object(module, 'run', fail_second_group):
        try:
            module.apply_patches(temp, config)
        except subprocess.CalledProcessError:
            pass
        else:
            raise AssertionError('injected apply failure must propagate')
    assert snapshot() == pristine, 'completed root group must roll back after second-group failure'
    # A failure in the third repository must also roll back both earlier groups.
    def fail_third_group(args, *, cwd=None, env=None):
        if cwd == objc and args[1] == 'apply' and '--reverse' not in args:
            raise subprocess.CalledProcessError(1, args)
        actual_run(args, cwd=cwd, env=env)
    with mock.patch.object(module, 'run', fail_third_group):
        try:
            module.apply_patches(temp, config)
        except subprocess.CalledProcessError:
            pass
        else:
            raise AssertionError('third-repository failure must propagate')
    assert snapshot() == pristine, 'both completed groups must roll back after third-group failure'
    # An existing M1 checkout may already carry Cocotron patches. Preflight
    # permits adding the separate root framework series without resetting it.
    cocoa_patches = [str(module.VENDOR / p['path']) for p in lock['patches']
                    if p.get('repository', 'cocotron') == 'cocotron']
    git(coco, 'apply', *cocoa_patches)
    module.apply_patches(temp, config)
    assert snapshot() == first, 'M1 checkouts can gain root framework patches'
print('PASS: multi-repository preflight, idempotence, drift protection, rollback and M1 upgrade')
