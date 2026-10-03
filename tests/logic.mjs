import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

// Execute actual QML JavaScript functions with deterministic service doubles.
function context(path, names, state) {
  const src = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const scope = vm.createContext(state);
  for (const name of names) {
    const match = src.match(new RegExp('^( +)function ' + name + '\\([^\\n]*', 'm'));
    assert.ok(match, `function ${name} exists`);
    const start = match.index + match[1].length;
    const line = src.slice(start).split('\n')[0];
    const end = line.trim().endsWith('}') ? start + line.length
      : src.indexOf('\n' + match[1] + '}', start) + match[1].length + 2;
    vm.runInContext(src.slice(start, end), scope);
  }
  return scope;
}

test('media paths preserve reserved characters and Unicode', () => {
  const src = readFileSync(new URL('../apps/lib/paths.js', import.meta.url), 'utf8').replace('.pragma library', '');
  const c = vm.createContext({}); vm.runInContext(src, c);
  for (const path of ['/home/a/Track #1?.mp3', '/home/a/100%/café.png', '/home/a/a b.mov']) {
    const u = new URL(c.fileUrl(path));
    assert.equal(u.hash, ''); assert.equal(u.search, '');
    assert.equal(decodeURIComponent(u.pathname), path);
  }
});
for (const [path, name, response] of [
  ['apps/weather.qml', 'geocode', n => ({results: [{name:n, latitude:1, longitude:2}]})],
  ['apps/maps.qml', 'search', n => ({features: [{name:n}]})]
]) {
  test(`${name}: stale requests and clear cannot repopulate results`, () => {
    const requests = [];
    const c = context(path, [name], {
      searchRevision: 0, results: [], searching: false,
      map: {lat:1, lon:2}, Api: {searchUrl:q=>q, place:x=>x}, url:(_,q)=>q,
      get: (...args) => requests.push(args.at(-1))
    });
    c[name]('old'); c[name]('new');
    requests[1](response('new')); requests[0](response('old'));
    assert.equal(c.results[0].name, 'new');
    c[name]('pending'); c[name](''); requests[2](response('pending'));
    assert.equal(c.results.length, 0); assert.equal(c.searching, false);
    c[name]('pending'); c.searchRevision++; requests[3](response('outdated before debounce'));
    assert.equal(c.results.length, 0);
  });
}

test('map fly-to bounds zoom, latitude and wraps either direction', () => {
  const c = context('apps/maps/SlippyMap.qml', ['wrapLon', 'setCenter', 'flyTo'], {
    lat:0, lon:0, zoom:12, Theme:{reduceMotion:true}, fly:{stop(){},start(){}}, latAnim:{},lonAnim:{},zoomAnim:{}
  });
  c.flyTo(90, -1260, 25);
  assert.equal(c.lat, 85); assert.equal(c.lon, -180); assert.equal(c.zoom, 19);
  c.flyTo(-90, 1081, -2);
  assert.equal(c.lat, -85); assert.equal(c.lon, 1); assert.equal(c.zoom, 2);
});

test('music queue clamps invalid indices and owns its array', () => {
  const c = context('apps/music/Player.qml', ['playList'], {queue:[], order:[], index:-1, shuffle:false, load(){}});
  const tracks = [{title:'a'}, {title:'b'}];
  c.playList(tracks, 99); assert.equal(c.index, 1);
  tracks.push({title:'c'}); assert.equal(c.queue.length, 2);
  c.playList([], 0); assert.equal(c.index, -1);
  c.playList(tracks, -1); assert.equal(c.index, 0);
});

test('latest route wins when travel mode changes during fetch', () => {
  const requests=[];
  const c=context('apps/maps.qml',['route'],{
    routeRevision:0, routing:false, routeFailed:false, routes:[], routeIndex:0,
    travel:'car',from:{},to:{},Api:{routeUrl:()=>''},get:(_,__,cb)=>requests.push(cb),
    map:{fit(){}}, win:{contentX:0},panelWidth:360
  });
  c.route(); c.travel='foot'; c.route();
  requests[1]({routes:[{id:'foot',geometry:{coordinates:[]}}]});
  requests[0]({routes:[{id:'car',geometry:{coordinates:[]}}]});
  assert.equal(c.routes[0].id,'foot');
});

test('failed note rename preserves the original, draft and dirty state', () => {
  const removed=[];
  const state={dirty:true,loadedPath:'/notes/Old.md',loading:false,saveTimer:{stop(){}},
    markdown:()=> '# New\nBody',taken:[],Md:{fileName:t=>t+'.md'},
    writer:{setText(){}},file:{path:'/notes/Old.md'},writeOk:false,saveError:'',
    saveFailed(){},Quickshell:{execDetached:args=>removed.push(args)},saved(){}};
  const c=context('apps/notes/NoteEditor.qml',['save'],state);
  assert.equal(c.save(),false);
  assert.equal(c.loadedPath,'/notes/Old.md'); assert.equal(c.dirty,true);
  assert.equal(removed.length,0); assert.ok(c.saveError);
  c.writer.setText=()=>{c.writeOk=true};
  assert.equal(c.save(),true);
  assert.equal(c.loadedPath,'/notes/New.md'); assert.equal(c.dirty,false);
  assert.equal(removed.length,1); assert.equal(removed[0].at(-1),'/notes/Old.md');
});

function library(path) {
  const c = vm.createContext({});
  vm.runInContext(readFileSync(new URL('../' + path, import.meta.url), 'utf8').replace('.pragma library', ''), c);
  return c;
}

test('LCode syntax: Swift runs, multi-line state and Xcode colours', () => {
  const s = library('apps/lib/syntax.js');
  const plain = (r) => JSON.parse(JSON.stringify(r));
  assert.deepEqual(plain(s.tokenize('let x = "a\\(b)" // hi', 0, 'swift')), {state: 0, runs: [
    ['keyword', 'let'], ['plain', ' '], ['plain', 'x'], ['plain', ' = '], ['string', '"a\\(b)"'], ['plain', ' '], ['comment', '// hi']]});
  assert.equal(s.tokenize('/* open', 0, 'swift').state, 1);
  assert.deepEqual(plain(s.tokenize('close */ let', 1, 'swift').runs[0]), ['comment', 'close */']);
  assert.deepEqual(plain(s.lineStates(['"""', 'text', '"""', 'x'], 'swift')), [0, 2, 2, 0]);
  assert.deepEqual(['a/b.swift', 'x.py', 'PKGBUILD', 'x.qml', 'README'].map(s.languageFor), ['swift', 'hash', 'hash', 'c', 'plain']);
  const html = s.html('\tlet a = 1 < 2', 0, 'swift', false, 4);
  assert.match(html, /^<font color="#262626">(&nbsp;){4}<\/font><b><font color="#9b2393">let<\/font><\/b>/);
  assert.match(html, /&nbsp;&lt;&nbsp;/);
  assert.notEqual(s.PALETTES.light.keyword, s.PALETTES.dark.keyword);
});

test('LCode syntax: document items and comment toggling', () => {
  const s = library('apps/lib/syntax.js');
  const items = s.symbols('import Foo\n// MARK: - Views\nstruct A: View {\n    @State private var x = 1\n' +
    '    func body() {}\n    private static func make() -> A {}\n}\nextension A {}\n');
  assert.deepEqual(JSON.parse(JSON.stringify(items)).map(i => `${i.line}:${i.kind}:${i.name}`),
    ['2:mark:Views', '3:struct:A', '5:func:body', '6:func:make', '8:extension:A']);
  const commented = s.toggleComment(['    a', '', '  b'], 'swift');
  assert.deepEqual([...commented], ['  //   a', '', '  // b']);
  assert.deepEqual([...s.toggleComment(commented, 'swift')], ['    a', '', '  b']);
  assert.deepEqual([...s.toggleComment(['x = 1'], 'hash')], ['# x = 1']);
  assert.equal(s.expandTabs('\ta\tb', 4), '    a   b');
});

test('LCode devices: Simulator displays fit portrait and landscape apps', () => {
  const d = library('apps/lcode/devices.js');
  for (const device of d.DEVICES) {
    const side = d.displaySide(device);
    for (const o of [0, 1]) {
      const t = d.runTarget(device, o);
      assert.equal(t.side, side, device.id);
      assert.ok(t.w > 0 && t.h > 0 && t.w <= side && t.h <= side, `${device.id} ${o}`);
      const screen = d.screenSize(device, o), inset = d.insets(device, o);
      assert.equal(t.w, screen.w - inset.left - inset.right);
      assert.equal(t.h, screen.h - inset.top - inset.bottom);
    }
  }
  assert.equal(d.byId('nope'), null);
});
