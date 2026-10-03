//! The menu bar and keyboard shortcuts.

use adw::prelude::*;
use gtk::gio;

fn section(items: &[(&str, &str)]) -> gio::Menu {
    let m = gio::Menu::new();
    for (label, action) in items {
        m.append(Some(label), Some(action));
    }
    m
}

fn menu(sections: &[gio::Menu]) -> gio::Menu {
    let m = gio::Menu::new();
    for s in sections {
        m.append_section(None, s);
    }
    m
}

pub fn menubar() -> gio::Menu {
    let bar = gio::Menu::new();
    bar.append_submenu(
        Some("LCode"),
        &menu(&[
            section(&[("About LCode", "app.about")]),
            section(&[("Settings…", "app.preferences")]),
            section(&[("Quit LCode", "app.quit")]),
        ]),
    );

    let new = section(&[("Project…", "app.new-project"), ("File…", "win.new-file")]);
    let file = gio::Menu::new();
    let new_section = gio::Menu::new();
    new_section.append_submenu(Some("New"), &new);
    file.append_section(None, &new_section);
    file.append_section(None, &section(&[("Open…", "app.open"), ("Open Quickly…", "win.open-quickly")]));
    file.append_section(None, &section(&[("Close Tab", "win.close-tab"), ("Close Project", "win.close")]));
    file.append_section(None, &section(&[("Save", "win.save"), ("Save All", "win.save-all")]));
    bar.append_submenu(Some("File"), &file);

    bar.append_submenu(
        Some("Edit"),
        &menu(&[
            section(&[("Undo", "win.undo"), ("Redo", "win.redo")]),
            section(&[("Cut", "win.cut"), ("Copy", "win.copy"), ("Paste", "win.paste"), ("Select All", "win.select-all")]),
            section(&[("Comment Selection", "win.toggle-comment"), ("Go to Line…", "win.go-to-line")]),
        ]),
    );

    bar.append_submenu(
        Some("View"),
        &menu(&[
            section(&[
                ("Navigator", "win.toggle-navigator"),
                ("Debug Area", "win.toggle-debug-area"),
                ("Inspectors", "win.toggle-inspector"),
            ]),
            section(&[
                ("Project Navigator", "win.show-project-navigator"),
                ("Find Navigator", "win.show-find-navigator"),
                ("Issue Navigator", "win.show-issue-navigator"),
                ("Report Navigator", "win.show-report-navigator"),
            ]),
            section(&[("Minimap", "win.toggle-minimap"), ("Clear Console", "win.clear-console")]),
        ]),
    );

    bar.append_submenu(
        Some("Find"),
        &menu(&[
            section(&[("Find in Project…", "win.find-in-project")]),
            section(&[("Find…", "win.find"), ("Find Next", "win.find-next"), ("Find Previous", "win.find-previous")]),
        ]),
    );

    bar.append_submenu(
        Some("Product"),
        &menu(&[
            section(&[("Run", "win.run"), ("Test", "win.test")]),
            section(&[("Build", "win.build"), ("Clean Build Folder", "win.clean")]),
            section(&[("Stop", "win.stop")]),
        ]),
    );

    bar.append_submenu(
        Some("Window"),
        &menu(&[section(&[("Welcome to LCode", "app.welcome"), ("Simulator", "app.simulator")])]),
    );

    bar.append_submenu(Some("Help"), &menu(&[section(&[("Keyboard Shortcuts", "app.shortcuts"), ("About LCode", "app.about")])]));
    bar
}

/// Keyboard shortcuts, modelled on the classic Apple IDE bindings with ⌘ mapped to Ctrl.
pub const ACCELS: &[(&str, &[&str], &str)] = &[
    ("app.quit", &["<Control>q"], "Quit LCode"),
    ("app.preferences", &["<Control>comma"], "Settings"),
    ("app.new-project", &["<Shift><Control>n"], "New Project"),
    ("app.open", &["<Control>o"], "Open"),
    ("app.welcome", &["<Shift><Control>1"], "Welcome to LCode"),
    ("app.simulator", &["<Shift><Control>2"], "Simulator"),
    ("win.new-file", &["<Control>n"], "New File"),
    ("win.open-quickly", &["<Shift><Control>o"], "Open Quickly"),
    ("win.close-tab", &["<Control>w"], "Close Tab"),
    ("win.close", &["<Shift><Control>w"], "Close Project"),
    ("win.save", &["<Control>s"], "Save"),
    ("win.save-all", &["<Alt><Control>s"], "Save All"),
    ("win.toggle-comment", &["<Control>slash"], "Comment Selection"),
    ("win.go-to-line", &["<Control>l"], "Go to Line"),
    ("win.find", &["<Control>f"], "Find"),
    ("win.find-next", &["<Control>g"], "Find Next"),
    ("win.find-previous", &["<Shift><Control>g"], "Find Previous"),
    ("win.find-in-project", &["<Shift><Control>f"], "Find in Project"),
    ("win.toggle-navigator", &["<Control>0"], "Show/Hide Navigator"),
    ("win.toggle-debug-area", &["<Shift><Control>y"], "Show/Hide Debug Area"),
    ("win.toggle-inspector", &["<Alt><Control>0"], "Show/Hide Inspectors"),
    ("win.show-project-navigator", &["<Control>1"], "Project Navigator"),
    ("win.show-find-navigator", &["<Control>4"], "Find Navigator"),
    ("win.show-issue-navigator", &["<Control>5"], "Issue Navigator"),
    ("win.show-report-navigator", &["<Control>9"], "Report Navigator"),
    ("win.clear-console", &["<Control>k"], "Clear Console"),
    ("win.run", &["<Control>r"], "Run"),
    ("win.build", &["<Control>b"], "Build"),
    ("win.test", &["<Control>u"], "Test"),
    ("win.clean", &["<Shift><Control>k"], "Clean Build Folder"),
    ("win.stop", &["<Control>period"], "Stop"),
];

pub fn install_accels(app: &adw::Application) {
    for (action, accels, _) in ACCELS {
        app.set_accels_for_action(action, accels);
    }
}

/// A dialog listing all shortcuts.
pub fn show_shortcuts(parent: Option<&gtk::Window>) {
    let list = gtk::ListBox::new();
    list.add_css_class("boxed-list");
    list.set_selection_mode(gtk::SelectionMode::None);
    for (_, accels, title) in ACCELS {
        let row = adw::ActionRow::builder().title(*title).build();
        let label = gtk::ShortcutLabel::new(accels[0]);
        label.set_valign(gtk::Align::Center);
        row.add_suffix(&label);
        list.append(&row);
    }
    let clamp = adw::Clamp::builder().child(&list).margin_top(12).margin_bottom(12).margin_start(12).margin_end(12).build();
    let scroller = gtk::ScrolledWindow::builder().child(&clamp).vexpand(true).build();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&scroller));
    let dialog = adw::Dialog::builder()
        .title("Keyboard Shortcuts")
        .content_width(460)
        .content_height(640)
        .child(&toolbar)
        .build();
    dialog.present(parent);
}
