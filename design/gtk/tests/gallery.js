// A window with every common GTK 4 / libadwaita control, for checking the
// CitronOS theme in one screenshot.
//
//   gjs -m design/gtk/tests/gallery.js [main|menu|dialog|finder]
//
// main    sidebar + toolbar + boxed lists, buttons, switches, checks, entries
// menu    the same window with a popover menu open
// dialog  the same window with an alert dialog open
// finder  a Finder-like list (column view) with a selected row
import Gtk from 'gi://Gtk?version=4.0';
import Adw from 'gi://Adw?version=1';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import { programArgs } from 'system';

const MODE = programArgs[0] ?? 'main';
const has = (ns, name) => typeof ns[name] === 'function';

const app = new Adw.Application({ application_id: 'org.goldengate.Gallery', flags: Gio.ApplicationFlags.NON_UNIQUE });

function sidebar() {
  const list = new Gtk.ListBox({ css_classes: ['navigation-sidebar'] });
  const add = (icon, label) => {
    const box = new Gtk.Box({ spacing: 8 });
    box.append(new Gtk.Image({ icon_name: icon }));
    box.append(new Gtk.Label({ label, xalign: 0 }));
    const row = new Gtk.ListBoxRow({ child: box });
    list.append(row);
    return row;
  };
  const header = (label) => {
    const l = new Gtk.Label({ label, xalign: 0, css_classes: ['heading', 'dim-label'] });
    const row = new Gtk.ListBoxRow({ child: l, selectable: false, activatable: false });
    list.append(row);
  };
  header('Favourites');
  const first = add('user-home-symbolic', 'Home');
  add('user-desktop-symbolic', 'Desktop');
  add('folder-documents-symbolic', 'Documents');
  add('folder-download-symbolic', 'Downloads');
  header('Locations');
  add('drive-harddisk-symbolic', 'Macintosh HD');
  add('network-server-symbolic', 'Network');
  list.select_row(first);

  const view = new Adw.ToolbarView();
  view.add_top_bar(new Adw.HeaderBar({ show_title: false }));
  view.set_content(new Gtk.ScrolledWindow({ child: list, vexpand: true }));
  return view;
}

function row(title, subtitle, suffix) {
  const r = new Adw.ActionRow({ title, subtitle: subtitle ?? '' });
  if (suffix) { r.add_suffix(suffix); r.set_activatable_widget(suffix); }
  return r;
}

function controls() {
  const page = new Adw.PreferencesPage();

  const g1 = new Adw.PreferencesGroup({ title: 'General', description: 'Rows in a boxed list' });
  if (has(Adw, 'SwitchRow')) g1.add(new Adw.SwitchRow({ title: 'Show hidden files', active: true }));
  g1.add(row('Show the path bar', null, new Gtk.Switch({ valign: Gtk.Align.CENTER })));
  g1.add(row('Open folders in tabs', 'Instead of new windows', new Gtk.CheckButton({ active: true, valign: Gtk.Align.CENTER })));
  const combo = new Adw.ComboRow({ title: 'Sort by', model: Gtk.StringList.new(['Name', 'Date Modified', 'Size', 'Kind']) });
  g1.add(combo);
  if (has(Adw, 'EntryRow')) g1.add(new Adw.EntryRow({ title: 'Computer Name', text: 'CitronOS' }));
  if (has(Adw, 'SpinRow')) g1.add(Adw.SpinRow.new_with_range(8, 72, 1));
  page.add(g1);

  const g2 = new Adw.PreferencesGroup({ title: 'Controls' });
  const buttons = new Gtk.Box({ spacing: 10, margin_top: 6, margin_bottom: 6 });
  buttons.append(new Gtk.Button({ label: 'Cancel' }));
  buttons.append(new Gtk.Button({ label: 'Save', css_classes: ['suggested-action'] }));
  buttons.append(new Gtk.Button({ label: 'Delete', css_classes: ['destructive-action'] }));
  buttons.append(new Gtk.Button({ label: 'Flat', css_classes: ['flat'] }));
  buttons.append(new Gtk.Button({ icon_name: 'list-add-symbolic', css_classes: ['circular'] }));
  buttons.append(new Gtk.Button({ label: 'Pill', css_classes: ['pill'] }));
  const linked = new Gtk.Box({ css_classes: ['linked'] });
  for (const i of ['view-grid-symbolic', 'view-list-symbolic', 'view-paged-symbolic'])
    linked.append(new Gtk.ToggleButton({ icon_name: i, active: i === 'view-list-symbolic' }));
  buttons.append(linked);
  g2.add(buttons);

  const toggles = new Gtk.Box({ spacing: 14, margin_top: 6, margin_bottom: 6 });
  toggles.append(new Gtk.Switch({ active: true, valign: Gtk.Align.CENTER }));
  toggles.append(new Gtk.Switch({ valign: Gtk.Align.CENTER }));
  toggles.append(new Gtk.CheckButton({ label: 'Checked', active: true }));
  toggles.append(new Gtk.CheckButton({ label: 'Unchecked' }));
  const r1 = new Gtk.CheckButton({ label: 'Radio', active: true });
  toggles.append(r1);
  toggles.append(new Gtk.CheckButton({ label: 'Other', group: r1 }));
  g2.add(toggles);

  const entries = new Gtk.Box({ spacing: 10, margin_top: 6, margin_bottom: 6 });
  entries.append(new Gtk.Entry({ placeholder_text: 'Text field', hexpand: true }));
  entries.append(new Gtk.SearchEntry({ placeholder_text: 'Search', hexpand: true }));
  entries.append(Gtk.DropDown.new_from_strings(['Automatic', 'Light', 'Dark']));
  entries.append(Gtk.SpinButton.new_with_range(0, 100, 1));
  g2.add(entries);

  const sliders = new Gtk.Box({ spacing: 14, margin_top: 6, margin_bottom: 6 });
  const scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
  scale.set_value(62); scale.set_hexpand(true);
  sliders.append(scale);
  const progress = new Gtk.ProgressBar({ fraction: 0.4, hexpand: true, valign: Gtk.Align.CENTER });
  sliders.append(progress);
  sliders.append(new Gtk.Spinner({ spinning: true }));
  g2.add(sliders);
  page.add(g2);
  return page;
}

function finder() {
  const store = new Gio.ListStore({ item_type: Gtk.StringObject });
  const files = [
    ['Applications', '—', 'Folder', 'Today at 09:41'], ['Desktop', '—', 'Folder', 'Yesterday at 18:02'],
    ['Documents', '—', 'Folder', '12 Sept 2026 at 11:20'], ['Downloads', '—', 'Folder', 'Today at 08:15'],
    ['Budget 2026.ods', '48 KB', 'Spreadsheet', '3 Sept 2026 at 16:44'], ['CitronOS.png', '2.4 MB', 'PNG image', '1 Sept 2026 at 12:00'],
    ['Notes.txt', '1 KB', 'Plain Text', '28 Aug 2026 at 21:13'], ['Trip.mp4', '184.2 MB', 'MPEG-4 movie', '14 Aug 2026 at 10:05'],
  ];
  for (const f of files) store.append(Gtk.StringObject.new(f.join('\t')));
  const selection = new Gtk.SingleSelection({ model: store, selected: 4 });
  const view = new Gtk.ColumnView({ model: selection, css_classes: ['data-table'], show_column_separators: false });
  ['Name', 'Size', 'Kind', 'Date Modified'].forEach((title, i) => {
    const factory = new Gtk.SignalListItemFactory();
    factory.connect('setup', (_f, item) => {
      const box = new Gtk.Box({ spacing: 6 });
      if (i === 0) box.append(new Gtk.Image({ icon_name: 'folder' }));
      box.append(new Gtk.Label({ xalign: 0, css_classes: i ? ['dim-label'] : [] }));
      item.set_child(box);
    });
    factory.connect('bind', (_f, item) => {
      const cols = item.get_item().get_string().split('\t');
      const box = item.get_child();
      box.get_last_child().set_label(cols[i]);
      if (i === 0) box.get_first_child().set_from_icon_name(cols[1] === '—' ? 'folder' : 'text-x-generic');
    });
    const col = new Gtk.ColumnViewColumn({ title, factory, expand: i === 0 });
    view.append_column(col);
  });
  return new Gtk.ScrolledWindow({ child: view, vexpand: true });
}

app.connect('activate', () => {
  const win = new Adw.ApplicationWindow({ application: app, default_width: 1000, default_height: 660, title: 'Gallery' });

  const content = new Adw.ToolbarView();
  const bar = new Adw.HeaderBar({ title_widget: new Adw.WindowTitle({ title: MODE === 'finder' ? 'Documents' : 'Gallery', subtitle: '' }) });
  bar.pack_start(new Gtk.Button({ icon_name: 'go-previous-symbolic' }));
  bar.pack_start(new Gtk.Button({ icon_name: 'go-next-symbolic', sensitive: false }));
  const menu = new Gio.Menu();
  const s1 = new Gio.Menu();
  s1.append('New Folder', 'win.none'); s1.append('New Tab', 'win.none'); s1.append('Open in Terminal', 'win.none');
  const s2 = new Gio.Menu();
  s2.append('Show Hidden Files', 'win.hidden'); s2.append('Sort by Name', 'win.none');
  const s3 = new Gio.Menu();
  s3.append('Preferences', 'win.none'); s3.append('Keyboard Shortcuts', 'win.none'); s3.append('About Gallery', 'win.none');
  menu.append_section(null, s1); menu.append_section(null, s2); menu.append_section(null, s3);
  const hidden = Gio.SimpleAction.new_stateful('hidden', null, GLib.Variant.new_boolean(true));
  win.add_action(hidden);
  win.add_action(new Gio.SimpleAction({ name: 'none' }));
  const menuButton = new Gtk.MenuButton({ icon_name: 'open-menu-symbolic', menu_model: menu });
  bar.pack_end(menuButton);
  bar.pack_end(new Gtk.ToggleButton({ icon_name: 'system-search-symbolic' }));
  content.add_top_bar(bar);
  content.set_content(MODE === 'finder' ? finder() : controls());

  const split = new Adw.NavigationSplitView({
    sidebar: new Adw.NavigationPage({ title: 'Sidebar', child: sidebar() }),
    content: new Adw.NavigationPage({ title: 'Content', child: content }),
  });
  win.set_content(split);
  win.present();

  // GG_DUMP=1 prints the widget tree (CSS node names, classes, sizes) for writing selectors.
  if (GLib.getenv('GG_DUMP')) GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
    print(`decoration-layout: ${Gtk.Settings.get_default().gtk_decoration_layout}`);
    const walk = (w, depth) => {
      const classes = w.get_css_classes().join('.');
      print(`${'  '.repeat(depth)}${w.get_css_name()}${classes ? '.' + classes : ''} ${w.get_width()}x${w.get_height()}${w.get_visible() ? '' : ' (hidden)'}`);
      for (let c = w.get_first_child(); c; c = c.get_next_sibling()) walk(c, depth + 1);
    };
    walk(win, 0);
    return GLib.SOURCE_REMOVE;
  });

  if (MODE === 'menu') GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => { menuButton.popup(); return GLib.SOURCE_REMOVE; });
  if (MODE === 'dialog') GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => {
    if (has(Adw, 'AlertDialog')) {
      const d = new Adw.AlertDialog({ heading: 'Move “Budget 2026.ods” to the Trash?', body: 'You can restore it from the Trash later.' });
      d.add_response('cancel', 'Cancel'); d.add_response('trash', 'Move to Trash');
      d.set_response_appearance('trash', Adw.ResponseAppearance.DESTRUCTIVE);
      d.present(win);
    } else {
      const d = new Adw.MessageDialog({ transient_for: win, heading: 'Move “Budget 2026.ods” to the Trash?', body: 'You can restore it from the Trash later.' });
      d.add_response('cancel', 'Cancel'); d.add_response('trash', 'Move to Trash');
      d.set_response_appearance('trash', Adw.ResponseAppearance.DESTRUCTIVE);
      d.present();
    }
    return GLib.SOURCE_REMOVE;
  });
});
app.run([]);
