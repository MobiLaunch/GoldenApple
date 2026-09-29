#!/usr/bin/env python3
from pathlib import Path
import json, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
helper=root/"apps/installer/helper.py"
# The helper must stay read-only: disk discovery only, never partition/format/mount.
src=helper.read_text()
for forbidden in ["mkfs", "parted", "wipefs", "sgdisk", "fdisk", "mount", "dd if="]:
    assert forbidden not in src, forbidden
# Verify parsing against a fake lsblk executable so CI never touches host disks.
with tempfile.TemporaryDirectory() as td:
    p=Path(td)/"lsblk"
    p.write_text('#!/bin/sh\nprintf \'%s\\n\' \'{"blockdevices":[{"path":"/dev/sda","model":"Internal","size":1000000000,"type":"disk","tran":"sata","rm":false},{"path":"/dev/sdb","model":"USB","size":2000000000,"type":"disk","tran":"usb","rm":true},{"path":"/dev/sda1","model":null,"size":1,"type":"part","tran":null,"rm":false}]}\'\n')
    p.chmod(0o755)
    import os
    env=os.environ.copy(); env["PATH"]=td+os.pathsep+env["PATH"]
    out=subprocess.check_output(["python3",str(helper),"disks"],text=True,env=env)
    disks=json.loads(out)
    assert len(disks)==1 and disks[0]["path"]=="/dev/sda"
print("installer safety: passed")
