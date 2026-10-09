#!/usr/bin/env python3
"""Music persistence and actual MPRIS wire contracts on a private session bus."""
import asyncio
import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from dbus_next import Variant, DBusError
from dbus_next.aio import MessageBus

ROOT=Path(__file__).resolve().parents[1]
HELPER=ROOT/'apps/music/session.py'
spec=importlib.util.spec_from_file_location('music_session',HELPER)
session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)

class Sessions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.home=Path(self.tmp.name)
        self.env={**os.environ,'XDG_STATE_HOME':str(self.home)}
        self.track=self.home/'曲 #one.wav';self.track.touch()
        self.data=dict(queue=[dict(path=str(self.track),title='One'),dict(path=str(self.home/'missing.wav'),title='Missing')],
                       index=0,order=[1,0],position=34.5,shuffle=True,repeat='all',volume=.35,muted=True)
    def tearDown(self):self.tmp.cleanup()
    def call(self,mode,data=None):
        r=subprocess.run([sys.executable,str(HELPER),mode],input=json.dumps(data) if data is not None else None,
                         env=self.env,text=True,capture_output=True,timeout=5)
        return r,json.loads(r.stdout)
    def test_new_account(self):
        r,out=self.call('read');self.assertEqual(r.returncode,0)
        self.assertEqual(out['session']['queue'],[]);self.assertEqual(out['session']['volume'],.8)
    def test_roundtrip_and_missing_files(self):
        self.assertTrue(self.call('write',self.data)[1]['ok'])
        s=self.call('read')[1]['session']
        self.assertEqual(len(s['queue']),1);self.assertEqual(s['order'],[0]);self.assertEqual(s['position'],34.5)
        self.assertEqual(s['skipped'],1);self.assertEqual(s['volume'],.35);self.assertTrue(s['muted'])
        self.assertTrue(s['shuffle']);self.assertEqual(s['repeat'],'all')
        self.assertEqual((self.home/'golden-gate/music/session.json').stat().st_mode & 0o777,0o600)
    def test_deleted_current_does_not_apply_position_to_successor(self):
        self.data.update(index=1,position=500)
        self.call('write',self.data);s=self.call('read')[1]['session']
        self.assertEqual(s['index'],0);self.assertEqual(s['position'],0)
    def test_opt_out_preserves_preferences_without_queue(self):
        self.data['remember']=False;self.call('write',self.data)
        s=self.call('read')[1]['session'];self.assertFalse(s['remember']);self.assertEqual(s['queue'],[])
        self.assertEqual(s['volume'],.35);self.assertTrue(s['muted'])
    def test_corrupt_record_is_preserved(self):
        self.call('write',self.data);path=self.home/'golden-gate/music/session.json'
        path.write_text('{broken')
        self.assertFalse(self.call('read')[1]['ok']);self.assertFalse(self.call('write',self.data)[1]['ok'])
        self.assertEqual(path.read_text(),'{broken')
    def test_explicit_forget_preserves_backup_and_recovers(self):
        self.call('write',self.data);path=self.home/'golden-gate/music/session.json'
        path.write_text('{broken')
        self.assertTrue(self.call('forget')[1]['ok']);self.assertFalse(path.exists())
        backups=list(path.parent.glob('session.forgotten-*.json'))
        self.assertEqual(len(backups),1);self.assertEqual(backups[0].read_text(),'{broken')
        self.assertTrue(self.call('write',self.data)[1]['ok'])
    def test_invalid_order_and_numeric_inputs(self):
        self.data.update(order=[True,1],position=float('nan'),volume=2)
        s=session.normalize(self.data);self.assertEqual(s['order'],[0,1]);self.assertEqual(s['position'],0);self.assertEqual(s['volume'],1)
    def test_invalid_track_refused(self):
        for item in ({'path':'relative.wav'},{'radio':True,'url':'file:///etc/passwd'},{'radio':True,'url':'https://user:pass@example.invalid'}):
            with self.assertRaises(ValueError):session.normalize({'queue':[item]})
    def test_radio_is_saved_without_contacting_station(self):
        s=session.normalize(dict(queue=[dict(radio=True,url='https://example.invalid/stream',title='Station')],index=0),True)
        self.assertTrue(s['queue'][0]['radio'])

class Mpris(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.proc=await asyncio.create_subprocess_exec(sys.executable,str(ROOT/'apps/music/mpris.py'),
            stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
        self.ready=await self.event();self.assertEqual(self.ready.get('event'),'ready',self.ready)
        self.bus=await MessageBus().connect()
        intro=await self.bus.introspect(self.ready['name'],'/org/mpris/MediaPlayer2')
        obj=self.bus.get_proxy_object(self.ready['name'],'/org/mpris/MediaPlayer2',intro)
        self.player=obj.get_interface('org.mpris.MediaPlayer2.Player')
        self.props=obj.get_interface('org.freedesktop.DBus.Properties')
        self.root=obj.get_interface('org.mpris.MediaPlayer2')
        self.state=dict(status='Paused',position=123.75,volume=.6,muted=False,shuffle=False,repeat='off',seekable=True,canNext=True,
                        track=dict(id='/org/goldengate/Music/track/t_1',title='曲 #one',artist='Artist',album='Album',length=4000,
                                   url='file:///tmp/%E6%9B%B2%20%23one.wav',art='file:///tmp/art.png'))
        await self.update()
    async def asyncTearDown(self):
        self.proc.stdin.close();await self.proc.stdin.wait_closed()
        await asyncio.wait_for(self.proc.wait(),3)
        self.assertEqual(self.proc.returncode,0,(await self.proc.stderr.read()).decode())
        self.bus.disconnect()
    async def event(self):return json.loads(await asyncio.wait_for(self.proc.stdout.readline(),3))
    async def update(self):
        self.proc.stdin.write((json.dumps(self.state)+'\n').encode());await self.proc.stdin.drain()
        for _ in range(100):
            if await self.player.get_playback_status()==self.state['status'] and await self.player.get_position()==int(self.state['position']*1e6):return
            await asyncio.sleep(.01)
        self.fail('Publisher did not acknowledge new state')
    async def test_typed_metadata_position_and_identity(self):
        m=await self.player.get_metadata()
        self.assertEqual(m['mpris:trackid'].signature,'o');self.assertEqual(m['mpris:length'].signature,'x')
        self.assertEqual(m['mpris:length'].value,4000000000);self.assertEqual(m['xesam:artist'].value,['Artist'])
        self.assertEqual(await self.player.get_position(),123750000)
        self.assertEqual(await self.root.get_identity(),'Music');self.assertTrue(await self.root.get_can_raise())
        self.assertEqual(await self.root.get_supported_uri_schemes(),['file'])
    async def test_transport_and_nonoptimistic_state(self):
        for fn,command in ((self.player.call_play,'play'),(self.player.call_next,'next'),(self.player.call_previous,'previous'),
                           (self.player.call_play_pause,'toggle'),(self.player.call_stop,'stop'),(self.root.call_raise,'raise'),(self.root.call_quit,'quit')):
            await fn();self.assertEqual((await self.event())['command'],command)
        self.assertEqual(await self.player.get_playback_status(),'Paused')
        self.state['status']='Playing';await self.update();await self.player.call_pause();self.assertEqual((await self.event())['command'],'pause')
    async def test_seek_and_stale_track_ids(self):
        await self.player.call_seek(-20000000);self.assertEqual((await self.event())['position'],103.75)
        await self.player.call_set_position('/org/goldengate/Music/track/stale',3000000)
        await self.player.call_set_position(self.state['track']['id'],5000000000) # outside duration
        await self.player.call_set_position(self.state['track']['id'],2500000000)
        self.assertEqual((await self.event())['position'],2500)
        await self.root.call_raise();self.assertEqual((await self.event())['command'],'raise') # no stale request left queued
    async def test_property_setters_wait_for_player_acknowledgement(self):
        for name,value,command,expected in (('LoopStatus',Variant('s','Track'),'repeat','one'),('Shuffle',Variant('b',True),'shuffle',True),('Volume',Variant('d',-.5),'volume',0)):
            await self.props.call_set('org.mpris.MediaPlayer2.Player',name,value)
            e=await self.event();self.assertEqual((e['command'],e['value']),(command,expected))
        self.assertEqual(await self.player.get_loop_status(),'None');self.assertFalse(await self.player.get_shuffle())
        with self.assertRaises(DBusError):await self.player.set_rate(2)
        with self.assertRaises(DBusError):await self.player.set_loop_status('bad')
    async def test_position_updates_do_not_emit_properties_changed(self):
        events=[];seeked=[]
        self.props.on_properties_changed(lambda interface, changed, invalidated: events.append((interface, changed, invalidated)))
        self.player.on_seeked(lambda position:seeked.append(position))
        await asyncio.sleep(.03)
        self.state['position']=150;await self.update();await asyncio.sleep(.04)
        self.assertFalse(any('Position' in e[1] for e in events))
        self.state.update(position=160,seeked=True);await self.update();await asyncio.sleep(.04)
        self.assertEqual(seeked,[160000000])
    async def test_local_open_only_and_encoded_paths(self):
        for url in ('https://example.invalid/stream','file://remote/tmp/a.wav','file:///tmp/a.wav#fragment'):
            with self.assertRaises(DBusError):await self.player.call_open_uri(url)
        await self.player.call_open_uri('file:///tmp/%E6%9B%B2%20%23one.wav')
        self.assertEqual((await self.event())['path'],'/tmp/曲 #one.wav')
    async def test_no_track_and_unseekable_station(self):
        self.state.update(track=None,status='Stopped',position=0,canNext=False,seekable=False);await self.update()
        self.assertFalse(await self.player.get_can_play());self.assertEqual(await self.player.get_metadata(),{})
        await self.player.call_next();await self.player.call_play();await self.player.call_seek(1000000)
        await self.root.call_raise();self.assertEqual((await self.event())['command'],'raise')
    async def test_large_or_invalid_numbers_do_not_break_wire_types(self):
        self.state.update(position=10**30);self.state['track']['length']=10**30
        self.proc.stdin.write((json.dumps(self.state)+'\n').encode());await self.proc.stdin.drain();await asyncio.sleep(.05)
        self.assertEqual(await self.player.get_position(),10**15)
        self.assertEqual((await self.player.get_metadata())['mpris:length'].value,10**15)

class Contracts(unittest.TestCase):
    def setUp(self):
        spec=importlib.util.spec_from_file_location('music_mpris',ROOT/'apps/music/mpris.py')
        self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        self.player=self.module.Player()
        self.state=dict(status='Paused',position=123.75,volume=.6,muted=False,shuffle=False,repeat='off',seekable=True,canNext=True,
                        track=dict(id='/org/goldengate/Music/track/t_1',title='曲 #one',artist='Artist',album='Album',length=4000,url='file:///tmp/a.wav'))
        self.player.update(self.state)
    def capture(self,fn,*args):
        out=io.StringIO()
        with contextlib.redirect_stdout(out):fn(*args)
        return [json.loads(line) for line in out.getvalue().splitlines()]
    def test_wire_serialization_with_64_bit_positions(self):
        from dbus_next import Message
        for signature,body in (('x',[self.player.Position]),('a{sv}',[self.player.Metadata])):
            wire=Message(path='/test',interface='org.example.Test',member='Value',signature=signature,body=body)._marshall()
            self.assertGreater(len(wire),40)
        self.assertEqual(self.player.Metadata['mpris:length'].value,4000000000)
        self.assertEqual(self.player.Position,123750000)
    def test_state_is_not_optimistically_changed(self):
        self.assertEqual(self.capture(self.player.Play),[dict(command='play')])
        self.assertEqual(self.player.PlaybackStatus,'Paused')
        self.assertEqual(self.capture(self.player.Pause),[])
        self.state['status']='Playing';self.player.update(self.state)
        self.assertEqual(self.capture(self.player.Pause),[dict(command='pause')])
        self.assertEqual(self.capture(self.player.Play),[])
    def test_seek_rejects_stale_and_out_of_range(self):
        self.assertEqual(self.capture(self.player.SetPosition,'/stale',3000000),[])
        self.assertEqual(self.capture(self.player.SetPosition,self.state['track']['id'],5000000000),[])
        self.assertEqual(self.capture(self.player.SetPosition,self.state['track']['id'],2500000000),[dict(command='seek',position=2500)])
        self.assertEqual(self.capture(self.player.Seek,-20000000),[dict(command='seek',position=103.75)])
    def test_open_uri_decodes_local_path_and_refuses_remote(self):
        self.assertEqual(self.capture(self.player.OpenUri,'file:///tmp/%E6%9B%B2%20%23one.wav'),[dict(command='open',path='/tmp/曲 #one.wav')])
        with self.assertRaises(DBusError):self.player.OpenUri('https://example.invalid/stream')
    def test_properties_and_capabilities(self):
        self.assertEqual(self.capture(setattr,self.player,'LoopStatus','Track'),[dict(command='repeat',value='one')])
        self.assertEqual(self.capture(setattr,self.player,'Volume',-.5),[dict(command='volume',value=0)])
        self.assertEqual(self.capture(setattr,self.player,'Shuffle',True),[dict(command='shuffle',value=True)])
        with self.assertRaises(DBusError):self.player.Rate=2
        with self.assertRaises(DBusError):self.player.Volume=float('nan')
        self.player.update(dict(track=None,status='Stopped'))
        self.assertFalse(self.player.CanPlay);self.assertFalse(self.player.CanSeek)
        self.assertEqual(self.capture(self.player.Next),[])
    def test_position_notifications_and_seeked(self):
        changes=[];seeks=[]
        self.player.emit_properties_changed=lambda values:changes.append(values)
        self.player.Seeked=lambda position:seeks.append(position)
        self.state={**self.state,'position':150};self.player.update(self.state)
        self.assertEqual(changes,[])
        self.player.update({**self.state,'position':160,'seeked':True});self.assertEqual(seeks,[160000000])
    def test_large_numbers_are_clamped(self):
        self.player.update({**self.state,'position':10**30,'track':{**self.state['track'],'length':10**30}})
        self.assertEqual(self.player.Position,10**15);self.assertEqual(self.player.Metadata['mpris:length'].value,10**15)

if __name__=='__main__':
    wire_requested=not sys.argv[1:] or any(arg.startswith('Mpris') for arg in sys.argv[1:])
    if wire_requested and not os.environ.get('GG_MUSIC_TEST_BUS'):
        raise SystemExit(subprocess.call(['dbus-run-session','--',sys.executable,__file__,*sys.argv[1:]],env={**os.environ,'GG_MUSIC_TEST_BUS':'1'}))
    unittest.main()
