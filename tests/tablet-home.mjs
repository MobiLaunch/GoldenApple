import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const root = new URL('../', import.meta.url)
const read = file => readFileSync(new URL(file, root), 'utf8')
const context = vm.createContext({})
vm.runInContext(read('shell/widgets/tablet-layout.js').replace(/^\.pragma library\s*/, ''), context)
const source = read('shell/TabletHome.qml')

test('tablet widgets start separately from desktop widgets', () => {
  const cards = context.defaults()
  assert.deepEqual(Array.from(cards, card => card.kind), ['weather', 'calendar', 'clock'])
  assert.equal(cards[0].size, 'medium')
  const desktop = read('shell/components/Prefs.qml')
  assert.match(desktop, /readonly property var widgets: Array\.isArray\(data\.widgets\)/)
  assert.match(desktop, /readonly property var tabletWidgets: Array\.isArray\(data\.tablet\?\.widgets\)/)
  assert.match(desktop, /gg-pref", "tablet\.widgets"/)
  assert.match(read('shell/DesktopWidgets.qml'), /visible: !Prefs\.tabletMode/)
})

test('widget add remove resize and drag reorder are safe and immutable', () => {
  const a = context.defaults()
  let b = context.add(a, 'music', 'small')
  assert.equal(a.length, 3)
  assert.equal(b.length, 4)
  b = context.resize(b, b[3].id, 'medium')
  assert.equal(b[3].size, 'medium')
  assert.equal(a[0].size, 'medium')
  const moved = context.move(b, b[3].id, 0)
  assert.equal(moved[0].kind, 'music')
  assert.equal(b[3].kind, 'music')
  const gone = context.remove(moved, moved[0].id)
  assert.equal(gone.length, 3)
  assert.equal(gone.filter(w => w.kind === 'music').length, 0)
  const still = context.resize(gone, gone[0].id, 'large')
  assert.equal(still[0].size, gone[0].size)
})

test('tablet widgets reject malicious content, duplicates and limit count', () => {
  const invalid = [
    {id:'../../escape',kind:'notes',size:'small'},
    {id:'valid',kind:'<script>',size:'small'},
    {id:'valid2',kind:'clock',size:'huge'},
    {id:'same',kind:'notes',size:'small'},
    {id:'same',kind:'weather',size:'small'}
  ]
  const clean = context.normalized(invalid)
  assert.equal(clean.length, 1)
  assert.equal(clean[0].id, 'same')
  let list = []
  for(let i=0;i<30;i++)list = context.add(list,'notes','small')
  assert.equal(list.length,20)
  assert.equal(new Set(Array.from(list,x=>x.id)).size,20)
})

test('tablet home and tablet shortcuts are integrated in one desktop shell', () => {
  const shell = read('shell/shell.qml')
  const bar = read('shell/MenuBar.qml')
  const dockSettings = read('apps/settings/panes/DockPane.qml')
  assert.match(shell,/TabletHome \{/)
  assert.match(shell,/target: "tablet"/)
  assert.match(shell,/root\.focusedTabletHome\(\)/)
  assert.match(source,/WlrLayershell\.layer: WlrLayer\.Bottom/)
  assert.match(source,/visible: Prefs\.tabletMode/)
  assert.match(source,/readonly property int iconColumns: portrait \? 4/)
  assert.match(source,/objectName: "tabletWidgetPicker"/)
  assert.match(source,/objectName: "tabletAppColumns"/)
  assert.match(source,/objectName: "tabletSwipePages"/)
  assert.match(source,/snapMode: ListView.SnapOneItem/)
  assert.match(source,/objectName: "tabletPageDots"/)
  assert.match(source,/function appsForPage\(index\)/)
  assert.match(source,/spotlight", "search"/)
  assert.match(source,/function dropWidget\(/)
  assert.match(source,/tablet\.iconFor\(appTile\.modelData\)/)
  assert.match(bar,/objectName: "tabletControlCenterGesture"/)
  assert.match(bar,/acceptedDevices: PointerDevice\.TouchScreen/)
  assert.match(bar,/translation\.y < 58/)
  assert.match(bar,/bar\.controlCenter\.toggle\(\)/)
  assert.match(dockSettings,/Customize Home…/)
  assert.match(dockSettings,/ipc", "call", "tablet", "edit"/)
})

test('tablet icon columns and widget sizing remain touch-friendly', () => {
  for(const [w,h] of [[390,844],[600,800],[768,1024],[1024,768],[1366,768],[1920,1080]]){
    const portrait = w < h
    const columns = portrait ? 4 : Math.max(5,Math.min(7,Math.floor((w-72)/154)))
    const width = Math.max(300,Math.min(1100,w-(portrait?40:76)))
    const cellWidth = (width-(columns-1)*10)/columns
    const iconSize = Math.max(60,Math.min(76,(width-(columns-1)*14)/columns-24))
    assert.ok(iconSize <= cellWidth, 'icon fits: '+w+'x'+h)
    assert.ok(columns>=4&&columns<=7)
    assert.ok(Math.min(1,width/344)>0, 'medium widget scales to portrait width')
  }
})

test('wallpaper-first tablet Home supports app long-press editing', () => {
  assert.match(source, /firstPageCapacity: iconColumns \* 2/)
  assert.match(source, /onPressAndHold: tablet\.editing = true/)
  assert.match(source, /style: Text\.Outline/)
  assert.doesNotMatch(source, /text: tablet\.editing && page\.index === 0 \? "Customize Home"/)
})

test('tablet lock screen uses live MPRIS data', () => {
  const lock = read('shell/components/LockSurface.qml')
  const session = read('shell/LockScreen.qml')
  assert.match(lock, /objectName: "tabletLockNowPlaying"/)
  assert.match(lock, /objectName: "tabletLockHomeIndicator"/)
  assert.match(lock, /root\.player\.togglePlaying\(\)/)
  assert.match(session, /Quickshell\.Services\.Mpris/)
  assert.match(session, /tabletMode: Prefs\.tabletMode/)
})

test('tablet status hides desktop menus but retains the Control Center gesture', () => {
  const bar = read('shell/MenuBar.qml')
  assert.match(bar, /objectName: "tabletStatusBar"/)
  assert.match(bar, /id: titlesRow\n        visible: !Prefs\.tabletMode/)
  assert.match(bar, /objectName: "tabletControlCenterGesture"/)
  assert.match(bar, /Qt\.formatDateTime\(tabletClock\.date/)
})
