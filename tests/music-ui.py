#!/usr/bin/env python3
"""Production Music player + controls with real local WAV decoding, fixture services.

No desktop, maps, radio catalog, geolocation, or external commands are loaded.
"""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import wave
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QEvent,QUrl,Slot,Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine,QQmlEngine,QQmlExpression
from PySide6.QtTest import QTest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/preview'))
import preview
APP=QGuiApplication([])

class System(preview.Preview):
    def __init__(self,state):
        super().__init__({},str(ROOT/'shell'),"'default'")
        self.state=state;self.fail=False;self.commands=[]
    @Slot('QVariant',result='QVariantMap')
    def run(self,cmd):
        cmd=cmd.toVariant() if hasattr(cmd,'toVariant') else cmd
        self.commands.append(cmd)
        if cmd and str(cmd[-1])=='read':return dict(stdout=json.dumps(dict(ok=True,session=self.state)),stderr='',code=0)
        if cmd and str(cmd[-1]) in ('write','forget'):return dict(stdout=json.dumps(dict(ok=not self.fail,error='Test disk full' if self.fail else '')),stderr='',code=1 if self.fail else 0)
        if cmd and str(cmd[-1]).endswith('mpris.py'):return dict(stdout='',stderr='',code=0,hang=True)
        return dict(stdout='',stderr='',code=0)

WRAPPER='''import QtQuick
import "../apps/music" as Music
import "../apps/lib/theme"
Window {
    id: root; width: 600; height: 170; visible: true
    property bool closed: false
    Music.Player { id: audio; onCloseReady: root.closed = true }
    Music.Mpris { id: bridge; player: audio; objectName: "bridge" }
    Music.MiniPlayer { id: controls; objectName: "controls"; player: audio; width: 560; anchors.centerIn: parent }
    function call(code) { return eval(code) }
    function scaleText(value) { Theme.textScale = value }
}
'''
class Playback(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.home=Path(self.tmp.name)
        self.wav=self.home/'曲 #one.wav'
        with wave.open(str(self.wav),'wb') as out:
            out.setnchannels(1);out.setsampwidth(2);out.setframerate(8000);out.writeframes(b'\0\0'*8000*20)
        track=dict(path=str(self.wav),title='A long title with 曲 and #',artist='Artist',album='Album',art='',seconds=20)
        self.state=dict(version=1,remember=True,queue=[track,{**track,'title':'Second'}],index=0,order=[1,0],position=7,
                        shuffle=True,repeat='all',volume=.35,muted=True,skipped=0)
        self.engine=None;self.root=None
        self.wrapper=ROOT/'tests/.music-test.qml';self.wrapper.write_text(WRAPPER)
    def tearDown(self):
        if self.root:self.root.deleteLater()
        if self.engine:self.engine.deleteLater()
        APP.processEvents();APP.sendPostedEvents(None,QEvent.DeferredDelete)
        self.wrapper.unlink(missing_ok=True);self.tmp.cleanup()
    def load(self):
        self.system=System(self.state);self.engine=QQmlApplicationEngine()
        self.interceptor=preview.SingletonDirs();self.engine.addUrlInterceptor(self.interceptor)
        self.engine.addImportPath(str(ROOT/'tools/preview/qml'))
        self.engine.rootContext().setContextProperty('__preview',self.system)
        self.engine.load(QUrl.fromLocalFile(str(self.wrapper)))
        self.assertTrue(self.engine.rootObjects(),'Production player failed to load')
        self.root=self.engine.rootObjects()[0]
        self.wait('audio.sessionReady')
    def eval(self,code):
        e=QQmlExpression(QQmlEngine.contextForObject(self.root),self.root,code)
        result=e.evaluate()[0];self.assertFalse(e.hasError(),e.error().toString())
        return result.toVariant() if hasattr(result,'toVariant') else result
    def wait(self,code):
        for _ in range(300):
            if self.eval(code):return
            QTest.qWait(10)
        self.fail('Timed out: '+code)
    def test_restore_paused_and_seek_local_decoded_audio(self):
        self.load();self.wait('audio.seekable')
        self.assertEqual(self.eval('audio.playbackStatus'),'Paused')
        self.assertFalse(self.eval('audio.playing'));self.wait('audio.position === 7')
        self.assertAlmostEqual(self.eval('audio.volume'),.35,places=6);self.assertTrue(self.eval('audio.muted'))
        self.assertEqual(self.eval('JSON.stringify(audio.order)'),'[1,0]')
        self.eval('audio.seek(12)');self.assertAlmostEqual(self.eval('audio.position'),12,places=1)
        self.eval('audio.play()');self.wait('audio.playing')
        self.eval('audio.pause()');self.wait('!audio.playing')
        self.eval('audio.previous()');self.assertEqual(self.eval('audio.position'),0)
    def test_paused_and_stopped_navigation(self):
        self.load();self.wait('audio.seekable')
        self.eval('audio.seek(0);audio.next()');self.wait('audio.seekable')
        self.assertEqual(self.eval('audio.index'),1);self.assertEqual(self.eval('audio.playbackStatus'),'Paused')
        self.eval('audio.stop();audio.next()');self.assertEqual(self.eval('audio.playbackStatus'),'Stopped')
        self.eval('audio.playList(audio.queue,0)');self.wait('audio.playing')
        self.eval('audio.next()');self.wait('audio.playing');self.assertEqual(self.eval('audio.index'),1)
    def test_radio_restore_never_loads_stream(self):
        self.state.update(queue=[dict(radio=True,url='https://example.invalid/stream',title='Radio',artist='',album='',art='')],index=0,order=[0],position=0)
        self.load();media=self.root.findChild(__import__('PySide6.QtCore',fromlist=['QObject']).QObject,'musicMedia')
        self.assertEqual(media.property('source').toString(),'');self.assertFalse(self.eval('audio.seekable'))
        self.assertEqual(self.eval('audio.playbackStatus'),'Paused')
    def test_failure_stays_reviewable_before_quit(self):
        self.load();self.wait('audio.seekable');self.system.fail=True
        self.eval('audio.seek(9);audio.requestClose()');self.wait('audio.sessionNotice.length > 0')
        self.assertFalse(self.eval('closed'));self.assertFalse(self.eval('audio.closing'))
        self.system.fail=False;self.eval('audio.requestClose()');self.wait('closed')
    def test_close_flushes_checkpoint_and_opt_out(self):
        self.load();self.wait('audio.seekable')
        self.eval('audio.seek(11);audio.rememberPlayback=false;audio.requestClose()');self.wait('closed')
        data=json.loads(self.eval('audio.savedPayload'));self.assertFalse(data['remember']);self.assertEqual(data['position'],11)
    def test_system_commands_use_actual_player(self):
        self.load();self.wait('audio.seekable')
        self.eval('bridge.command({command:"volume",value:0.7})')
        self.assertFalse(self.eval('audio.muted'));self.assertAlmostEqual(self.eval('audio.volume'),.7,places=6)
        self.eval('bridge.command({command:"seek",position:10})');self.assertEqual(self.eval('audio.position'),10)
        self.eval('bridge.command({command:"play"})');self.wait('audio.playing')
        self.eval('bridge.command({command:"pause"})');self.wait('!audio.playing')
    def test_keyboard_controls_and_large_text(self):
        self.load();self.wait('audio.seekable')
        # The same production controls are reached by keyboard and accessibility.
        self.root.scaleText(1.5);QTest.qWait(50)
        self.assertGreaterEqual(self.eval('controls.height'),60)
        def descendants(obj):
            yield obj
            for child in obj.children():yield from descendants(child)
        play=next(o for o in descendants(self.root) if o.property('label')=='Play')
        play.forceActiveFocus();QTest.keyClick(self.root,Qt.Key_Space);self.wait('audio.playing')
        QTest.keyClick(self.root,Qt.Key_Space);self.wait('!audio.playing')
        output=os.environ.get('GG_MUSIC_SHOT')
        if output:self.assertTrue(self.root.grabWindow().save(output))
    def test_compile_main_window_without_starting_services(self):
        self.load()
        from PySide6.QtQml import QQmlComponent
        component=QQmlComponent(self.engine,QUrl.fromLocalFile(str(ROOT/'apps/music.qml')))
        while component.isLoading():QTest.qWait(10)
        self.assertFalse(component.isError(),'\n'.join(e.toString() for e in component.errors()))
    def test_local_playback_error_and_retry(self):
        self.load()
        self.eval('audio.playList([{path:"/missing/audio-test.wav",title:"Missing",artist:"",album:"",art:""}],0)')
        self.wait('audio.error.length > 0')
        self.assertEqual(self.eval('audio.playbackStatus'),'Stopped')
        self.assertIn('Missing',self.eval('audio.error'))
        self.eval('audio.clearQueue()');self.assertEqual(self.eval('audio.error'),'')
    def test_forget_saved_queue_clears_live_queue_and_notice(self):
        self.load();self.eval('audio.sessionNotice="Damaged saved queue";audio.forgetSavedQueue()')
        self.wait('audio.queue.length === 0');self.assertEqual(self.eval('audio.sessionNotice'),'')
    def test_clear_queue_clears_transport_and_saved_state(self):
        self.load();self.eval('audio.clearQueue();audio.requestClose()');self.wait('closed')
        self.assertEqual(self.eval('audio.playbackStatus'),'Stopped');self.assertEqual(json.loads(self.eval('audio.savedPayload'))['queue'],[])
        self.assertTrue(self.wav.exists())

if __name__=='__main__':unittest.main()
