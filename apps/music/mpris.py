#!/usr/bin/env python3
"""MPRIS on the user's session bus; stdin state, stdout transport requests.

No playback, network requests or file writes occur in this process. QML remains
the playback authority and acknowledges commands by publishing its actual state.
"""
import asyncio
import json
import math
import os
import re
import sys
from urllib.parse import urlparse,unquote

try:
    from dbus_next import Variant,DBusError
    from dbus_next.aio import MessageBus
    from dbus_next.constants import PropertyAccess,NameFlag,RequestNameReply
    from dbus_next.service import ServiceInterface,method,dbus_property,signal

except ImportError:
    print(json.dumps(dict(event="error", error="System media controls need python-dbus-next. Install the latest Golden Gate update.")), flush=True)
    raise SystemExit(1)

PATH="/org/mpris/MediaPlayer2"
NO_TRACK=PATH+"/TrackList/NoTrack"


def emit(event): print(json.dumps(event,separators=(",",":")),flush=True)


def bounded(value,default=0,maximum=10**9):
    if not isinstance(value,(int,float)) or isinstance(value,bool) or not math.isfinite(value): return default
    return max(0,min(maximum,value))


class Root(ServiceInterface):
    def __init__(self): super().__init__("org.mpris.MediaPlayer2")
    @method()
    def Raise(self): emit(dict(command="raise"))
    @method()
    def Quit(self): emit(dict(command="quit"))
    @dbus_property(access=PropertyAccess.READ)
    def CanQuit(self)->'b': return True
    @dbus_property(access=PropertyAccess.READ)
    def CanRaise(self)->'b': return True
    @dbus_property(access=PropertyAccess.READ)
    def HasTrackList(self)->'b': return False
    @dbus_property(access=PropertyAccess.READ)
    def Identity(self)->'s': return "Music"
    @dbus_property(access=PropertyAccess.READ)
    def DesktopEntry(self)->'s': return "org.goldengate.Music"
    @dbus_property(access=PropertyAccess.READ)
    def SupportedUriSchemes(self)->'as': return ["file"]
    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self)->'as': return ["audio/mpeg","audio/flac","audio/ogg","audio/wav","audio/mp4","audio/aac"]


class Player(ServiceInterface):
    def __init__(self):
        super().__init__("org.mpris.MediaPlayer2.Player")
        self.state={};self.metadata={}
    def request(self,command,**args): emit(dict(command=command,**args))
    def update(self,state):
        old=self.values()
        self.state=state
        track=state.get("track")
        self.metadata={}
        if isinstance(track,dict):
            tid=str(track.get("id",NO_TRACK))
            if not re.fullmatch(r"/org/goldengate/Music/track/[A-Za-z0-9_]+",tid): tid=NO_TRACK
            self.metadata={"mpris:trackid":Variant('o',tid),"xesam:title":Variant('s',str(track.get("title","") or "")),
                           "xesam:artist":Variant('as',[str(track.get("artist","") or "")]),
                           "xesam:album":Variant('s',str(track.get("album","") or "")),
                           "xesam:url":Variant('s',str(track.get("url","") or ""))}
            if track.get("art"): self.metadata["mpris:artUrl"]=Variant('s',str(track["art"]))
            length=bounded(track.get("length"))
            if length>0: self.metadata["mpris:length"]=Variant('x',int(length*1000000))
        new=self.values()
        changes={key:value for key,value in new.items() if key!="Position" and old.get(key)!=value}
        if changes: self.emit_properties_changed(changes)
        if state.get("seeked"): self.Seeked(self.Position)
    def values(self):
        return {key:getattr(self,key) for key in ("PlaybackStatus","LoopStatus","Rate","Shuffle","Metadata","Volume","Position",
                "MinimumRate","MaximumRate","CanGoNext","CanGoPrevious","CanPlay","CanPause","CanSeek","CanControl")}
    @method()
    def Next(self):
        if self.CanGoNext: self.request("next")
    @method()
    def Previous(self):
        if self.CanGoPrevious: self.request("previous")
    @method()
    def Pause(self):
        if self.CanPause and self.PlaybackStatus=="Playing": self.request("pause")
    @method()
    def PlayPause(self):
        if self.CanPlay: self.request("toggle")
    @method()
    def Stop(self): self.request("stop")
    @method()
    def Play(self):
        if self.CanPlay and self.PlaybackStatus!="Playing": self.request("play")
    @method()
    def Seek(self,Offset:'x'):
        if self.CanSeek: self.request("seek",position=max(0,self.Position/1000000+Offset/1000000))
    @method()
    def SetPosition(self,TrackId:'o',Position:'x'):
        current=self.metadata.get("mpris:trackid")
        length=self.metadata.get("mpris:length")
        if self.CanSeek and current and TrackId==current.value and Position>=0 and (not length or Position<=length.value):
            self.request("seek",position=Position/1000000)
    @method()
    def OpenUri(self,Uri:'s'):
        u=urlparse(Uri)
        if u.scheme!="file" or u.netloc not in ("","localhost") or not u.path.startswith("/") or u.query or u.fragment:
            raise DBusError("org.freedesktop.DBus.Error.InvalidArgs","Music accepts local file addresses here.")
        self.request("open",path=unquote(u.path))
    @signal()
    def Seeked(self,Position:'x')->'x': return Position
    @dbus_property(access=PropertyAccess.READ)
    def PlaybackStatus(self)->'s': return self.state.get("status") if self.state.get("status") in ("Playing","Paused","Stopped") else "Stopped"
    @dbus_property()
    def LoopStatus(self)->'s': return {"off":"None","one":"Track","all":"Playlist"}.get(self.state.get("repeat"),"None")
    @LoopStatus.setter
    def LoopStatus(self,value:'s'):
        if value not in ("None","Track","Playlist"): raise DBusError("org.freedesktop.DBus.Error.InvalidArgs","Choose None, Track or Playlist.")
        self.request("repeat",value={"None":"off","Track":"one","Playlist":"all"}[value])
    @dbus_property()
    def Rate(self)->'d': return 1.0
    @Rate.setter
    def Rate(self,value:'d'):
        if value!=1: raise DBusError("org.freedesktop.DBus.Error.NotSupported","Music plays at normal speed.")
    @dbus_property()
    def Shuffle(self)->'b': return self.state.get("shuffle") is True
    @Shuffle.setter
    def Shuffle(self,value:'b'): self.request("shuffle",value=value)
    @dbus_property(access=PropertyAccess.READ)
    def Metadata(self)->'a{sv}': return self.metadata
    @dbus_property()
    def Volume(self)->'d': return 0.0 if self.state.get("muted") else float(bounded(self.state.get("volume"),.8,1))
    @Volume.setter
    def Volume(self,value:'d'):
        if not math.isfinite(value): raise DBusError("org.freedesktop.DBus.Error.InvalidArgs","Choose a finite volume.")
        self.request("volume",value=max(0,min(1,value)))
    @dbus_property(access=PropertyAccess.READ)
    def Position(self)->'x': return int(bounded(self.state.get("position"))*1000000)
    @dbus_property(access=PropertyAccess.READ)
    def MinimumRate(self)->'d': return 1.0
    @dbus_property(access=PropertyAccess.READ)
    def MaximumRate(self)->'d': return 1.0
    @dbus_property(access=PropertyAccess.READ)
    def CanGoNext(self)->'b': return self.state.get("canNext") is True
    @dbus_property(access=PropertyAccess.READ)
    def CanGoPrevious(self)->'b': return bool(self.metadata)
    @dbus_property(access=PropertyAccess.READ)
    def CanPlay(self)->'b': return bool(self.metadata)
    @dbus_property(access=PropertyAccess.READ)
    def CanPause(self)->'b': return bool(self.metadata)
    @dbus_property(access=PropertyAccess.READ)
    def CanSeek(self)->'b': return bool(self.metadata) and self.state.get("seekable") is True
    @dbus_property(access=PropertyAccess.READ)
    def CanControl(self)->'b': return True


async def main():
    bus=await MessageBus().connect()
    name="org.mpris.MediaPlayer2.goldengate.instance_"+str(os.getpid())
    root=Root();player=Player()
    bus.export(PATH,root);bus.export(PATH,player)
    if await bus.request_name(name,NameFlag.DO_NOT_QUEUE)!=RequestNameReply.PRIMARY_OWNER: raise RuntimeError("The Music media service name is in use.")
    emit(dict(event="ready",name=name))
    reader=asyncio.StreamReader();protocol=asyncio.StreamReaderProtocol(reader)
    transport,_=await asyncio.get_running_loop().connect_read_pipe(lambda:protocol,sys.stdin)
    try:
        while line:=await reader.readline():
            try:
                state=json.loads(line)
                if isinstance(state,dict): player.update(state)
            except (ValueError,TypeError,OverflowError): continue
    finally:
        transport.close();bus.disconnect()


if __name__=="__main__":
    try: asyncio.run(main())
    except Exception as exc:
        emit(dict(event="error",error="System media controls aren't available: "+str(exc)));raise SystemExit(1)
