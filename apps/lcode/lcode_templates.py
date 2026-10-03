"""LCode project templates (File ▸ New ▸ Project) and new-file contents.

Every template writes a project its own tools understand (SwiftPM, cargo,
Meson, Python) plus .lcode/project.json, LCode's settings for it: the
toolchain, product type, app identity and default run destination.
"""
from __future__ import annotations

import datetime
import getpass
import json
import os
import pathlib
import pwd
import re
import subprocess

HOST = "host"

# id: (toolchain, product kind, title)
TEMPLATE_INFO = {
    "gg-app": ("goldengate", "app", "Golden Gate App"),
    "app": ("swift", "app", "Swift App"),
    "python-app": ("python", "app", "Python App"),
    "rust-app": ("cargo", "app", "Rust App"),
    "c-app": ("meson", "app", "C App"),
    "tool": ("swift", "tool", "Swift Command Line Tool"),
    "python-tool": ("python", "tool", "Python Script"),
    "rust-tool": ("cargo", "tool", "Rust Command Line Tool"),
    "c-tool": ("meson", "tool", "C Command Line Tool"),
    "library": ("swift", "library", "Swift Package"),
    "rust-library": ("cargo", "library", "Rust Library"),
}
TEMPLATES = tuple(TEMPLATE_INFO)


# ------------------------------------------------------------------ names

def module_name(product: str) -> str:
    s = "".join(c if c.isalnum() or c == "_" else "_" for c in product) or "App"
    return "_" + s if s[0].isdigit() else s


def snake_name(product: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", product.lower()).strip("_") or "app"
    return "app_" + s if s[0].isdigit() else s


def slug_name(product: str) -> str:
    """Cargo and Meson names: lowercase words joined by hyphens."""
    s = re.sub(r"[^a-z0-9]+", "-", product.lower()).strip("-") or "app"
    return "app-" + s if s[0].isdigit() else s


def bundle_identifier(org_id: str, product: str) -> str:
    slug = "".join(c if c.isascii() and (c.isalnum() or c == "-") else "-" for c in product)
    return f"{org_id}.{slug}" if org_id else slug


def application_id(bundle_id: str) -> str:
    """A valid GTK/D-Bus application id from a bundle identifier."""
    parts = [re.sub(r"[^A-Za-z0-9_]", "_", p) for p in bundle_id.split(".") if p]
    parts = ["_" + p if p[0].isdigit() else p for p in parts]
    if len(parts) < 2:
        parts.insert(0, "org.example")
    return ".".join(parts)


def author_name() -> str:
    try:
        gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
        if gecos:
            return gecos
    except KeyError:
        pass
    return getpass.getuser()


COMMENT = {"swift": "//", "rust": "//", "c": "//", "qml": "//", "js": "//", "python": "#", "css": None, "meson": "#", "toml": "#"}


def language_of(file_name: str) -> str:
    ext = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""
    return {"swift": "swift", "rs": "rust", "c": "c", "h": "c", "cpp": "c", "hpp": "c", "qml": "qml", "js": "js",
            "py": "python", "css": "css", "toml": "toml"}.get(ext, "meson" if file_name == "meson.build" else "")


def file_header(file_name: str, project: str, organization: str = "") -> str:
    today = datetime.date.today().strftime("%x")
    lines = [file_name, project, "", f"Created by {author_name()} on {today}."]
    if organization:
        lines.append(f"Copyright © {datetime.date.today().year} {organization}. All rights reserved.")
    lang = language_of(file_name)
    if lang == "css":
        return "/*\n" + "".join(f" *  {l}\n" if l else " *\n" for l in lines) + " */\n\n"
    mark = COMMENT.get(lang) or "//"
    body = "".join(f"{mark}  {l}\n" if l else f"{mark}\n" for l in lines)
    return f"{mark}\n{body}{mark}\n\n"


# ------------------------------------------------------------------ swift

def _swift_test_target(module: str, include: bool, deps: str = "") -> str:
    if not include:
        return ""
    return f'        .testTarget(\n            name: "{module}Tests",\n            dependencies: [{deps}]\n        ),\n'


def _swift_manifest(template: str, name: str, module: str, tests: bool) -> str:
    if template == "app":
        return f'''// swift-tools-version: 5.10
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
{_swift_test_target(module, tests)}    ]
)
'''
    if template == "tool":
        return f'''// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{name}",
    targets: [
        .executableTarget(
            name: "{module}"
        ),
{_swift_test_target(module, tests)}    ]
)
'''
    return f'''// swift-tools-version: 5.9
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
{_swift_test_target(module, tests, f'"{module}"')}    ]
)
'''


def swift_files(template: str, root: pathlib.Path, name: str, org: str, tests: bool, **_) -> dict:
    module = module_name(name)
    sources = root / "Sources" / module
    h = lambda f: file_header(f, name, org)  # noqa: E731
    files = {root / "Package.swift": _swift_manifest(template, name, module, tests)}
    if template == "app":
        app_file = f"{module}App.swift"
        files[sources / app_file] = h(app_file) + (
            "import SwiftCrossUI\nimport DefaultBackend\n\n@main\n"
            f"struct {module}App: App {{\n    var body: some Scene {{\n        WindowGroup(\"{name}\") {{\n"
            "            ContentView()\n        }\n    }\n}\n")
        files[sources / "ContentView.swift"] = h("ContentView.swift") + (
            "import SwiftCrossUI\n\nstruct ContentView: View {\n    @State var count = 0\n\n"
            "    var body: some View {\n        VStack {\n            Text(\"Hello, world!\")\n"
            "                .font(.title)\n            HStack {\n                Button(\"-\") { count -= 1 }\n"
            "                Text(\"Count: \\(count)\")\n                Button(\"+\") { count += 1 }\n"
            "            }\n        }\n        .padding()\n    }\n}\n")
    elif template == "tool":
        files[sources / "main.swift"] = h("main.swift") + 'print("Hello, World!")\n'
    else:
        lib_file = f"{module}.swift"
        files[sources / lib_file] = h(lib_file) + (
            f"/// A greeting from {module}.\npublic func greeting(for name: String) -> String {{\n"
            "    \"Hello, \\(name)!\"\n}\n")
    if tests:
        tests_name = f"{module}Tests"
        body = (f"import XCTest\n@testable import {module}\n\nfinal class {tests_name}: XCTestCase {{\n"
                "    func testGreeting() throws {\n        XCTAssertEqual(greeting(for: \"LCode\"), \"Hello, LCode!\")\n    }\n}\n"
                if template == "library" else
                f"import XCTest\n\nfinal class {tests_name}: XCTestCase {{\n    func testExample() throws {{\n"
                "        XCTAssertTrue(true)\n    }\n}\n")
        files[root / "Tests" / tests_name / f"{tests_name}.swift"] = h(f"{tests_name}.swift") + body
    files[root / ".gitignore"] = ".DS_Store\n/.build\n/Packages\n.lcode/userdata/\n*.swp\n"
    return files


# ----------------------------------------------------------------- python

PY_APPLICATION = '''import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, Gtk  # noqa: E402

from .window import MainWindow  # noqa: E402

APP_ID = "{app_id}"


class Application(Adw.Application):
    """The app: one main window, the About dialog and Quit (Ctrl+Q)."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.add_action_with_accels("quit", lambda *_: self.quit(), ["<primary>q"])
        self.add_action_with_accels("about", self.on_about, [])

    def add_action_with_accels(self, name, callback, accels):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)
        if accels:
            self.set_accels_for_action(f"app.{{name}}", accels)

    def do_startup(self):
        Adw.Application.do_startup(self)
        # style.css is yours: colours, fonts, spacing and corner radii.
        css = Gtk.CssProvider()
        css.load_from_path(str(Path(__file__).with_name("style.css")))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        window = self.props.active_window or MainWindow(application=self)
        window.present()

    def on_about(self, *_):
        about = Adw.AboutWindow(transient_for=self.props.active_window, application_name="{name}",
                                application_icon=APP_ID, version="1.0", developer_name="{developer}")
        about.present()


def main():
    return Application().run(sys.argv)
'''

PY_WINDOW = '''from gi.repository import Adw, Gtk

from .model import Counter


class MainWindow(Adw.ApplicationWindow):
    """The main window: a header bar, then your content."""

    def __init__(self, **kwargs):
        super().__init__(title="{name}", default_width=480, default_height=560, **kwargs)
        self.counter = Counter()

        menu = Gtk.PopoverMenu.new_from_model(self.app_menu())
        header = Adw.HeaderBar()
        header.pack_end(Gtk.MenuButton(icon_name="open-menu-symbolic", popover=menu))

        self.value = Gtk.Label(label=self.counter.text, css_classes=["counter"])
        title = Gtk.Label(label="Hello, world!", css_classes=["title-1"])
        subtitle = Gtk.Label(label="Edit window.py and style.css to make this app your own.",
                             css_classes=["dim-label"], wrap=True, justify=Gtk.Justification.CENTER)

        minus = Gtk.Button(icon_name="list-remove-symbolic", css_classes=["circular", "flat"])
        plus = Gtk.Button(label="Add One", css_classes=["pill", "suggested-action"])
        minus.connect("clicked", lambda *_: self.change(-1))
        plus.connect("clicked", lambda *_: self.change(+1))
        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER)
        buttons.append(minus)
        buttons.append(plus)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, css_classes=["card", "hero"],
                       valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER)
        for widget in (title, self.value, buttons, subtitle):
            card.append(widget)

        clamp = Adw.Clamp(maximum_size=420, child=card, margin_top=24, margin_bottom=24, margin_start=18, margin_end=18)
        view = Adw.ToolbarView(content=clamp)
        view.add_top_bar(header)
        self.set_content(view)

    @staticmethod
    def app_menu():
        from gi.repository import Gio
        menu = Gio.Menu()
        menu.append("About {name}", "app.about")
        menu.append("Quit", "app.quit")
        return menu

    def change(self, delta):
        self.counter.add(delta)
        self.value.set_label(self.counter.text)
'''

PY_MODEL = '''class Counter:
    """Your app's data, kept apart from the interface so it's easy to test."""

    def __init__(self, value=0):
        self.value = value

    def add(self, delta=1):
        self.value += delta
        return self.value

    @property
    def text(self):
        return str(self.value)
'''

PY_STYLE = '''/* Your app's look, in GTK CSS. Change the accent colour, fonts, spacing and
   corners here; see https://docs.gtk.org/gtk4/css-properties.html */

@define-color accent_bg_color {accent};
@define-color accent_color {accent};

.hero {{
  padding: 32px 28px;
  border-radius: 24px;
}}

.counter {{
  font-size: 72px;
  font-weight: 800;
  font-feature-settings: "tnum";
}}
'''


def python_files(template: str, root: pathlib.Path, name: str, org: str, tests: bool, bundle_id: str = "",
                 options: dict | None = None, **_) -> dict:
    options = options or {}
    package = snake_name(name)
    h = lambda f: file_header(f, name, org)  # noqa: E731
    files: dict = {}
    if template == "python-app":
        app_id = application_id(bundle_id or bundle_identifier("org.example", name))
        accent = options.get("accent") or "#0a84ff"
        files[root / "main.py"] = "#!/usr/bin/env python3\n" + h("main.py") + (
            f"import sys\n\nfrom {package}.application import main\n\nif __name__ == \"__main__\":\n    sys.exit(main())\n")
        files[root / package / "__init__.py"] = ""
        files[root / package / "application.py"] = h("application.py") + PY_APPLICATION.format(
            app_id=app_id, name=name, developer=org or author_name())
        files[root / package / "window.py"] = h("window.py") + PY_WINDOW.format(name=name)
        files[root / package / "model.py"] = h("model.py") + PY_MODEL
        files[root / package / "style.css"] = h("style.css") + PY_STYLE.format(accent=accent)
        if tests:
            files[root / "tests" / "__init__.py"] = ""
            files[root / "tests" / "test_model.py"] = h("test_model.py") + (
                f"import unittest\n\nfrom {package}.model import Counter\n\n\nclass CounterTests(unittest.TestCase):\n"
                "    def test_counts_up_and_down(self):\n        c = Counter()\n        c.add()\n        c.add()\n"
                "        c.add(-1)\n        self.assertEqual(c.text, \"1\")\n\n\nif __name__ == \"__main__\":\n    unittest.main()\n")
        deps = '"PyGObject>=3.48"'
    else:
        files[root / "main.py"] = "#!/usr/bin/env python3\n" + h("main.py") + (
            "def greeting(name):\n    return f\"Hello, {name}!\"\n\n\n"
            "def main():\n    print(\"Hello, World!\")\n    try:\n        name = input(\"What's your name? \")\n"
            "    except EOFError:\n        return\n    print(greeting(name.strip() or \"there\"))\n\n\n"
            "if __name__ == \"__main__\":\n    main()\n")
        if tests:
            files[root / "tests" / "__init__.py"] = ""
            files[root / "tests" / "test_main.py"] = h("test_main.py") + (
                "import unittest\n\nfrom main import greeting\n\n\nclass GreetingTests(unittest.TestCase):\n"
                "    def test_greeting(self):\n        self.assertEqual(greeting(\"LCode\"), \"Hello, LCode!\")\n\n\n"
                "if __name__ == \"__main__\":\n    unittest.main()\n")
        deps = ""
    files[root / "pyproject.toml"] = (f'[project]\nname = "{slug_name(name)}"\nversion = "1.0.0"\n'
                                      f'requires-python = ">=3.10"\ndependencies = [{deps}]\n')
    files[root / ".gitignore"] = "__pycache__/\n*.pyc\n.venv/\n/dist\n.lcode/userdata/\n"
    return files


# ------------------------------------------------------------------- rust

RUST_APP = '''use adw::prelude::*;
use gtk::{{gdk, glib}};
use std::cell::Cell;
use std::rc::Rc;

const APP_ID: &str = "{app_id}";

fn main() -> glib::ExitCode {{
    let app = adw::Application::builder().application_id(APP_ID).build();
    app.connect_startup(|_| load_css());
    app.connect_activate(build_ui);
    app.run()
}}

/// style.css is yours: colours, fonts, spacing and corner radii.
fn load_css() {{
    let provider = gtk::CssProvider::new();
    provider.load_from_string(include_str!("style.css"));
    gtk::style_context_add_provider_for_display(
        &gdk::Display::default().expect("a display"),
        &provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}}

/// The text the counter shows. Kept apart from the interface so it's easy to test.
fn counter_text(count: i32) -> String {{
    count.to_string()
}}

fn build_ui(app: &adw::Application) {{
    let count = Rc::new(Cell::new(0));
    let value = gtk::Label::builder().label(counter_text(0)).css_classes(["counter"]).build();
    let title = gtk::Label::builder().label("Hello, world!").css_classes(["title-1"]).build();
    let subtitle = gtk::Label::builder()
        .label("Edit main.rs and style.css to make this app your own.")
        .css_classes(["dim-label"])
        .wrap(true)
        .justify(gtk::Justification::Center)
        .build();

    let minus = gtk::Button::builder().icon_name("list-remove-symbolic").css_classes(["circular", "flat"]).build();
    let plus = gtk::Button::builder().label("Add One").css_classes(["pill", "suggested-action"]).build();
    for (button, delta) in [(&minus, -1), (&plus, 1)] {{
        let count = count.clone();
        let value = value.clone();
        button.connect_clicked(move |_| {{
            count.set(count.get() + delta);
            value.set_label(&counter_text(count.get()));
        }});
    }}
    let buttons = gtk::Box::builder().spacing(12).halign(gtk::Align::Center).build();
    buttons.append(&minus);
    buttons.append(&plus);

    let card = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .css_classes(["card", "hero"])
        .valign(gtk::Align::Center)
        .halign(gtk::Align::Center)
        .build();
    card.append(&title);
    card.append(&value);
    card.append(&buttons);
    card.append(&subtitle);

    let clamp = adw::Clamp::builder().maximum_size(420).child(&card).margin_top(24).margin_bottom(24).build();
    let view = adw::ToolbarView::builder().content(&clamp).build();
    view.add_top_bar(&adw::HeaderBar::new());

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("{name}")
        .default_width(480)
        .default_height(560)
        .content(&view)
        .build();
    window.present();
}}

#[cfg(test)]
mod tests {{
    use super::*;

    #[test]
    fn counter_shows_the_count() {{
        assert_eq!(counter_text(3), "3");
    }}
}}
'''


def rust_files(template: str, root: pathlib.Path, name: str, org: str, tests: bool, bundle_id: str = "",
               options: dict | None = None, **_) -> dict:
    options = options or {}
    crate = slug_name(name)
    h = lambda f: file_header(f, name, org)  # noqa: E731
    files: dict = {}
    deps = ""
    if template == "rust-app":
        app_id = application_id(bundle_id or bundle_identifier("org.example", name))
        deps = ('adw = { package = "libadwaita", version = "0.9", features = ["v1_4"] }\n'
                'gtk = { package = "gtk4", version = "0.11", features = ["v4_12"] }\n')
        files[root / "src" / "main.rs"] = h("main.rs") + RUST_APP.format(app_id=app_id, name=name)
        files[root / "src" / "style.css"] = h("style.css") + PY_STYLE.format(accent=options.get("accent") or "#0a84ff")
    elif template == "rust-tool":
        files[root / "src" / "main.rs"] = h("main.rs") + (
            "use std::io::{self, BufRead, Write};\n\nfn greeting(name: &str) -> String {\n    format!(\"Hello, {name}!\")\n}\n\n"
            "fn main() {\n    println!(\"Hello, World!\");\n    print!(\"What's your name? \");\n    io::stdout().flush().ok();\n"
            "    let mut line = String::new();\n    if io::stdin().lock().read_line(&mut line).unwrap_or(0) > 0 {\n"
            "        println!(\"{}\", greeting(line.trim()));\n    }\n}\n" +
            ("\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn greets() {\n        assert_eq!(super::greeting(\"LCode\"), \"Hello, LCode!\");\n    }\n}\n"
             if tests else ""))
    else:
        files[root / "src" / "lib.rs"] = h("lib.rs") + (
            "/// A greeting for `name`.\npub fn greeting(name: &str) -> String {\n    format!(\"Hello, {name}!\")\n}\n" +
            ("\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn greets() {\n        assert_eq!(super::greeting(\"LCode\"), \"Hello, LCode!\");\n    }\n}\n"
             if tests else ""))
    files[root / "Cargo.toml"] = (f'[package]\nname = "{crate}"\nversion = "0.1.0"\nedition = "2021"\n\n'
                                  f'[dependencies]\n{deps}')
    files[root / ".gitignore"] = "/target\n.lcode/userdata/\n"
    return files


# ---------------------------------------------------------------------- c

C_APP = '''#include <adwaita.h>
#include "counter.h"

/* The window: a header bar, then your content. Your app's look lives in
   style.css, which libadwaita loads for you from the app's resources. */

typedef struct {{
  int count;
  GtkLabel *value;
}} AppState;

static void
change (AppState *state, int delta)
{{
  g_autofree char *text = NULL;

  state->count += delta;
  text = counter_text (state->count);
  gtk_label_set_label (state->value, text);
}}

static void on_minus (G_GNUC_UNUSED GtkButton *button, AppState *state) {{ change (state, -1); }}
static void on_plus (G_GNUC_UNUSED GtkButton *button, AppState *state) {{ change (state, +1); }}

static void
on_activate (AdwApplication *app, AppState *state)
{{
  GtkWidget *window, *view, *clamp, *card, *title, *subtitle, *buttons, *minus, *plus;

  title = gtk_label_new ("Hello, world!");
  gtk_widget_add_css_class (title, "title-1");
  state->value = GTK_LABEL (gtk_label_new ("0"));
  gtk_widget_add_css_class (GTK_WIDGET (state->value), "counter");
  subtitle = gtk_label_new ("Edit main.c and style.css to make this app your own.");
  gtk_widget_add_css_class (subtitle, "dim-label");
  gtk_label_set_wrap (GTK_LABEL (subtitle), TRUE);
  gtk_label_set_justify (GTK_LABEL (subtitle), GTK_JUSTIFY_CENTER);

  minus = gtk_button_new_from_icon_name ("list-remove-symbolic");
  gtk_widget_add_css_class (minus, "circular");
  gtk_widget_add_css_class (minus, "flat");
  plus = gtk_button_new_with_label ("Add One");
  gtk_widget_add_css_class (plus, "pill");
  gtk_widget_add_css_class (plus, "suggested-action");
  g_signal_connect (minus, "clicked", G_CALLBACK (on_minus), state);
  g_signal_connect (plus, "clicked", G_CALLBACK (on_plus), state);
  buttons = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_widget_set_halign (buttons, GTK_ALIGN_CENTER);
  gtk_box_append (GTK_BOX (buttons), minus);
  gtk_box_append (GTK_BOX (buttons), plus);

  card = gtk_box_new (GTK_ORIENTATION_VERTICAL, 18);
  gtk_widget_add_css_class (card, "card");
  gtk_widget_add_css_class (card, "hero");
  gtk_widget_set_valign (card, GTK_ALIGN_CENTER);
  gtk_widget_set_halign (card, GTK_ALIGN_CENTER);
  gtk_box_append (GTK_BOX (card), title);
  gtk_box_append (GTK_BOX (card), GTK_WIDGET (state->value));
  gtk_box_append (GTK_BOX (card), buttons);
  gtk_box_append (GTK_BOX (card), subtitle);

  clamp = adw_clamp_new ();
  adw_clamp_set_maximum_size (ADW_CLAMP (clamp), 420);
  adw_clamp_set_child (ADW_CLAMP (clamp), card);
  view = adw_toolbar_view_new ();
  adw_toolbar_view_add_top_bar (ADW_TOOLBAR_VIEW (view), adw_header_bar_new ());
  adw_toolbar_view_set_content (ADW_TOOLBAR_VIEW (view), clamp);

  window = adw_application_window_new (GTK_APPLICATION (app));
  gtk_window_set_title (GTK_WINDOW (window), "{name}");
  gtk_window_set_default_size (GTK_WINDOW (window), 480, 560);
  adw_application_window_set_content (ADW_APPLICATION_WINDOW (window), view);
  gtk_window_present (GTK_WINDOW (window));
}}

int
main (int argc, char *argv[])
{{
  g_autoptr (AdwApplication) app = adw_application_new ("{app_id}", G_APPLICATION_DEFAULT_FLAGS);
  AppState state = {{ 0 }};

  g_signal_connect (app, "activate", G_CALLBACK (on_activate), &state);
  return g_application_run (G_APPLICATION (app), argc, argv);
}}
'''


def c_files(template: str, root: pathlib.Path, name: str, org: str, tests: bool, bundle_id: str = "",
            options: dict | None = None, **_) -> dict:
    options = options or {}
    project = slug_name(name)
    h = lambda f: file_header(f, name, org)  # noqa: E731
    files: dict = {}
    if template == "c-app":
        app_id = application_id(bundle_id or bundle_identifier("org.example", name))
        prefix = "/" + app_id.replace(".", "/")
        files[root / "src" / "main.c"] = h("main.c") + C_APP.format(app_id=app_id, name=name.replace('"', '\\"'))
        files[root / "src" / "counter.h"] = h("counter.h") + "#pragma once\n\n/* The counter's text; free it with g_free (). */\nchar *counter_text (int count);\n"
        files[root / "src" / "counter.c"] = h("counter.c") + '#include <glib.h>\n#include "counter.h"\n\nchar *\ncounter_text (int count)\n{\n  return g_strdup_printf ("%d", count);\n}\n'
        files[root / "src" / "style.css"] = h("style.css") + PY_STYLE.format(accent=options.get("accent") or "#0a84ff")
        files[root / "src" / f"{project}.gresource.xml"] = (
            f'<?xml version="1.0" encoding="UTF-8"?>\n<gresources>\n  <gresource prefix="{prefix}">\n'
            '    <file>style.css</file>\n  </gresource>\n</gresources>\n')
        test_block = (f"\ntest_exe = executable('test-counter', 'tests/test_counter.c', 'src/counter.c',\n"
                      f"  include_directories: include_directories('src'), dependencies: dependency('glib-2.0'))\n"
                      f"test('counter', test_exe)\n") if tests else ""
        files[root / "meson.build"] = (
            f"project('{project}', 'c', version: '0.1.0', default_options: ['warning_level=2', 'c_std=gnu11'])\n\n"
            "gnome = import('gnome')\nadw = dependency('libadwaita-1', version: '>= 1.4')\n"
            f"resources = gnome.compile_resources('resources', 'src/{project}.gresource.xml', source_dir: 'src')\n\n"
            f"executable('{project}', 'src/main.c', 'src/counter.c', resources, dependencies: adw, install: true)\n" + test_block)
        if tests:
            files[root / "tests" / "test_counter.c"] = h("test_counter.c") + (
                '#include <glib.h>\n#include "counter.h"\n\nstatic void\ntest_text (void)\n{\n'
                '  g_autofree char *text = counter_text (3);\n  g_assert_cmpstr (text, ==, "3");\n}\n\n'
                'int\nmain (int argc, char *argv[])\n{\n  g_test_init (&argc, &argv, NULL);\n'
                '  g_test_add_func ("/counter/text", test_text);\n  return g_test_run ();\n}\n')
    else:
        files[root / "src" / "main.c"] = h("main.c") + (
            '#include <stdio.h>\n#include <string.h>\n\nint\nmain (void)\n{\n  char name[256];\n\n'
            '  printf ("Hello, World!\\nWhat\'s your name? ");\n  fflush (stdout);\n'
            '  if (fgets (name, sizeof name, stdin)) {\n    name[strcspn (name, "\\n")] = 0;\n'
            '    printf ("Hello, %s!\\n", name);\n  }\n  return 0;\n}\n')
        files[root / "meson.build"] = (
            f"project('{project}', 'c', version: '0.1.0', default_options: ['warning_level=2', 'c_std=c11'])\n\n"
            f"executable('{project}', 'src/main.c', install: true)\n")
    files[root / ".gitignore"] = "/build\n/build-release\n.lcode/userdata/\n"
    return files


# --------------------------------------------------------------- creation

def create_project(parent: str, template: str, name: str, organization: str = "", org_id: str = "",
                   tests: bool = True, git: bool = True, default_simulator: str = "lphone-16",
                   options: dict | None = None) -> str:
    if template not in TEMPLATE_INFO:
        raise ValueError(f"Unknown template “{template}”.")
    name = name.strip()
    if not name or "/" in name:
        raise ValueError("Enter a product name.")
    root = pathlib.Path(parent).expanduser() / name
    if root.exists() and any(root.iterdir()):
        raise FileExistsError(f"“{root}” already exists and is not empty.")
    toolchain, kind, _ = TEMPLATE_INFO[template]
    bundle_id = bundle_identifier(org_id, name)
    args = dict(root=root, name=name, org=organization, tests=tests, bundle_id=bundle_id, options=options or {})
    if toolchain == "swift":
        files = swift_files(template, **args)
    elif toolchain == "python":
        files = python_files(template, **args)
    elif toolchain == "cargo":
        files = rust_files(template, **args)
    elif toolchain == "meson":
        files = c_files(template, **args)
    else:
        import lcode_design as design
        files = design.template_files(**args)

    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    if (root / "main.py").is_file():
        os.chmod(root / "main.py", 0o755)
    meta = {
        "toolchain": toolchain,
        "kind": kind,
        "bundle_identifier": bundle_id,
        "organization": organization,
        "display_name": name,
        "version": "1.0",
        "default_destination": HOST if kind != "app" or toolchain == "goldengate" else default_simulator,
    }
    if (options or {}).get("accent"):
        meta["accent"] = options["accent"]
    write_json(root / ".lcode/project.json", meta)
    if git:
        git_init(root)
    return str(root)


def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def git_init(root: pathlib.Path) -> None:
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        if git("init", "--quiet").returncode:
            return
    except OSError:
        return
    git("add", "-A")
    identity = []
    if not git("config", "user.email").stdout.strip():
        identity = ["-c", f"user.name={author_name()}", "-c", f"user.email={getpass.getuser()}@localhost"]
    git(*identity, "commit", "--quiet", "-m", "Initial Commit")


# -------------------------------------------------------------- new files

def new_file_contents(name: str, project: str, organization: str = "") -> str:
    """File ▸ New ▸ File…: a starting point that suits the file's language."""
    h = file_header(name, project, organization)
    if name.endswith("View.swift"):
        view = module_name(name[: -len(".swift")])
        return h + (f"import SwiftCrossUI\n\nstruct {view}: View {{\n    var body: some View {{\n"
                    "        Text(\"Hello, world!\")\n    }\n}\n")
    if name.endswith(".swift"):
        return h + "import Foundation\n\n"
    if name.endswith(".py"):
        return h
    if name.endswith(".rs"):
        return h
    if name.endswith(".h"):
        return h + "#pragma once\n\n"
    if name.endswith(".c"):
        stem = name[:-2]
        return h + f'#include "{stem}.h"\n\n'
    if name.endswith(".qml"):
        return h + "import QtQuick\n\nItem {\n}\n"
    if name.endswith(".css"):
        return h
    return ""
