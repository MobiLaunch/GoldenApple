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

test('Music UI exposes editable playlists and queue controls', () => {
  const app = readFileSync(new URL('../apps/music.qml', import.meta.url),'utf8');
  const library = readFileSync(new URL('../apps/music/Library.qml', import.meta.url),'utf8');
  const album = readFileSync(new URL('../apps/music/AlbumPage.qml', import.meta.url),'utf8');
  for (const fragment of [
    'id: nameSheet', 'id: pickerSheet', 'id: managerSheet',
    'id: deletePlaylistConfirm', 'musicLib.mutatePlaylist("add"',
    'app.playlistEdit("remove"', 'app.playlistEdit("move"',
    'audio.moveUpcoming(modelData.i, -1)', 'audio.moveUpcoming(modelData.i, 1)',
    'audio.removeUpcoming(modelData.i)', 'editablePlaylist: true',
    'onManagePlaylist: app.openPlaylistManager()'
  ]) assert.ok(app.includes(fragment), fragment);
  assert.ok(library.includes('playlistHelper'));
  assert.ok(library.includes('postCreateAdd'));
  assert.ok(album.includes('signal managePlaylist()'));
});

test('Music Playing Next reorders, removes and appends safely under shuffle', () => {
  let saves=0, loads=0;
  const c=context('apps/music/Player.qml',
    ['futureOrder','moveUpcoming','removeUpcoming','playLater','playNext'],{
      queue:[{title:'A'},{title:'B'},{title:'C'},{title:'D'}],
      order:[2,0,3,1],index:2,
      scheduleSave(){saves++},
      playList(l,i){this.queue=l;this.index=i;this.order=l.map((_,j)=>j);loads++}
    });
  assert.deepEqual(Array.from(c.futureOrder()),[0,3,1]);
  assert.equal(c.moveUpcoming(1,-1),true);
  assert.deepEqual(Array.from(c.order),[2,0,1,3]);
  assert.equal(c.moveUpcoming(2,1),false,'current track must not move');
  assert.equal(c.moveUpcoming(0,-1),false,'future track cannot move before current');
  assert.equal(c.removeUpcoming(1),true);
  assert.deepEqual(Array.from(c.order),[1,0,2]);
  assert.equal(c.index,1,'the same playing track is preserved after index adjustment');
  assert.equal(c.queue[c.index].title,'C');
  assert.equal(c.queue.length,3);
  assert.equal(c.removeUpcoming(1),false,'cannot remove current');
  const next={title:'Next'},last={title:'Last'};
  c.playNext(next);
  assert.deepEqual(Array.from(c.order),[1,3,0,2]);
  assert.equal(c.queue[3],next);
  c.playLater(last);
  assert.deepEqual(Array.from(c.order),[1,3,0,2,4]);
  assert.equal(c.queue[4],last);
  assert.equal(loads,0,'editing future tracks never restarts audio');
  assert.ok(saves>=4,'changes are persisted');
});

test('Music inserts first queued track when playback is empty', () => {
  const c=context('apps/music/Player.qml',['playNext','playLater'],{
    current:null,playList(list,index){this.queue=list;this.index=index},
  });
  c.playNext({title:'Solo'});
  assert.equal(c.index,0);
  assert.equal(c.queue[0].title,'Solo');
  c.current=null;
  c.playLater({title:'Another'});
  assert.equal(c.queue[0].title,'Another');
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

test('failed note save preserves the original, draft and dirty state; a saved one is renamed without replacing', () => {
  const state={dirty:true,loadedPath:'/notes/Old.md',loading:false,saveTimer:{stop(){},restart(){}},
    markdown:()=> '# New\nBody',Md:{fileName:t=>t+'.md'},root:'/notes',fresh:false,lastSaved:'# Old',
    onDisk:()=> '# Old',notice:'',renaming:false,
    writer:{setText(){}},file:{path:'/notes/Old.md'},writeOk:false,saveError:'',
    renamer:{running:false},Qt:{resolvedUrl:u=>'file:///apps/notes/'+u},
    saveFailed(){},saved(){}};
  const c=context('apps/notes/NoteEditor.qml',['save'],state);
  assert.equal(c.save(),false);
  assert.equal(c.loadedPath,'/notes/Old.md'); assert.equal(c.dirty,true);
  assert.equal(c.renamer.running,false,'no rename for a note that was not saved'); assert.ok(c.saveError);
  c.writer.setText=()=>{c.writeOk=true};
  assert.equal(c.save(),true);
  assert.equal(c.dirty,false); assert.equal(c.saveError,'');
  assert.equal(c.loadedPath,'/notes/Old.md','renamed only once trash.py has done it');
  assert.equal(c.renamer.running,true);
  assert.deepEqual([...c.renamer.command.slice(2)],['rename','/notes','/notes/Old.md','New.md']);
});

test('a note changed elsewhere is never written over', () => {
  const state={dirty:true,loadedPath:'/notes/A.md',loading:false,saveTimer:{stop(){}},
    markdown:()=> '# A\nmine',Md:{fileName:t=>t+'.md'},root:'',fresh:false,lastSaved:'# A\nold',
    onDisk:p=> p==='/notes/A.md' ? '# A\ntheirs' : null,notice:'',renaming:false,
    writer:{path:'',setText(){state.writeOk=true}},file:{path:'/notes/A.md'},writeOk:false,saveError:'',
    renamer:{running:false},saveFailed(){},saved(){}};
  const c=context('apps/notes/NoteEditor.qml',['save'],state);
  assert.equal(c.save(),true);
  assert.equal(c.writer.path,'/notes/A 2.md');
  assert.equal(c.loadedPath,'/notes/A 2.md'); assert.match(c.notice,/changed somewhere else/);
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

test('LCode themes: complete colour sets, custom copies and placeholder-aware highlighting', () => {
  const s = library('apps/lib/syntax.js');
  const ids = new Set();
  for (const t of s.THEMES) {
    for (const k of s.THEME_KEYS) assert.ok(typeof t[k] === 'string' && (t[k] === '' ? k === 'selection' : /^#[0-9a-f]{6}$/i.test(t[k])), `${t.id}.${k}`);
    assert.ok(!ids.has(t.id), t.id); ids.add(t.id);
    assert.equal(typeof t.dark, 'boolean');
  }
  assert.equal(s.resolveTheme('nope', true, []).id, 'default-dark');
  assert.equal(s.resolveTheme('nope', false, []).id, 'default-light');
  const copy = s.duplicateTheme(s.themeById('midnight'), []);
  assert.equal(copy.name, 'Midnight copy'); assert.equal(copy.builtIn, false); assert.notEqual(copy.id, 'midnight');
  assert.equal(s.duplicateTheme(s.themeById('midnight'), [copy]).name, 'Midnight copy 2');
  assert.equal(s.resolveTheme(copy.id, true, [copy]).id, copy.id);
  // A theme object colours the line; booleans keep the default themes.
  assert.match(s.html('let a', 0, 'swift', s.themeById('midnight'), 4), /#d31895/);
  assert.match(s.html('let a', 0, 'swift', true, 4), new RegExp(s.PALETTES.dark.keyword));
  // <#name#> placeholders read as plain names, even with # comments around.
  const runs = s.tokenize('if <#condition#>: # done', 0, 'python').runs;
  assert.equal(runs.map(r => r[1]).join(''), 'if <#condition#>: # done');
  assert.ok(runs.some(r => r[0] !== 'comment' && r[1].includes('<#condition#>')));
  assert.match(s.html('x = <#value#>', 0, 'python', false, 4), /<font color="#00000000">&lt;#<\/font>value/);
});

test('LCode key bindings: display, recording, conflicts and every command handled', () => {
  const c = library('apps/lcode/commands.js');
  assert.equal(c.display('Ctrl+Shift+K'), '⇧⌘K');
  assert.equal(c.display('Ctrl+Alt+S'), '⌥⌘S');
  assert.equal(c.display('Ctrl++'), '⌘+');
  assert.equal(c.display('Ctrl+Space'), '⌘Space');
  const CTRL = 0x04000000, SHIFT = 0x02000000;
  assert.equal(c.sequenceFor(0x45, CTRL | SHIFT, 'E'), 'Ctrl+Shift+E');
  assert.equal(c.sequenceFor(0x01000021, CTRL, ''), '');           // Ctrl alone
  assert.equal(c.sequenceFor(0x01000030 + 4, 0, ''), 'F5');
  // Taking ⌘S for Save All leaves Save unbound.
  const next = c.bind('saveAll', 'Ctrl+S', {});
  assert.deepEqual([...c.keysFor('saveAll', next)], ['Ctrl+S']);
  assert.deepEqual([...c.keysFor('save', next)], []);
  assert.deepEqual([...c.conflicts('Ctrl+S', 'save', next).map(x => x.id)], ['saveAll']);
  assert.deepEqual([...c.keysFor('save', c.reset('save', next))], ['Ctrl+S']);
  assert.ok(c.isCustomized('save', next) && !c.isCustomized('run', next));
  // No two commands share a default key.
  const seen = {};
  for (const cmd of c.COMMANDS) for (const k of cmd.keys) { assert.ok(!seen[k], `${k}: ${seen[k]} and ${cmd.id}`); seen[k] = cmd.id; }
  // The project window performs every command.
  const ws = readFileSync(new URL('../apps/lcode/Workspace.qml', import.meta.url), 'utf8');
  for (const cmd of c.COMMANDS) assert.ok(ws.includes(`case "${cmd.id}":`), cmd.id);
  // Behaviors: defaults, overridden one key at a time.
  assert.equal(c.behavior('buildFailed', {}).navigator, 'issues');
  const b = c.behavior('buildFailed', { buildFailed: { notify: true } });
  assert.equal(b.notify, true); assert.equal(b.reveal, true);
});

test('LCode completion: names, keywords and snippets with placeholders', () => {
  const syntax = library('apps/lib/syntax.js');
  const src = readFileSync(new URL('../apps/lcode/completion.js', import.meta.url), 'utf8')
    .replace('.pragma library', '').replace(/^\.import .*$/m, '');
  const c = vm.createContext({ Syntax: syntax }); vm.runInContext(src, c);
  const text = 'struct Greeter {\n    let greeting = "hi"\n    func greet() {}\n}\ngre';
  const r = c.complete(text, text.length, 'swift', {});
  assert.equal(r.prefix, 'gre'); assert.equal(r.start, text.length - 3);
  const titles = r.items.map(i => i.title);
  assert.ok(titles.includes('greet') && titles.includes('greeting') && titles.includes('Greeter'), titles.join());
  assert.equal(r.items.find(i => i.title === 'greet').kind, 'function');
  assert.equal(r.items.find(i => i.title === 'Greeter').kind, 'type');
  // Prefix matches beat letters-in-order; keywords and snippets come too.
  const g = c.complete('gu', 2, 'swift', {}).items;
  assert.ok(g.some(i => i.kind === 'snippet' && i.title === 'guard'));
  assert.ok(g.some(i => i.kind === 'keyword' && i.title === 'guard'));
  assert.equal(c.complete('x.', 2, 'swift', {}).items.length, 0);
  assert.ok(c.complete('x ', 2, 'swift', { explicit: true }).items.length > 10);
  // Your snippets, for their language.
  const own = [{ id: 'a', title: 'Fetch', trigger: 'fetchjson', language: 'python', body: 'x' }];
  assert.ok(c.complete('fetch', 5, 'python', { userSnippets: own }).items[0].own);
  assert.ok(!c.complete('fetch', 5, 'swift', { userSnippets: own }).items.some(i => i.own));
  // Expanding re-indents to the line and the indent unit.
  assert.equal(c.expand('if <#c#> {\n    <#s#>\n}', '\t', '\t'), 'if <#c#> {\n\t\t<#s#>\n\t}');
  assert.equal(c.expand('a\n    b', '  ', '  '), 'a\n    b');
  const ph = c.placeholders('a <#x#> b <#y#>');
  assert.deepEqual([...ph.map(p => p.name)], ['x', 'y']);
  assert.equal(c.nextPlaceholder('a <#x#> b <#y#>', 8).name, 'y');
  assert.equal(c.nextPlaceholder('a <#x#> b <#y#>', 15).name, 'x');     // wraps
  for (const [lang, list] of Object.entries(c.SNIPPETS))
    for (const s of list) assert.ok(s.trigger && s.title && s.body, `${lang} ${s.title}`);
});

test('LCode devices: your own Simulator devices', () => {
  const d = library('apps/lcode/devices.js');
  const all = d.all([{ id: 'custom-x', name: 'X', width: 5000, height: 10, tablet: true, style: 'home-button' }]);
  assert.equal(all.length, d.DEVICES.length + 1);
  const x = d.find('custom-x', [{ id: 'custom-x', name: 'X', width: 5000, height: 10, tablet: true, style: 'home-button' }]);
  assert.equal(x.width, 2048); assert.equal(x.height, 240); assert.equal(x.cutout, 'home-button');
  assert.ok(d.runTarget(x, 0).side >= 2048 - 1);
});

// Spotlight answers: arithmetic, conversions and Settings panes, from the shell's library.
function spotlightAnswers() {
  const src = readFileSync(new URL('../shell/spotlight/answers.js', import.meta.url), 'utf8').replace('.pragma library', '');
  const c = vm.createContext({}); vm.runInContext(src, c); return c;
}
test('Spotlight calculates, and leaves words and plain numbers alone', () => {
  const a = spotlightAnswers();
  for (const [q, shown] of [['2+2', '4'], ['12*(3+4)', '84'], ['2^10', '1,024'], ['sqrt(144)', '12'], ['20% of 150', '30'],
                            ['2x3', '6'], ['1/3', '0.3333333333'], ['1234567*3', '3,703,701'], ['-5+2', '-3']])
    assert.equal(a.calculate(q)?.display, shown, q);
  for (const q of ['photos', '42', '(1+2', '100/0', 'rm -rf', 'Messages']) assert.equal(a.calculate(q), null, q);
});
test('Spotlight converts units, and refuses mismatched kinds', () => {
  const a = spotlightAnswers();
  assert.equal(a.convert('5 km in mi').display, '3.11 mi');
  assert.equal(a.convert('100 c in f').display, '212 °F');
  assert.equal(a.convert('70 f to c').display, '21.11 °C');
  assert.equal(a.convert('3 cups in ml').display, '709.8 mL');
  assert.equal(a.convert('5 km in kg'), null);
  assert.equal(a.convert('5 apples to oranges'), null);
});
test('Spotlight finds Settings panes by name and by what people call them', () => {
  const a = spotlightAnswers();
  assert.equal(a.settings('dark mode')[0].pane, 'appearance');
  assert.equal(a.settings('brightness')[0].pane, 'displays');
  assert.equal(a.settings('wi')[0].pane, 'wifi');
  assert.equal(a.settings('x').length, 0);
});

function missionControl() {
  const src = readFileSync(new URL('../shell/missioncontrol/layout.js', import.meta.url), 'utf8').replace('.pragma library', '');
  const c = vm.createContext({}); vm.runInContext(src, c);
  return c;
}

test('Mission Control spreads windows without overlap, inside the area, never enlarged', () => {
  const { spread } = missionControl();
  const area = { x: 48, y: 186, width: 1344, height: 606 };
  const windows = [
    { x: 90, y: 80, w: 880, h: 560 }, { x: 640, y: 170, w: 700, h: 520 },
    { x: 220, y: 400, w: 780, h: 430 }, { x: 1010, y: 60, w: 400, h: 330 },
  ];
  const out = spread(windows, area, 28, 26);
  assert.equal(out.length, windows.length);
  out.forEach((r, i) => {
    assert.ok(r.x >= area.x - 0.5 && r.y >= area.y - 0.5, `window ${i} starts inside`);
    assert.ok(r.x + r.width <= area.x + area.width + 0.5 && r.y + r.height <= area.y + area.height + 0.5, `window ${i} ends inside`);
    assert.ok(r.width <= windows[i].w + 0.01 && r.height <= windows[i].h + 0.01, `window ${i} isn't enlarged`);
    assert.ok(Math.abs(r.width / r.height - windows[i].w / windows[i].h) < 0.01, `window ${i} keeps its shape`);
  });
  for (let i = 0; i < out.length; i++) for (let j = i + 1; j < out.length; j++) {
    const a = out[i], b = out[j];
    const apart = a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y;
    assert.ok(apart, `windows ${i} and ${j} don't overlap`);
  }
  // Files (left) stays left of Weather (right) in the top row.
  assert.ok(out[0].x < out[3].x);
  // One small window isn't blown up to fill the screen.
  const [one] = spread([{ x: 0, y: 0, w: 400, h: 300 }], area);
  assert.equal(one.width, 400); assert.equal(one.height, 300);
  assert.equal(spread([], area).length, 0);
});

test('Mission Control arrow keys move to the closest window in the next row', () => {
  const { nearest } = missionControl();
  const rects = [{ x: 0, y: 0, width: 100, height: 80 }, { x: 200, y: 0, width: 100, height: 80 },
                 { x: 20, y: 200, width: 100, height: 80 }, { x: 220, y: 200, width: 100, height: 80 }];
  assert.equal(nearest(rects, 1, 1), 3);
  assert.equal(nearest(rects, 2, -1), 0);
  assert.equal(nearest(rects, 0, -1), 0);
  assert.equal(nearest(rects, -1, 1), 0);
});

test('Calendar view switching, month-end clamping and week/day navigation', () => {
  const src = readFileSync(new URL('../apps/calendar.qml', import.meta.url), 'utf8');
  for (const marker of [
    'checked: cal.viewMode === "month"', 'checked: cal.viewMode === "week"',
    'checked: cal.viewMode === "day"', 'id: agendaRow',
    'visible: cal.viewMode === "month"',
    'model: agendaDay.dayEvents', 'cal.requestEdit(eventTile.modelData)',
    'sequence: "Ctrl+1"', 'sequence: "Ctrl+2"', 'sequence: "Ctrl+3"',
    'sequence: "Ctrl+T"', 'sequence: "Ctrl+N"'
  ]) assert.ok(src.includes(marker), marker);
  const c = context('apps/calendar.qml', ['changeView', 'shiftRange'], {
    viewMode:'month', selectedDate:new Date(2026, 9, 31),
    visibleMonth:new Date(2026, 9, 1), year:2026, month:9
  });
  c.shiftRange(1);
  assert.equal(c.selectedDate.getMonth(),10);
  assert.equal(c.selectedDate.getDate(),30,'Oct 31 clamps to November 30');
  c.changeView('week');
  assert.equal(c.viewMode,'week');
  c.shiftRange(1);
  assert.equal(c.selectedDate.getMonth(),11,'week crosses into December');
  assert.equal(c.selectedDate.getDate(),7);
  c.changeView('day');
  c.shiftRange(-1);
  assert.equal(c.selectedDate.getDate(),6);
  c.changeView('not-a-view');
  assert.equal(c.viewMode,'day','ignore unknown view');
});

test('Calendar refresh requests queue behind an active load', () => {
  const loadProc={running:true};
  const c=context('apps/calendar.qml',['reload'],{loadProc,reloadPending:false});
  c.reload();
  assert.equal(c.reloadPending,true,'a concurrent reload is not silently lost');
  loadProc.running=false;
  c.reload();
  assert.equal(loadProc.running,true,'an idle refresh starts immediately');
  const source=readFileSync(new URL('../apps/calendar.qml',import.meta.url),'utf8');
  assert.ok(source.includes('if (cal.reloadPending)'), 'onExited drains pending refresh');
  assert.ok(source.includes('Qt.callLater(() => cal.reload())'), 'refresh is not restarted during onExited');
});

test('Files drops: move within Files, copy from other apps, Trash, never into itself', () => {
  const ops = [];
  const c = context('apps/files.qml', ['pathsOf', 'accepts', 'dropOn'], {
    busy:false, say(){},
    runOperation: (args, kind) => ops.push([kind, ...args]),
    startTransfer: (paths, dest, mode) => ops.push(['transfer', ...paths, dest, mode]),
    Qt: { MoveAction: 2, CopyAction: 1 },
  });
  const urls = ['file:///home/j/Documents/Plan%20B.txt', 'file:///home/j/Documents/Project', 'https://example.com/x'];
  assert.deepEqual(Array.from(c.pathsOf(urls)), ['/home/j/Documents/Plan B.txt', '/home/j/Documents/Project']);
  assert.equal(c.accepts({ urls }, '/home/j/Desktop'), true);
  assert.equal(c.accepts({ urls }, '/home/j/Documents/Project'), false, 'not onto itself');
  assert.equal(c.accepts({ urls }, '/home/j/Documents/Project/Sub'), false, 'not into its own contents');
  assert.equal(c.accepts({ urls: ['https://example.com/x'] }, '/home/j/Desktop'), false, 'only files');

  const drop = (source, proposedAction) => {
    const d = { urls: [urls[0]], source, proposedAction, accepted: null };
    d.accept = (a) => { d.accepted = a; };
    return d;
  };
  let d = drop({}, 2);
  c.dropOn(d, '/home/j/Desktop');
  assert.deepEqual(ops.pop(), ['transfer', '/home/j/Documents/Plan B.txt', '/home/j/Desktop', 'auto']);
  assert.equal(d.accepted, 2, 'a drag from Files moves');
  d = drop(null, 2);
  c.dropOn(d, '/home/j/Desktop');
  assert.deepEqual(ops.pop(), ['transfer', '/home/j/Documents/Plan B.txt', '/home/j/Desktop', 'copy']);
  assert.equal(d.accepted, 1, "another app's file is copied, so that app keeps its own");
  d = drop({}, 2);
  c.dropOn(d, 'trash:');
  assert.deepEqual(ops.pop(), ['trash', 'trash', '/home/j/Documents/Plan B.txt']);
});

test('Screenshots: grim gets the right region and a Mac-style file name, quoted safely', async () => {
  const { execFileSync } = await import('node:child_process');
  const { mkdtempSync, writeFileSync, chmodSync, readFileSync: read, existsSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const dir = mkdtempSync(tmpdir() + '/gg-shot-');
  // A grim that writes down its arguments and makes the file it's given.
  writeFileSync(dir + '/grim', '#!/bin/sh\nprintf "%s\\n" "$@" > "$GG_ARGS"\nfor a; do last=$a; done\n[ "$last" = - ] && printf png || : > "$last"\n');
  writeFileSync(dir + '/wl-copy', '#!/bin/sh\ncat > "$GG_CLIP"\n');
  chmodSync(dir + '/grim', 0o755); chmodSync(dir + '/wl-copy', 0o755);
  const shooter = {};
  const state = {
    toClipboard: false, saveTo: 'desktop', showPointer: false, lastFile: '',
    pendingRect: { x: 100.4, y: 50, width: 640, height: 400 }, screen: { name: 'DP-2' },
    monitor: { x: 1440, y: 0 }, shooter, Quickshell: { env: () => dir },
    Qt: { formatDateTime: () => '2026-10-04 at 9.41.12 PM' },
  };
  const c = context('shell/Screenshot.qml', ['home', 'folder', 'stamp', 'geometry', 'capture'], state);
  const run = () => execFileSync(shooter.command[0], shooter.command.slice(1),
    { env: { ...process.env, PATH: dir + ':' + process.env.PATH, GG_ARGS: dir + '/args', GG_CLIP: dir + '/clip' } });

  c.capture();
  run();
  const file = dir + '/Desktop/Screenshot 2026-10-04 at 9.41.12 PM.png';
  assert.equal(c.lastFile, file);
  assert.ok(existsSync(file), 'saved on the Desktop, spaces and all');
  assert.deepEqual(read(dir + '/args', 'utf8').trim().split('\n'), ['-g', '1540,50 640x400', file]);

  c.pendingRect = null; c.showPointer = true; c.saveTo = 'pictures';
  c.capture(); run();
  assert.deepEqual(read(dir + '/args', 'utf8').trim().split('\n'),
    ['-c', '-o', 'DP-2', dir + '/Pictures/Screenshot 2026-10-04 at 9.41.12 PM.png'], 'the whole screen, with the pointer');

  c.toClipboard = true;
  c.capture(); run();
  assert.equal(c.lastFile, '', 'nothing saved');
  assert.equal(read(dir + '/clip', 'utf8'), 'png', 'the picture goes to the clipboard');
});

test('Screen recording: wf-recorder records the selection or the screen to a named file', () => {
  const recorder = {};
  const c = context('shell/Screenshot.qml', ['home', 'folder', 'stamp', 'geometry', 'startRecording'], {
    saveTo: 'documents', lastFile: '', pendingRect: { x: 0, y: 30, width: 800, height: 600 },
    screen: { name: 'eDP-1' }, monitor: { x: 0, y: 0 }, recorder, Quickshell: { env: () => '/home/j' },
    Qt: { formatDateTime: () => '2026-10-04 at 9.41.12 PM' },
  });
  c.startRecording();
  assert.deepEqual(Array.from(recorder.command), ['wf-recorder', '-y', '-f', '/home/j/Documents/Screen Recording 2026-10-04 at 9.41.12 PM.mp4', '-g', '0,30 800x600']);
  assert.equal(recorder.running, true);
});

test('Dock: dragging an icon reorders, removes or adds it', () => {
  const { orderAfter } = context('shell/Dock.qml', ['orderAfter'], {});
  const ids = ['files', 'web', 'mail', 'notes'];
  assert.deepEqual(Array.from(orderAfter(ids, 'files', 2)), ['web', 'mail', 'files', 'notes'], 'moved right');
  assert.deepEqual(Array.from(orderAfter(ids, 'notes', 0)), ['notes', 'files', 'web', 'mail'], 'moved to the front');
  assert.deepEqual(Array.from(orderAfter(ids, 'web', -1)), ['files', 'mail', 'notes'], 'dragged off: removed');
  assert.deepEqual(Array.from(orderAfter(ids, 'music', 1)), ['files', 'music', 'web', 'mail', 'notes'], 'a running app kept');
  assert.deepEqual(Array.from(orderAfter(ids, 'mail', 99)), ['files', 'web', 'notes', 'mail'], 'past the end: last');
  assert.deepEqual(Array.from(orderAfter(ids, '', -1)), ids, 'nothing dragged');
});

test('Desktop widgets: snap to free cells, never overlap, fill down the left first', () => {
  const L = library('shell/widgets/layout.js');
  const plain = (r) => JSON.parse(JSON.stringify(r));
  const g = L.grid(1440, 900);
  assert.deepEqual(plain(g), { cols: 7, rows: 4 });
  const items = plain(L.defaults());
  // The defaults: calendar and clock side by side, the weather under them.
  assert.ok(items.every((a) => items.every((b) => a === b || !L.overlaps(a, b))));
  // A new small widget goes under the weather, a medium one too.
  assert.deepEqual(plain(L.firstFree(items, 'small', g)), { col: 0, row: 2 });
  assert.deepEqual(plain(L.firstFree(items, 'large', g)), { col: 0, row: 2 });
  // Dropped onto the clock, the calendar lands in the nearest free cell instead.
  const cal = items[0];
  assert.equal(L.fits(items, cal, 1, 0, g), false);
  const at = plain(L.nearest(items, cal, 1, 0, g));
  assert.ok(L.fits(items, cal, at.col, at.row, g));
  assert.equal(Math.abs(at.col - 1) + Math.abs(at.row - 0), 1);
  // Its own cell is free for itself; off the grid is not.
  assert.equal(L.fits(items, cal, 0, 0, g), true);
  assert.equal(L.fits(items, cal, -1, 0, g), false);
  assert.equal(L.fits(items, { id: 'x', size: 'medium' }, 6, 3, g), false);
  // Dragging snaps to the closest cell.
  assert.deepEqual(plain(L.cellAt(L.x(2) + 60, L.y(1) - 70)), { col: 2, row: 1 });
  // Growing the calendar to medium would cover the clock: it moves to fit.
  const big = plain(L.resized(items, cal, 'medium', g));
  assert.equal(big.size, 'medium');
  assert.ok(L.fits(items, big, big.col, big.row, g));
  assert.deepEqual(plain(L.pixels('medium')), { width: 344, height: 164 });
  // A full desktop has no room.
  const full = [];
  for (let c = 0; c < g.cols; c++) for (let r = 0; r < g.rows; r++) full.push({ id: c + ':' + r, size: 'small', col: c, row: r });
  assert.equal(L.firstFree(full, 'small', g), null);
});

// Calculator (apps/calculator/engine.js): precedence and parentheses,
// scientific functions, 64-bit Programmer arithmetic without BigInt, and
// unit conversion.
function calculator() {
  const src = readFileSync(new URL('../apps/calculator/engine.js', import.meta.url), 'utf8').replace('.pragma library', '');
  const c = vm.createContext({ BigInt: undefined }); vm.runInContext(src, c);   // as in Qt: no BigInt
  return c;
}

test('calculator evaluates with precedence, parentheses and powers', () => {
  const c = calculator();
  assert.equal(c.evaluate([2, '+', 3, '*', 4]), 14);
  assert.equal(c.evaluate(['(', 2, '+', 3, ')', '*', 4]), 20);
  assert.equal(c.evaluate([2, '^', 3, '^', 2]), 512, 'powers associate to the right');
  assert.equal(c.evaluate([27, 'root', 3]), 3);
  assert.equal(c.evaluate([1.5, 'EE', 3]), 1500);
  assert.equal(c.evaluate([2, 'rpow', 3]), 9, 'yˣ: y to the power of x');
  assert.equal(c.evaluate([2, '+', 3, '*']), 5, 'a trailing operator is dropped');
  assert.equal(c.evaluate(['(', 2, '+', 3, '*', 2]), 8, 'open parentheses close themselves');
  assert.ok(Number.isNaN(c.evaluate([1, '/', 0])));
  assert.equal(c.format(1 / 3), '0.333333333');
  assert.equal(c.format(1234567), '1,234,567');
  assert.equal(c.format(1e10), '1e10');
  assert.equal(c.format(Math.PI, 12), '3.14159265359');
});

test('calculator scientific functions, in degrees or radians', () => {
  const c = calculator();
  assert.equal(c.unary('sin', 30, false).toFixed(12), '0.500000000000');
  assert.equal(c.unary('sin', 180, false), 0, 'no 1.2e-16');
  assert.equal(c.unary('cos', 90, false), 0);
  assert.ok(Number.isNaN(c.unary('tan', 90, false)));
  assert.equal(c.unary('sin', Math.PI / 2, true), 1);
  assert.equal(c.unary('asin', 1, false), 90);
  assert.equal(c.unary('fact', 5), 120);
  assert.ok(Number.isNaN(c.unary('fact', 2.5)));
  assert.equal(c.unary('log10', 1000), 3);
  assert.equal(c.unary('cbrt', -8), -2);
  assert.ok(Number.isNaN(c.unary('ln', 0)));
});

test('calculator programmer mode: exact 64-bit arithmetic without BigInt', () => {
  const c = calculator();
  const max = c.parseInt64('FFFFFFFFFFFFFFFF', 16);
  assert.equal(c.toBase(max, 10), '18,446,744,073,709,551,615');
  assert.equal(c.toBase(c.add(max, c.u64(1)), 16), '0', 'wraps at 64 bits');
  const f = c.parseInt64('FFFFFFFF', 16);
  assert.equal(c.toBase(c.mul(f, f), 16), 'FFFF FFFE 0000 0001');
  const [q, r] = c.divmod(c.u64(100), c.u64(7));
  assert.equal(c.toBase(q, 10), '14'); assert.equal(c.toBase(r, 10), '2');
  assert.equal(c.divmod(c.u64(1), c.u64(0)), null);
  assert.equal(c.toBase(c.punary('twos', c.u64(1)), 16), 'FFFF FFFF FFFF FFFF');
  assert.equal(c.toBase(c.punary('rol', c.parseInt64('8000000000000000', 16)), 16), '1');
  assert.equal(c.toBase(c.punary('flipb', c.parseInt64('1234', 16)), 16), '3412');
  assert.equal(c.toBase(c.pevaluate([c.u64(2), '+', c.u64(3), '*', c.u64(4)]), 10), '14');
  assert.equal(c.toBase(c.pevaluate([c.u64(1), 'shl', c.u64(4), 'or', c.u64(1)]), 10), '17');
  assert.equal(c.toBase(c.parseInt64('777', 8), 10), '511');
  assert.equal(c.toBase(c.u64(10), 2), '1010');
  assert.equal(c.bit(c.u64(5), 2), 1);
  assert.equal(c.toBase(c.toggleBit(c.u64(0), 63), 16), '8000 0000 0000 0000');
});

test('calculator converts units', () => {
  const c = calculator();
  assert.equal(c.convert(100, 'Temperature', 'Celsius', 'Fahrenheit'), 212);
  assert.equal(Math.round(c.convert(32, 'Temperature', 'Fahrenheit', 'Kelvin') * 100) / 100, 273.15);
  assert.equal(c.convert(1, 'Length', 'Miles', 'Kilometers'), 1.609344);
  assert.equal(c.convert(1, 'Data', 'Gibibytes', 'Bytes'), 1073741824);
  assert.ok(c.categories().includes('Pressure'));
  assert.ok(Number.isNaN(c.convert(1, 'Length', 'Miles', 'Kilograms')));
});
