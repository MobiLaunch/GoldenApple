#!/usr/bin/env python3
"""Read-only helper for the graphical installer. Destructive work stays in archinstall."""
import json, subprocess, sys
def disks():
    p=subprocess.run(["lsblk","-J","-b","-d","-o","PATH,MODEL,SIZE,TYPE,TRAN,RM"],text=True,capture_output=True,check=True)
    out=[]
    for d in json.loads(p.stdout).get("blockdevices",[]):
        if d.get("type")!="disk" or d.get("rm") in (1,True): continue
        out.append({"path":d.get("path",""),"model":(d.get("model") or "Storage Device").strip(),"size":int(d.get("size") or 0),"transport":d.get("tran") or ""})
    print(json.dumps(out))
if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="disks": disks()
    else: raise SystemExit(2)
