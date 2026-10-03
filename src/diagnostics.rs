//! Parsing compiler output (swiftc / SwiftPM / clang / ld) into issues.

use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Severity {
    Error,
    Warning,
    Note,
}

impl Severity {
    pub fn icon_name(self) -> &'static str {
        match self {
            Severity::Error => "dialog-error-symbolic",
            Severity::Warning => "dialog-warning-symbolic",
            Severity::Note => "dialog-information-symbolic",
        }
    }

    pub fn css_class(self) -> &'static str {
        match self {
            Severity::Error => "issue-error",
            Severity::Warning => "issue-warning",
            Severity::Note => "issue-note",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Location {
    pub path: PathBuf,
    pub line: u32,
    pub column: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Diagnostic {
    pub severity: Severity,
    pub message: String,
    pub location: Option<Location>,
}

static LOCATED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?P<path>[^:\s][^:]*):(?P<line>\d+):(?:(?P<col>\d+):)? (?P<sev>error|warning|note): (?P<msg>.+)$")
        .unwrap()
});
static GLOBAL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?:\S+: )?(?P<sev>error|warning): (?P<msg>.+)$").unwrap());
static PROGRESS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\[(?P<done>\d+)/(?P<total>\d+)\]").unwrap());

fn severity(s: &str) -> Severity {
    match s {
        "error" => Severity::Error,
        "warning" => Severity::Warning,
        _ => Severity::Note,
    }
}

/// Parse one line of build output. Relative paths are resolved against `root`.
pub fn parse_line(line: &str, root: &Path) -> Option<Diagnostic> {
    let line = strip_ansi(line);
    let line = line.trim_end();
    if let Some(c) = LOCATED.captures(line) {
        let raw = Path::new(&c["path"]);
        let path = if raw.is_absolute() { raw.to_path_buf() } else { root.join(raw) };
        return Some(Diagnostic {
            severity: severity(&c["sev"]),
            message: c["msg"].to_string(),
            location: Some(Location {
                path,
                line: c["line"].parse().unwrap_or(1),
                column: c.name("col").and_then(|m| m.as_str().parse().ok()).unwrap_or(1),
            }),
        });
    }
    if let Some(c) = GLOBAL.captures(line) {
        return Some(Diagnostic {
            severity: severity(&c["sev"]),
            message: c["msg"].to_string(),
            location: None,
        });
    }
    None
}

/// Parse SwiftPM's `[done/total]` progress prefix.
pub fn parse_progress(line: &str) -> Option<(u32, u32)> {
    let c = PROGRESS.captures(line)?;
    Some((c["done"].parse().ok()?, c["total"].parse().ok()?))
}

pub fn strip_ansi(s: &str) -> std::borrow::Cow<'_, str> {
    static ANSI: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\x1b\[[0-9;?]*[ -/]*[@-~]").unwrap());
    ANSI.replace_all(s, "")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_swiftc_error() {
        let d = parse_line(
            "/home/me/App/Sources/App/main.swift:12:5: error: cannot find 'foo' in scope",
            Path::new("/home/me/App"),
        )
        .unwrap();
        assert_eq!(d.severity, Severity::Error);
        assert_eq!(d.message, "cannot find 'foo' in scope");
        let loc = d.location.unwrap();
        assert_eq!(loc.path, PathBuf::from("/home/me/App/Sources/App/main.swift"));
        assert_eq!((loc.line, loc.column), (12, 5));
    }

    #[test]
    fn resolves_relative_paths_and_missing_columns() {
        let d = parse_line("Sources/A.swift:3: warning: unused", Path::new("/p")).unwrap();
        let loc = d.location.unwrap();
        assert_eq!(loc.path, PathBuf::from("/p/Sources/A.swift"));
        assert_eq!((loc.line, loc.column), (3, 1));
    }

    #[test]
    fn parses_global_errors_and_ignores_noise() {
        let d = parse_line("error: link command failed with exit code 1", Path::new("/")).unwrap();
        assert!(d.location.is_none());
        assert_eq!(d.severity, Severity::Error);
        assert!(parse_line("[3/7] Compiling App main.swift", Path::new("/")).is_none());
        assert!(parse_line("Build complete! (1.2s)", Path::new("/")).is_none());
    }

    #[test]
    fn strips_color_codes() {
        let d = parse_line("\x1b[1m/a/b.swift:1:2: \x1b[31merror: \x1b[0mboom", Path::new("/")).unwrap();
        assert_eq!(d.message, "boom");
    }

    #[test]
    fn parses_progress() {
        assert_eq!(parse_progress("[3/7] Compiling App main.swift"), Some((3, 7)));
        assert_eq!(parse_progress("Compiling"), None);
    }
}
