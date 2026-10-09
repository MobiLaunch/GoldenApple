#!/usr/bin/env python3
"""Validate and atomically save Music's paused-on-reopen session."""
import fcntl
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time
from urllib.parse import urlparse


def number(value, default, minimum=0, maximum=10**9):
    if not isinstance(value,(int,float)) or isinstance(value,bool) or not math.isfinite(value): return default
    return max(minimum,min(maximum,value))


def normalize(data, check_files=False):
    if not isinstance(data,dict) or data.get("version",1)!=1: raise ValueError("The saved Music session isn't valid.")
    raw=data.get("queue",[])
    if not isinstance(raw,list) or len(raw)>10000: raise ValueError("The saved queue isn't valid.")
    queue=[]; mapping={}; skipped=0
    original=int(number(data.get("index"),-1,-1,10000))
    for i, item in enumerate(raw):
        if not isinstance(item,dict): raise ValueError("A saved queue item isn't valid.")
        track={k:str(item.get(k,"") or "")[:8192] for k in ("title","artist","album","albumArtist","art")}
        track["seconds"]=number(item.get("seconds"),0)
        if item.get("radio") is True:
            url=str(item.get("url", "")); u=urlparse(url)
            if u.scheme not in ("http","https") or not u.hostname or u.username or u.password: raise ValueError("A saved station address isn't valid.")
            track.update(radio=True,url=url)
        else:
            path=item.get("path")
            if not isinstance(path,str) or not os.path.isabs(path): raise ValueError("A saved track needs a local path.")
            if check_files and not Path(path).is_file(): skipped+=1; continue
            track["path"]=path
        mapping[i]=len(queue);queue.append(track)
    index=mapping.get(original, min(sum(i<original for i in mapping),len(queue)-1)) if queue else -1
    position=number(data.get("position"),0) if original in mapping else 0
    old_order=data.get("order",list(range(len(raw))))
    if not isinstance(old_order,list) or sorted(i for i in old_order if isinstance(i,int) and not isinstance(i,bool))!=list(range(len(raw))) or len(old_order)!=len(raw):
        old_order=list(range(len(raw)))
    order=[mapping[i] for i in old_order if i in mapping]
    remember=data.get("remember",True) is not False
    return dict(version=1,remember=remember,queue=queue if remember else [],index=index if remember else -1,
                position=position if remember else 0,order=order if remember else [],shuffle=data.get("shuffle") is True,
                repeat=data.get("repeat") if data.get("repeat") in ("off","all","one") else "off",
                volume=number(data.get("volume"),.8,0,1),muted=data.get("muted") is True,skipped=skipped)


def session_path():
    return Path(os.environ.get("XDG_STATE_HOME",Path.home()/".local/state"))/"golden-gate/music/session.json"


def main():
    try:
        path=session_path()
        if len(sys.argv)!=2 or sys.argv[1] not in ("read","write","forget"): raise ValueError("Choose read, write or forget.")
        if sys.argv[1]=="read":
            try: data=json.loads(path.read_text())
            except FileNotFoundError: data={}
            result=dict(ok=True,session=normalize(data,True))
        elif sys.argv[1]=="forget":
            path.parent.mkdir(parents=True,exist_ok=True)
            with (path.parent/".session.lock").open("a") as lock:
                fcntl.flock(lock,fcntl.LOCK_EX)
                if path.exists(): os.replace(path,path.with_name("session.forgotten-"+str(time.time_ns())+".json"))
            result=dict(ok=True)
        else:
            data=normalize(json.load(sys.stdin))
            path.parent.mkdir(parents=True,exist_ok=True)
            with (path.parent/".session.lock").open("a") as lock:
                fcntl.flock(lock,fcntl.LOCK_EX)
                # A damaged record is never overwritten on a guess.
                if path.exists(): normalize(json.loads(path.read_text()))
                fd,temp=tempfile.mkstemp(prefix=".session-",dir=path.parent)
                try:
                    with os.fdopen(fd,"w") as out: json.dump(data,out);out.flush();os.fsync(out.fileno())
                    os.replace(temp,path)
                finally: Path(temp).unlink(missing_ok=True)
            result=dict(ok=True)
        print(json.dumps(result));return 0
    except (OSError,ValueError,TypeError) as exc:
        print(json.dumps(dict(ok=False,error="Music couldn't restore or save the queue: " + str(exc))));return 1


if __name__=="__main__": raise SystemExit(main())
