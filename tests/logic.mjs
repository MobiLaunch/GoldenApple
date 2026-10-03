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
  assert.deepEqual(['a/b.swift', 'x.py', 'PKGBUILD', 'x.qml', 'README'].map(s.languageFor), ['swift', 'python', 'hash', 'js', 'plain']);
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

function designModel() {
  const Catalog = library('apps/lib/kit/catalog.js');
  const c = vm.createContext({ Catalog });
  const src = readFileSync(new URL('../apps/lcode/design.js', import.meta.url), 'utf8')
    .replace('.pragma library', '').replace(/^\.import .*$/m, '');
  vm.runInContext(src, c);
  return c;
}
const plain = (x) => JSON.parse(JSON.stringify(x));

test('App Designer: catalog components, library pieces and actions are complete', () => {
  const { CATALOG } = library('apps/lib/kit/catalog.js');
  const kit = new Set(readFileSync(new URL('../apps/lib/kit/qmldir', import.meta.url), 'utf8').split('\n')
    .map((l) => l.split(' ')[0]).filter(Boolean));
  for (const [type, c] of Object.entries(CATALOG.components)) {
    assert.ok(kit.has(type), `${type} is a Kit component`);
    assert.ok(c.title && c.symbol && c.detail && Array.isArray(c.fields), type);
    for (const t of c.templates || []) assert.ok(t in (c.defaults || {}) || c.fields.some((f) => f.key === t), `${type}.${t}`);
    if (c.bind) assert.ok(['text', 'number', 'bool', 'list'].includes(c.bind.type), type);
  }
  for (const e of CATALOG.library) if (!e.section) assert.ok(CATALOG.components[e.type], e.title);
  assert.deepEqual(plain(CATALOG.actions.map((a) => a.do).sort()), ['alert', 'append', 'back', 'clear', 'copy', 'increment', 'navigate',
    'notify', 'openUrl', 'quit', 'removeItem', 'run', 'script', 'set', 'toggle']);
});

test('App Designer: editing a design never changes the old one (undo is snapshots)', () => {
  const D = designModel();
  const doc = D.parse(JSON.stringify({ app: { name: 'T' }, state: [], screens: [{ id: 'home', title: 'Home',
    root: { id: 'n1', type: 'VStack', props: {}, children: [{ id: 'n2', type: 'Text', props: { text: 'Hi' } }] } }] }));
  const before = JSON.stringify(doc);
  const card = D.createNode(doc, { type: 'VStack', props: { padding: 18 }, children: [{ type: 'Text' }, { type: 'Button' }] });
  assert.deepEqual(plain([card.id, card.children[0].id, card.children[1].id]), ['n3', 'n4', 'n5']);
  assert.equal(card.children[1].props.buttonStyle, 'bordered');
  const d1 = D.insert(doc, 'n1', 0, card);
  assert.equal(JSON.stringify(doc), before);
  assert.deepEqual(plain(D.find(d1, 'n1').node.children.map((c) => c.id)), ['n3', 'n2']);
  // Move the text into the card, then try to move the card into itself.
  const d2 = D.move(d1, 'n2', 'n3', 1);
  assert.deepEqual(plain(D.pathTo(d2, 'n2')), ['n1', 'n3', 'n2']);
  assert.equal(D.move(d2, 'n3', 'n4', 0), d2);
  const dup = D.duplicate(d2, 'n4');
  assert.equal(dup.id, 'n6');
  assert.deepEqual(plain(D.find(dup.doc, 'n3').node.children.map((c) => c.id)), ['n4', 'n6', 'n2', 'n5']);
  const wrapped = D.embed(d2, 'n2', 'HStack');
  assert.equal(D.find(wrapped.doc, 'n2').parent.type, 'HStack');
  const unwrapped = D.unembed(wrapped.doc, wrapped.id);
  assert.equal(D.find(unwrapped, 'n2').parent.id, 'n3');
  assert.equal(D.find(D.remove(d2, 'n3'), 'n2'), null);
  assert.equal(D.find(D.remove(d2, 'n1'), 'n1').node.id, 'n1'); // the root stays
  const patched = D.update(d2, 'n2', { text: 'Bye', textStyle: null });
  assert.deepEqual(plain(D.find(patched, 'n2').node.props), { text: 'Bye' });
  assert.deepEqual(plain(D.insertionPoint(d2, 'home', 'n4')), { parent: 'n3', index: 1 });
  assert.deepEqual(plain(D.insertionPoint(d2, 'home', 'n3')), { parent: 'n3', index: 3 });
});

test('App Designer: renaming a variable follows it everywhere', () => {
  const D = designModel();
  let doc = D.parse(JSON.stringify({ app: {}, state: [{ name: 'count', type: 'number', value: 0 }], screens: [{ id: 'home', root: {
    id: 'n1', type: 'VStack', props: {}, children: [
      { id: 'n2', type: 'Text', props: { text: 'Count: {count}' } },
      { id: 'n3', type: 'Slider', props: { binding: 'count' } },
      { id: 'n4', type: 'Button', props: { visibleWhen: 'count' }, actions: { tap: [{ do: 'increment', var: 'count', by: 1 },
                                                                                   { do: 'alert', title: 'Now {count}' }] } }] } }] }));
  assert.equal(D.usesOf(doc, 'count').length, 3);
  doc = D.updateVariable(doc, 'count', { name: 'clicks' });
  assert.equal(D.find(doc, 'n2').node.props.text, 'Count: {clicks}');
  assert.equal(D.find(doc, 'n3').node.props.binding, 'clicks');
  assert.deepEqual(plain(D.find(doc, 'n4').node.actions.tap.map((a) => a.var || a.title)), ['clicks', 'Now {clicks}']);
  const added = D.addVariable(doc, 'list');
  assert.equal(added.name, 'items');
  assert.deepEqual(plain(D.variable(added.doc, 'items').value), []);
  assert.deepEqual(plain(D.initialValues(added.doc)), { clicks: 0, items: [] });
  const screen = D.addScreen(doc, 'About Us');
  assert.equal(screen.id, 'about-us');
  assert.equal(D.addScreen(screen.doc, 'About Us').id, 'about-us-2');
});

test('Kit: colours adapt to the appearance; templates fill in variables', () => {
  const K = library('apps/lib/kit/kit.js');
  const env = { dark: false, accent: '#ff375f', colors: { Brand: { light: '#112233', dark: '#445566' } } };
  assert.equal(K.color('accent', env), '#ff375f');
  assert.equal(K.color('red', env), '#ff3b30');
  assert.equal(K.color('red', { dark: true }), '#ff453a');
  assert.equal(K.color('Brand', env), '#112233');
  assert.equal(K.color('Brand', Object.assign({}, env, { dark: true })), '#445566');
  assert.equal(K.color('#80ffffff', env), '#80ffffff');
  assert.equal(K.color('', env, 'fallback'), 'fallback');
  assert.equal(K.alpha('#0a84ff', 0.5), '#800a84ff');
  assert.equal(K.interpolate('{count} of {todos} · {item.title}', { count: 2.5, todos: [1, 2, 3] }, { item: { title: 'Milk' } }), '2.5 of 3 · Milk');
  assert.equal(K.interpolate('{missing} stays', {}), '{missing} stays');
  assert.deepEqual(plain(K.references('Hi {name}, {item.title}')), ['name', 'item']);
  assert.deepEqual(plain(K.edges([1, 2, 3, 4])), { top: 1, right: 2, bottom: 3, left: 4 });
  assert.equal(K.place('trailing', 100, 30), 70);
  assert.equal(K.qtWeight(650), 700);
  assert.equal(K.fontSize('title', 0), 22);
});
