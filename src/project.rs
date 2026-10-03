//! Project model. An LCode project is a Swift package (Package.swift) plus an
//! optional `.lcode/` directory holding project and per-user settings, the
//! equivalent of an `.xcodeproj` bundle and its `xcuserdata`.

use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ProjectKind {
    /// GUI application, run in the Simulator by default.
    App,
    /// Command-line tool, run on the host with output in the console.
    #[default]
    Tool,
    /// Library package. Builds but has nothing to run.
    Library,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct ProjectMeta {
    pub kind: ProjectKind,
    pub bundle_identifier: String,
    pub organization: String,
    pub default_destination: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct UserState {
    pub open_files: Vec<PathBuf>,
    pub selected_file: Option<PathBuf>,
    pub scheme: Option<String>,
    pub destination: Option<String>,
}

pub const HOST_DESTINATION: &str = "host";

#[derive(Debug, Clone)]
pub struct Project {
    pub root: PathBuf,
    pub name: String,
    pub meta: ProjectMeta,
}

static PACKAGE_NAME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"Package\s*\(\s*name:\s*"([^"]+)""#).unwrap());
static EXECUTABLES: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"\.(?:executableTarget|executable)\s*\(\s*name:\s*"([^"]+)""#).unwrap()
});

impl Project {
    pub fn open(root: &Path) -> Project {
        let root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
        let manifest = std::fs::read_to_string(root.join("Package.swift")).unwrap_or_default();
        let name = PACKAGE_NAME
            .captures(&manifest)
            .map(|c| c[1].to_string())
            .unwrap_or_else(|| {
                root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
            });
        let meta = std::fs::read_to_string(root.join(".lcode/project.json"))
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(|| guess_meta(&manifest));
        Project { root, name, meta }
    }

    pub fn is_swift_package(&self) -> bool {
        self.root.join("Package.swift").is_file()
    }

    pub fn manifest(&self) -> String {
        std::fs::read_to_string(self.root.join("Package.swift")).unwrap_or_default()
    }

    /// Executable products declared in Package.swift; these become schemes.
    pub fn executable_products(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for c in EXECUTABLES.captures_iter(&self.manifest()) {
            let name = c[1].to_string();
            if !out.contains(&name) {
                out.push(name);
            }
        }
        out
    }

    pub fn save_meta(&self) -> std::io::Result<()> {
        let dir = self.root.join(".lcode");
        std::fs::create_dir_all(&dir)?;
        std::fs::write(dir.join("project.json"), serde_json::to_string_pretty(&self.meta)?)
    }

    fn user_state_path(&self) -> PathBuf {
        self.root.join(".lcode/userdata/state.json")
    }

    pub fn load_user_state(&self) -> UserState {
        std::fs::read_to_string(self.user_state_path())
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save_user_state(&self, state: &UserState) {
        let path = self.user_state_path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(json) = serde_json::to_string_pretty(state) {
            let _ = std::fs::write(path, json);
        }
    }
}

/// Infer metadata for packages that were not created by LCode.
fn guess_meta(manifest: &str) -> ProjectMeta {
    let gui = ["swift-cross-ui", "adwaita-swift", "SwiftCrossUI", "Adwaita"]
        .iter()
        .any(|needle| manifest.contains(needle));
    let kind = if gui {
        ProjectKind::App
    } else if EXECUTABLES.is_match(manifest) || manifest.is_empty() {
        ProjectKind::Tool
    } else {
        ProjectKind::Library
    };
    ProjectMeta { kind, ..Default::default() }
}

/// Files and folders hidden from the project navigator, search and Open Quickly.
pub fn is_ignored(name: &str) -> bool {
    name.starts_with('.') || name == "build" || name == "DerivedData"
}

/// All source files in the project, for Open Quickly and Find in Project.
pub fn walk_files(root: &Path, limit: usize) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        let mut entries: Vec<_> = entries.flatten().collect();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            let name = entry.file_name().to_string_lossy().into_owned();
            if is_ignored(&name) {
                continue;
            }
            let path = entry.path();
            match entry.file_type() {
                Ok(t) if t.is_dir() => stack.push(path),
                Ok(t) if t.is_file() => {
                    out.push(path);
                    if out.len() >= limit {
                        return out;
                    }
                }
                _ => {}
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_package_name_and_executables() {
        let dir = std::env::temp_dir().join(format!("lcode-project-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("Package.swift"),
            r#"// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Demo",
    products: [.executable(name: "demo-cli", targets: ["Demo"])],
    dependencies: [.package(url: "https://github.com/moreSwift/swift-cross-ui", from: "0.9.0")],
    targets: [
        .executableTarget(
            name: "Demo"
        ),
        .target(name: "Core"),
    ]
)"#,
        )
        .unwrap();
        let p = Project::open(&dir);
        assert_eq!(p.name, "Demo");
        assert_eq!(p.executable_products(), vec!["demo-cli", "Demo"]);
        assert_eq!(p.meta.kind, ProjectKind::App);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
