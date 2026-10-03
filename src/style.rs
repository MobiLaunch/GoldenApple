//! Application-wide styling: CSS, editor color schemes and the app icon.

use std::path::PathBuf;

use gtk::{gdk, glib};

const CSS: &str = r#"
/* ---------- Toolbar ---------- */
.lcode-toolbar { min-height: 46px; }
.lcode-toolbar button.run-button { min-width: 34px; min-height: 30px; padding: 0 8px; }
.lcode-toolbar button.run-button image { -gtk-icon-size: 18px; }

.scheme-selector {
  border-radius: 7px;
  padding: 2px 4px;
}
.scheme-selector > button, .scheme-selector menubutton > button { padding: 2px 8px; min-height: 24px; }
.scheme-selector .separator-chevron { opacity: 0.45; margin: 0 2px; }

/* The activity view: the rounded status pill in the middle of the toolbar. */
.activity-view {
  background-color: alpha(currentColor, 0.065);
  border-radius: 8px;
  min-height: 30px;
  min-width: 420px;
  padding: 0 12px;
}
.activity-view .activity-title { font-weight: 600; }
.activity-view .activity-status { opacity: 0.8; }
.activity-view progressbar { margin-top: -3px; }
.activity-view progressbar trough { min-height: 3px; background: transparent; }
.activity-view progressbar progress { min-height: 3px; border-radius: 2px; }
.activity-view .badge { font-size: 0.9em; font-weight: 600; padding: 0 2px; }
.activity-view .badge.errors { color: @error_color; }
.activity-view .badge.warnings { color: @warning_color; }

/* ---------- Navigator ---------- */
.navigator { background-color: @sidebar_bg_color; }
.navigator-tabs { padding: 4px 6px; border-bottom: 1px solid alpha(currentColor, 0.1); }
.navigator-tabs togglebutton { min-width: 24px; min-height: 22px; padding: 2px 4px; border-radius: 5px; }
.navigator-tabs togglebutton:checked { color: @accent_color; background: transparent; }
.navigator listview, .navigator list { background: transparent; }
.navigator listview > row { padding: 1px 4px; border-radius: 5px; margin: 0 6px; }
.navigator .filter-bar { padding: 6px; border-top: 1px solid alpha(currentColor, 0.1); }
.navigator .section-title { font-size: 0.85em; font-weight: 700; opacity: 0.6; padding: 8px 10px 2px 10px; }
.navigator .result-file { font-weight: 600; }
.navigator .result-line { font-family: monospace; font-size: 0.9em; }
.navigator .placeholder { opacity: 0.55; padding: 24px; }
.file-row image { margin-right: 4px; }
.file-row .swift-icon { color: #F05138; }
.file-row .folder-icon { color: #3B8EEA; }
.file-row .package-icon { color: #A2845E; }

/* ---------- Editor ---------- */
.jump-bar {
  min-height: 26px;
  padding: 0 8px;
  border-bottom: 1px solid alpha(currentColor, 0.1);
  background-color: @view_bg_color;
}
.jump-bar button { padding: 0 4px; min-height: 22px; font-size: 0.92em; }
.jump-bar .crumb-chevron { opacity: 0.4; -gtk-icon-size: 10px; }
.editor-view { font-family: monospace; }
.editor-map { border-left: 1px solid alpha(currentColor, 0.08); }
.editor-empty { opacity: 0.45; font-size: 1.6em; font-weight: 300; }
.find-bar { padding: 4px 8px; border-bottom: 1px solid alpha(currentColor, 0.1); background-color: @view_bg_color; }
.issue-banner { border-radius: 4px; padding: 0 6px; font-size: 0.9em; }
.issue-banner.error { background-color: alpha(@error_color, 0.22); }
.issue-banner.warning { background-color: alpha(@warning_color, 0.22); }

/* Symbol badges in the jump bar, like an IDE outline. */
.symbol-badge { font-family: monospace; font-weight: 800; font-size: 0.75em; color: white; border-radius: 4px; min-width: 16px; min-height: 16px; padding: 0 2px; }
.symbol-badge.func { background-color: #3D7BD9; }
.symbol-badge.type { background-color: #A65BD6; }
.symbol-badge.enum { background-color: #D97B3D; }
.symbol-badge.proto { background-color: #6E6E73; }
.symbol-badge.ext { background-color: #E5A43B; }
.symbol-badge.mark { background-color: #8E8E93; }

/* ---------- Debug area ---------- */
.debug-bar { min-height: 26px; padding: 0 6px; border-top: 1px solid alpha(currentColor, 0.12); border-bottom: 1px solid alpha(currentColor, 0.08); }
.debug-bar button, .debug-bar togglebutton { min-height: 20px; min-width: 20px; padding: 1px 4px; }
.console-view { font-family: monospace; font-size: 0.92em; padding: 4px 8px; }
.console-input { font-family: monospace; font-size: 0.92em; border-radius: 0; border-top: 1px solid alpha(currentColor, 0.08); }

/* ---------- Inspector ---------- */
.inspector { background-color: @sidebar_bg_color; }
.inspector .inspector-section { font-weight: 700; font-size: 0.85em; padding: 10px 12px 4px 12px; }
.inspector .inspector-key { opacity: 0.65; font-size: 0.9em; }
.inspector .inspector-value { font-size: 0.9em; }

/* ---------- Issues ---------- */
.issue-error image.severity { color: @error_color; }
.issue-warning image.severity { color: @warning_color; }
.issue-note image.severity { color: @accent_color; }

/* ---------- Welcome window ---------- */
.welcome-left { padding: 36px 40px 24px 40px; }
.welcome-title { font-size: 2.6em; font-weight: 300; }
.welcome-version { opacity: 0.55; }
.welcome-action { padding: 8px 12px; border-radius: 9px; }
.welcome-action .action-title { font-weight: 600; }
.welcome-action .action-subtitle { opacity: 0.6; font-size: 0.9em; }
.welcome-action image { color: @accent_color; -gtk-icon-size: 22px; }
.welcome-recents { background-color: @sidebar_bg_color; }
.welcome-recents listview > row, .welcome-recents list > row { border-radius: 7px; margin: 2px 8px; padding: 6px 8px; }
.welcome-recents .recent-path { opacity: 0.55; font-size: 0.85em; }

/* ---------- Template chooser ---------- */
.template-tile { padding: 14px 8px; border-radius: 10px; min-width: 120px; }
.template-tile image { -gtk-icon-size: 48px; color: @accent_color; }
.template-tile:checked { background-color: alpha(@accent_color, 0.18); }
.platform-tabs { margin: 6px 0 4px 0; }

/* ---------- Open Quickly ---------- */
.open-quickly { border-radius: 12px; }
.open-quickly entry { font-size: 1.3em; min-height: 40px; }
.open-quickly .oq-path { opacity: 0.55; font-size: 0.85em; }

/* ---------- Simulator ---------- */
.simulator-stage { background-color: @window_bg_color; }
"#;

/// Directory where bundled data files (style schemes, icons) are unpacked.
fn data_cache_dir() -> PathBuf {
    glib::user_cache_dir().join("lcode").join(env!("CARGO_PKG_VERSION"))
}

pub fn install() {
    let display = gdk::Display::default().expect("a display");

    let provider = gtk::CssProvider::new();
    provider.load_from_string(CSS);
    gtk::style_context_add_provider_for_display(&display, &provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);

    let editor_font = gtk::CssProvider::new();
    update_editor_font(&editor_font);
    gtk::style_context_add_provider_for_display(&display, &editor_font, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    EDITOR_FONT.with(|p| p.replace(Some(editor_font)));

    let dir = data_cache_dir();
    let styles = dir.join("styles");
    // Icons live directly in the search path ("unthemed" icons), which needs no index.theme.
    let icons = dir.join("icons");
    let _ = std::fs::create_dir_all(&styles);
    let _ = std::fs::create_dir_all(&icons);
    let _ = std::fs::write(styles.join("lcode-light.xml"), include_str!("../data/styles/lcode-light.xml"));
    let _ = std::fs::write(styles.join("lcode-dark.xml"), include_str!("../data/styles/lcode-dark.xml"));
    for (name, svg) in [
        ("dev.lcode.LCode.svg", include_str!("../data/icons/dev.lcode.LCode.svg")),
        ("lcode-debug-area-symbolic.svg", include_str!("../data/icons/lcode-debug-area-symbolic.svg")),
        ("lcode-source-file-symbolic.svg", include_str!("../data/icons/lcode-source-file-symbolic.svg")),
    ] {
        let _ = std::fs::write(icons.join(name), svg);
    }

    sourceview5::StyleSchemeManager::default().append_search_path(&styles.to_string_lossy());
    gtk::IconTheme::for_display(&display).add_search_path(&icons);
    gtk::Window::set_default_icon_name(crate::APP_ID);

    apply_appearance();
}

thread_local! {
    static EDITOR_FONT: std::cell::RefCell<Option<gtk::CssProvider>> = const { std::cell::RefCell::new(None) };
}

fn update_editor_font(provider: &gtk::CssProvider) {
    let s = crate::settings::get();
    let family = if s.editor_font.trim().is_empty() { "Monospace".to_string() } else { s.editor_font.clone() };
    provider.load_from_string(&format!(
        ".editor-view {{ font-family: \"{}\", monospace; font-size: {}pt; }}",
        family.replace('"', ""),
        s.editor_font_size.clamp(6, 48)
    ));
}

/// Re-apply settings that affect styling (font, appearance).
pub fn refresh() {
    EDITOR_FONT.with(|p| {
        if let Some(p) = p.borrow().as_ref() {
            update_editor_font(p);
        }
    });
    apply_appearance();
}

fn apply_appearance() {
    let scheme = match crate::settings::get().appearance.as_str() {
        "light" => adw::ColorScheme::ForceLight,
        "dark" => adw::ColorScheme::ForceDark,
        _ => adw::ColorScheme::Default,
    };
    adw::StyleManager::default().set_color_scheme(scheme);
}

/// The editor style scheme matching the current light/dark appearance.
pub fn editor_scheme() -> Option<sourceview5::StyleScheme> {
    let id = if adw::StyleManager::default().is_dark() { "lcode-dark" } else { "lcode-light" };
    sourceview5::StyleSchemeManager::default().scheme(id)
}

/// Icon and CSS class for a file in the navigator.
pub fn file_icon(name: &str, is_dir: bool) -> (&'static str, &'static str) {
    if is_dir {
        return ("folder-symbolic", "folder-icon");
    }
    if name == "Package.swift" {
        return ("package-x-generic-symbolic", "package-icon");
    }
    match name.rsplit('.').next().unwrap_or("") {
        "swift" => ("lcode-source-file-symbolic", "swift-icon"),
        "c" | "h" | "cpp" | "m" | "rs" | "py" | "sh" => ("lcode-source-file-symbolic", "generic-icon"),
        "json" | "plist" | "yml" | "yaml" | "toml" => ("text-x-generic-symbolic", "data-icon"),
        "png" | "jpg" | "jpeg" | "svg" | "gif" => ("image-x-generic-symbolic", "image-icon"),
        "md" | "txt" => ("text-x-generic-symbolic", "doc-icon"),
        _ => ("text-x-generic-symbolic", "generic-icon"),
    }
}
