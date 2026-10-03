//! LCode ▸ Settings.

use adw::prelude::*;

use crate::settings;

fn apply_everywhere() {
    crate::style::refresh();
    for ws in crate::workspace::all() {
        ws.apply_settings();
    }
}

fn toolchain_description() -> String {
    match settings::swift_executable() {
        Some(path) => {
            let version = std::process::Command::new(&path)
                .arg("--version")
                .output()
                .ok()
                .filter(|o| o.status.success())
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .and_then(|s| s.lines().next().map(str::to_string));
            match version {
                Some(v) => format!("{v}\n{}", path.display()),
                None => format!("{} (could not run it)", path.display()),
            }
        }
        None => "No Swift toolchain found on PATH".into(),
    }
}

pub fn present(parent: Option<&gtk::Window>) {
    let s = settings::get();
    let dialog = adw::PreferencesDialog::new();
    dialog.set_title("Settings");

    // General
    let general = adw::PreferencesPage::builder().title("General").icon_name("emblem-system-symbolic").build();
    let appearance_group = adw::PreferencesGroup::builder().title("Appearance").build();
    let appearance = adw::ComboRow::builder()
        .title("Appearance")
        .model(&gtk::StringList::new(&["System", "Light", "Dark"]))
        .selected(match s.appearance.as_str() {
            "light" => 1,
            "dark" => 2,
            _ => 0,
        })
        .build();
    appearance.connect_selected_notify(|row| {
        let value = ["system", "light", "dark"][row.selected().min(2) as usize].to_string();
        settings::update(|s| s.appearance = value);
        apply_everywhere();
    });
    appearance_group.add(&appearance);
    let welcome = adw::SwitchRow::builder()
        .title("Show Welcome Window on Launch")
        .active(s.show_welcome_on_launch)
        .build();
    welcome.connect_active_notify(|row| {
        let on = row.is_active();
        settings::update(|s| s.show_welcome_on_launch = on);
    });
    appearance_group.add(&welcome);
    general.add(&appearance_group);

    let sim_group = adw::PreferencesGroup::builder().title("Simulator").build();
    let names: Vec<&str> = crate::simulator::DEVICES.iter().map(|d| d.name).collect();
    let default_sim = adw::ComboRow::builder()
        .title("Default Device")
        .subtitle("Used for new app projects")
        .model(&gtk::StringList::new(&names))
        .selected(crate::simulator::DEVICES.iter().position(|d| d.id == s.default_simulator).unwrap_or(0) as u32)
        .build();
    default_sim.connect_selected_notify(|row| {
        if let Some(d) = crate::simulator::DEVICES.get(row.selected() as usize) {
            settings::update(|s| s.default_simulator = d.id.to_string());
        }
    });
    sim_group.add(&default_sim);
    general.add(&sim_group);
    dialog.add(&general);

    // Text Editing
    let editing = adw::PreferencesPage::builder().title("Text Editing").icon_name("document-edit-symbolic").build();
    let font_group = adw::PreferencesGroup::builder().title("Font").build();
    let font_family = adw::EntryRow::builder().title("Editor Font Family").text(&s.editor_font).show_apply_button(true).build();
    font_family.connect_apply(|row| {
        let family = row.text().to_string();
        settings::update(|s| s.editor_font = family);
        apply_everywhere();
    });
    font_group.add(&font_family);
    let font_size = adw::SpinRow::with_range(6.0, 48.0, 1.0);
    font_size.set_title("Font Size");
    font_size.set_value(s.editor_font_size as f64);
    font_size.connect_value_notify(|row| {
        let size = row.value() as u32;
        settings::update(|s| s.editor_font_size = size);
        apply_everywhere();
    });
    font_group.add(&font_size);
    editing.add(&font_group);

    let indent_group = adw::PreferencesGroup::builder().title("Indentation").build();
    let spaces = adw::SwitchRow::builder().title("Indent Using Spaces").active(s.indent_with_spaces).build();
    spaces.connect_active_notify(|row| {
        let on = row.is_active();
        settings::update(|s| s.indent_with_spaces = on);
        apply_everywhere();
    });
    indent_group.add(&spaces);
    let tab_width = adw::SpinRow::with_range(1.0, 16.0, 1.0);
    tab_width.set_title("Tab Width");
    tab_width.set_value(s.tab_width as f64);
    tab_width.connect_value_notify(|row| {
        let w = row.value() as u32;
        settings::update(|s| s.tab_width = w);
        apply_everywhere();
    });
    indent_group.add(&tab_width);
    let minimap = adw::SwitchRow::builder().title("Show Minimap").active(s.show_minimap).build();
    minimap.connect_active_notify(|row| {
        let on = row.is_active();
        settings::update(|s| s.show_minimap = on);
        apply_everywhere();
    });
    indent_group.add(&minimap);
    editing.add(&indent_group);
    dialog.add(&editing);

    // Locations
    let locations = adw::PreferencesPage::builder().title("Locations").icon_name("folder-symbolic").build();
    let toolchain_group = adw::PreferencesGroup::builder()
        .title("Swift Toolchain")
        .description("Leave empty to use the swift on your PATH (or $LCODE_SWIFT).")
        .build();
    let detected = adw::ActionRow::builder().title("Active Toolchain").subtitle(toolchain_description()).build();
    detected.add_css_class("property");
    let path = adw::EntryRow::builder().title("Path to swift").text(&s.swift_path).show_apply_button(true).build();
    let detected_row = detected.clone();
    path.connect_apply(move |row| {
        let p = row.text().trim().to_string();
        settings::update(|s| s.swift_path = p);
        detected_row.set_subtitle(&toolchain_description());
    });
    toolchain_group.add(&path);
    toolchain_group.add(&detected);
    locations.add(&toolchain_group);
    dialog.add(&locations);

    match parent {
        Some(p) => dialog.present(Some(p)),
        None => dialog.present(None::<&gtk::Widget>),
    }
}
