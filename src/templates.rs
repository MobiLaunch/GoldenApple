//! Project and file templates ("Choose a template for your new project").

use std::path::{Path, PathBuf};

use gtk::glib;

use crate::project::{HOST_DESTINATION, ProjectKind, ProjectMeta};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Template {
    App,
    CommandLineTool,
    Library,
}

impl Template {
    pub const ALL: [Template; 3] = [Template::App, Template::CommandLineTool, Template::Library];

    pub fn title(self) -> &'static str {
        match self {
            Template::App => "App",
            Template::CommandLineTool => "Command Line Tool",
            Template::Library => "Swift Package",
        }
    }

    pub fn subtitle(self) -> &'static str {
        match self {
            Template::App => "A SwiftUI-style app built with SwiftCrossUI that runs in the Simulator.",
            Template::CommandLineTool => "A command-line tool that runs in the LCode console.",
            Template::Library => "A reusable Swift package library with unit tests.",
        }
    }

    pub fn icon_name(self) -> &'static str {
        match self {
            Template::App => "applications-system-symbolic",
            Template::CommandLineTool => "utilities-terminal-symbolic",
            Template::Library => "package-x-generic-symbolic",
        }
    }

    pub fn kind(self) -> ProjectKind {
        match self {
            Template::App => ProjectKind::App,
            Template::CommandLineTool => ProjectKind::Tool,
            Template::Library => ProjectKind::Library,
        }
    }
}

#[derive(Debug, Clone)]
pub struct TemplateOptions {
    pub product_name: String,
    pub organization_name: String,
    pub organization_identifier: String,
    pub include_tests: bool,
    pub create_git_repository: bool,
}

impl TemplateOptions {
    pub fn bundle_identifier(&self) -> String {
        let product: String = self
            .product_name
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '-' })
            .collect();
        if self.organization_identifier.is_empty() {
            product
        } else {
            format!("{}.{}", self.organization_identifier, product)
        }
    }
}

/// Turn a product name into a valid Swift module identifier.
pub fn module_name(product: &str) -> String {
    let mut s: String = product
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '_' { c } else { '_' })
        .collect();
    if s.is_empty() {
        s.push_str("App");
    }
    if s.starts_with(|c: char| c.is_ascii_digit()) {
        s.insert(0, '_');
    }
    s
}

pub fn author_name() -> String {
    let real = glib::real_name().to_string_lossy().into_owned();
    if real.is_empty() || real == "Unknown" {
        glib::user_name().to_string_lossy().into_owned()
    } else {
        real
    }
}

/// The comment banner LCode puts at the top of new files.
pub fn file_header(file_name: &str, project: &str, organization: &str) -> String {
    let date = glib::DateTime::now_local()
        .ok()
        .and_then(|d| d.format("%x").ok())
        .map(|s| s.to_string())
        .unwrap_or_default();
    let mut header = format!(
        "//\n//  {file_name}\n//  {project}\n//\n//  Created by {} on {date}.\n",
        author_name()
    );
    if !organization.is_empty() {
        let year = glib::DateTime::now_local().map(|d| d.year()).unwrap_or(2026);
        header.push_str(&format!("//  Copyright © {year} {organization}. All rights reserved.\n"));
    }
    header.push_str("//\n\n");
    header
}

/// Create the project directory `parent/<product>` and populate it.
pub fn create_project(parent: &Path, template: Template, opts: &TemplateOptions) -> std::io::Result<PathBuf> {
    let root = parent.join(&opts.product_name);
    if root.exists() && std::fs::read_dir(&root)?.next().is_some() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AlreadyExists,
            format!("“{}” already exists and is not empty.", root.display()),
        ));
    }
    let module = module_name(&opts.product_name);
    let name = &opts.product_name;
    let org = &opts.organization_name;
    let sources = root.join("Sources").join(&module);
    std::fs::create_dir_all(&sources)?;

    let mut files: Vec<(PathBuf, String)> = Vec::new();
    let tests_target = format!("{module}Tests");

    match template {
        Template::App => {
            files.push((root.join("Package.swift"), app_manifest(name, &module, opts.include_tests)));
            let app_file = format!("{module}App.swift");
            files.push((
                sources.join(&app_file),
                format!(
                    "{}import SwiftCrossUI\nimport DefaultBackend\n\n@main\nstruct {module}App: App {{\n    var body: some Scene {{\n        WindowGroup(\"{name}\") {{\n            ContentView()\n        }}\n    }}\n}}\n",
                    file_header(&app_file, name, org)
                ),
            ));
            files.push((
                sources.join("ContentView.swift"),
                format!(
                    "{}import SwiftCrossUI\n\nstruct ContentView: View {{\n    @State var count = 0\n\n    var body: some View {{\n        VStack {{\n            Text(\"Hello, world!\")\n                .font(.title)\n            HStack {{\n                Button(\"-\") {{ count -= 1 }}\n                Text(\"Count: \\(count)\")\n                Button(\"+\") {{ count += 1 }}\n            }}\n        }}\n        .padding()\n    }}\n}}\n",
                    file_header("ContentView.swift", name, org)
                ),
            ));
        }
        Template::CommandLineTool => {
            files.push((root.join("Package.swift"), tool_manifest(name, &module, opts.include_tests)));
            files.push((
                sources.join("main.swift"),
                format!("{}print(\"Hello, World!\")\n", file_header("main.swift", name, org)),
            ));
        }
        Template::Library => {
            files.push((root.join("Package.swift"), library_manifest(name, &module, opts.include_tests)));
            files.push((
                sources.join(format!("{module}.swift")),
                format!(
                    "{}/// A greeting from {module}.\npublic func greeting(for name: String) -> String {{\n    \"Hello, \\(name)!\"\n}}\n",
                    file_header(&format!("{module}.swift"), name, org)
                ),
            ));
        }
    }

    if opts.include_tests {
        let tests = root.join("Tests").join(&tests_target);
        std::fs::create_dir_all(&tests)?;
        let test_file = format!("{tests_target}.swift");
        let body = match template {
            Template::Library => format!(
                "import XCTest\n@testable import {module}\n\nfinal class {tests_target}: XCTestCase {{\n    func testGreeting() throws {{\n        XCTAssertEqual(greeting(for: \"LCode\"), \"Hello, LCode!\")\n    }}\n}}\n"
            ),
            _ => format!(
                "import XCTest\n\nfinal class {tests_target}: XCTestCase {{\n    func testExample() throws {{\n        XCTAssertTrue(true)\n    }}\n}}\n"
            ),
        };
        files.push((tests.join(&test_file), format!("{}{body}", file_header(&test_file, name, org))));
    }

    files.push((root.join(".gitignore"), ".DS_Store\n/.build\n/Packages\n.lcode/userdata/\n*.swp\n".into()));

    for (path, contents) in files {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        std::fs::write(path, contents)?;
    }

    let meta = ProjectMeta {
        kind: template.kind(),
        bundle_identifier: opts.bundle_identifier(),
        organization: opts.organization_name.clone(),
        default_destination: match template {
            Template::App => crate::settings::get().default_simulator,
            _ => HOST_DESTINATION.into(),
        },
    };
    std::fs::create_dir_all(root.join(".lcode"))?;
    std::fs::write(root.join(".lcode/project.json"), serde_json::to_string_pretty(&meta)?)?;

    if opts.create_git_repository {
        let ok = std::process::Command::new("git")
            .args(["init", "--quiet"])
            .current_dir(&root)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            let _ = std::process::Command::new("git").args(["add", "-A"]).current_dir(&root).status();
            let mut commit = std::process::Command::new("git");
            // Without a configured identity git refuses to commit; fall back to a local one.
            let has_identity = std::process::Command::new("git")
                .args(["config", "user.email"])
                .current_dir(&root)
                .output()
                .is_ok_and(|o| o.status.success() && !o.stdout.trim_ascii().is_empty());
            if !has_identity {
                commit
                    .arg("-c")
                    .arg(format!("user.name={}", author_name()))
                    .arg("-c")
                    .arg(format!("user.email={}@localhost", glib::user_name().to_string_lossy()));
            }
            let _ = commit.args(["commit", "--quiet", "-m", "Initial Commit"]).current_dir(&root).status();
        }
    }
    Ok(root)
}

fn test_target(module: &str, include: bool, deps: &str) -> String {
    if include {
        format!(
            "        .testTarget(\n            name: \"{module}Tests\",\n            dependencies: [{deps}]\n        ),\n"
        )
    } else {
        String::new()
    }
}

fn app_manifest(name: &str, module: &str, tests: bool) -> String {
    format!(
        r#"// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "{name}",
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.9.0")),
    ],
    targets: [
        .executableTarget(
            name: "{module}",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
{tests}    ]
)
"#,
        tests = test_target(module, tests, "")
    )
}

fn tool_manifest(name: &str, module: &str, tests: bool) -> String {
    format!(
        r#"// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{name}",
    targets: [
        .executableTarget(
            name: "{module}"
        ),
{tests}    ]
)
"#,
        tests = test_target(module, tests, "")
    )
}

fn library_manifest(name: &str, module: &str, tests: bool) -> String {
    format!(
        r#"// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{name}",
    products: [
        .library(
            name: "{module}",
            targets: ["{module}"]
        ),
    ],
    targets: [
        .target(
            name: "{module}"
        ),
{tests}    ]
)
"#,
        tests = test_target(module, tests, &format!("\"{module}\""))
    )
}

/// Templates offered by File ▸ New ▸ File…
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileTemplate {
    SwiftFile,
    SwiftUIView,
    Empty,
}

impl FileTemplate {
    pub fn contents(self, file_name: &str, project: &str, organization: &str) -> String {
        let stem = Path::new(file_name)
            .file_stem()
            .map(|s| module_name(&s.to_string_lossy()))
            .unwrap_or_default();
        match self {
            FileTemplate::SwiftFile => format!("{}import Foundation\n\n", file_header(file_name, project, organization)),
            FileTemplate::SwiftUIView => format!(
                "{}import SwiftCrossUI\n\nstruct {stem}: View {{\n    var body: some View {{\n        Text(\"Hello, world!\")\n    }}\n}}\n",
                file_header(file_name, project, organization)
            ),
            FileTemplate::Empty => String::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(name: &str) -> TemplateOptions {
        TemplateOptions {
            product_name: name.into(),
            organization_name: "Acme".into(),
            organization_identifier: "com.acme".into(),
            include_tests: true,
            create_git_repository: false,
        }
    }

    #[test]
    fn module_names_are_valid_identifiers() {
        assert_eq!(module_name("My App"), "My_App");
        assert_eq!(module_name("2048"), "_2048");
        assert_eq!(opts("My App").bundle_identifier(), "com.acme.My-App");
    }

    #[test]
    fn creates_each_template() {
        let base = std::env::temp_dir().join(format!("lcode-templates-{}", std::process::id()));
        for t in Template::ALL {
            let root = create_project(&base, t, &opts(&format!("{:?}Demo", t))).unwrap();
            let manifest = std::fs::read_to_string(root.join("Package.swift")).unwrap();
            assert!(manifest.starts_with("// swift-tools-version:"));
            assert!(manifest.contains(".testTarget("));
            let project = crate::project::Project::open(&root);
            assert_eq!(project.meta.kind, t.kind());
            match t {
                Template::Library => assert!(project.executable_products().is_empty()),
                _ => assert_eq!(project.executable_products().len(), 1),
            }
            // Refuses to overwrite.
            assert!(create_project(&base, t, &opts(&format!("{:?}Demo", t))).is_err());
        }
        std::fs::remove_dir_all(&base).unwrap();
    }
}
