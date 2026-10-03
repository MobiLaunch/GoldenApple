//! Global preferences (~/.config/lcode/settings.json) and the recent projects list.

use std::cell::RefCell;
use std::path::{Path, PathBuf};

use gtk::glib;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Path to the `swift` driver. Empty means "find it on PATH".
    pub swift_path: String,
    pub editor_font: String,
    pub editor_font_size: u32,
    pub show_minimap: bool,
    pub show_welcome_on_launch: bool,
    /// "system", "light" or "dark".
    pub appearance: String,
    pub tab_width: u32,
    pub indent_with_spaces: bool,
    pub default_simulator: String,
    pub organization_name: String,
    pub organization_identifier: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            swift_path: String::new(),
            editor_font: "Monospace".into(),
            editor_font_size: 11,
            show_minimap: true,
            show_welcome_on_launch: true,
            appearance: "system".into(),
            tab_width: 4,
            indent_with_spaces: true,
            default_simulator: "lphone-16".into(),
            organization_name: String::new(),
            organization_identifier: "com.example".into(),
        }
    }
}

thread_local! {
    static SETTINGS: RefCell<Settings> = RefCell::new(load());
}

fn config_path() -> PathBuf {
    glib::user_config_dir().join("lcode/settings.json")
}

fn load() -> Settings {
    std::fs::read_to_string(config_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn get() -> Settings {
    SETTINGS.with(|s| s.borrow().clone())
}

pub fn update(f: impl FnOnce(&mut Settings)) {
    SETTINGS.with(|s| {
        f(&mut s.borrow_mut());
        let path = config_path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(json) = serde_json::to_string_pretty(&*s.borrow()) {
            let _ = std::fs::write(path, json);
        }
    });
}

/// Resolve the Swift driver: settings, then $LCODE_SWIFT, then PATH.
pub fn swift_executable() -> Option<PathBuf> {
    let configured = get().swift_path;
    if !configured.is_empty() {
        return Some(PathBuf::from(configured));
    }
    if let Ok(p) = std::env::var("LCODE_SWIFT")
        && !p.is_empty() {
            return Some(PathBuf::from(p));
        }
    glib::find_program_in_path("swift")
}

// ---- Recent projects ----------------------------------------------------

fn recent_path() -> PathBuf {
    glib::user_data_dir().join("lcode/recent.json")
}

pub fn recent_projects() -> Vec<PathBuf> {
    std::fs::read_to_string(recent_path())
        .ok()
        .and_then(|s| serde_json::from_str::<Vec<PathBuf>>(&s).ok())
        .unwrap_or_default()
        .into_iter()
        .filter(|p| p.is_dir())
        .collect()
}

pub fn add_recent_project(path: &Path) {
    let mut list = recent_projects();
    list.retain(|p| p != path);
    list.insert(0, path.to_path_buf());
    list.truncate(12);
    write_recent(&list);
}

pub fn remove_recent_project(path: &Path) {
    let mut list = recent_projects();
    list.retain(|p| p != path);
    write_recent(&list);
}

fn write_recent(list: &[PathBuf]) {
    let path = recent_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(json) = serde_json::to_string_pretty(list) {
        let _ = std::fs::write(path, json);
    }
}
