//! The workspace window: toolbar, navigator, editor, debug area and
//! inspector, plus the build / run / test pipeline.

pub mod activity;
pub mod console;
pub mod editor;
pub mod inspector;
pub mod navigator;
pub mod open_quickly;

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};

use crate::diagnostics::{self, Diagnostic, Severity};
use crate::process::{LineBuffer, ProcEvent, RunningProcess};
use crate::project::{HOST_DESTINATION, Project, ProjectKind, UserState};
use crate::simulator;
use activity::Activity;
use console::{Console, Stream};
use editor::Editor;
use inspector::Inspector;
use navigator::{Navigator, Page, ReportStatus};

thread_local! {
    /// Open workspaces. This registry owns them; UI callbacks hold weak references.
    static WORKSPACES: RefCell<Vec<Rc<Workspace>>> = const { RefCell::new(Vec::new()) };
}

pub fn all() -> Vec<Rc<Workspace>> {
    WORKSPACES.with(|w| w.borrow().clone())
}

/// Open a project folder in a workspace window (or focus the existing one).
pub fn open(app: &adw::Application, path: &Path) -> Rc<Workspace> {
    let root = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    if let Some(ws) = all().into_iter().find(|w| w.project.borrow().root == root) {
        ws.window.present();
        return ws;
    }
    crate::settings::add_recent_project(&root);
    let ws = Workspace::new(app, &root);
    WORKSPACES.with(|w| w.borrow_mut().push(ws.clone()));
    crate::welcome::close();
    ws.window.present();
    ws
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TaskKind {
    Build,
    Test,
    Clean,
    Run,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum After {
    Nothing,
    Run,
}

struct Task {
    kind: TaskKind,
    process: Option<Rc<RunningProcess>>,
    in_simulator: bool,
    cancelled: bool,
}

struct Report {
    title: String,
    log: String,
    row: gtk::Box,
}

pub struct Workspace {
    app: adw::Application,
    pub window: adw::ApplicationWindow,
    project: RefCell<Project>,
    editor: Rc<Editor>,
    navigator: Rc<Navigator>,
    console: Rc<Console>,
    inspector: Rc<Inspector>,
    activity: Activity,
    toast: adw::ToastOverlay,
    nav_pane: gtk::Paned,
    center_pane: gtk::Paned,
    inspector_box: gtk::Box,
    scheme_label: gtk::Label,
    scheme_menu: gio::Menu,
    destination_label: gtk::Label,
    destination_icon: gtk::Image,
    scheme: RefCell<Option<String>>,
    destination: RefCell<String>,
    task: RefCell<Option<Task>>,
    task_generation: Cell<u64>,
    reports: RefCell<Vec<Report>>,
    diagnostics: RefCell<Vec<Diagnostic>>,
    closing: Cell<bool>,
}

fn destination_name(id: &str) -> String {
    if id == HOST_DESTINATION {
        "My Linux PC".into()
    } else {
        simulator::device::by_id(id).map(|d| d.name.to_string()).unwrap_or_else(|| id.to_string())
    }
}

fn destination_icon(id: &str) -> &'static str {
    match simulator::device::by_id(id) {
        Some(d) if d.tablet => "tablet-symbolic",
        Some(_) => "phone-symbolic",
        None => "computer-symbolic",
    }
}

impl Workspace {
    fn new(app: &adw::Application, root: &Path) -> Rc<Self> {
        let project = Project::open(root);
        let user = project.load_user_state();

        let editor = Editor::new(&project.root, &project.name);
        let navigator = Navigator::new(&project.root, &project.name);
        let console = Console::new();
        let inspector = Inspector::new(&project);
        let activity = Activity::new(&project.name);

        // ---- Toolbar ----
        let header = adw::HeaderBar::new();
        header.add_css_class("lcode-toolbar");
        let nav_toggle = gtk::Button::builder()
            .icon_name("sidebar-show-symbolic")
            .tooltip_text("Hide or show the Navigator (Ctrl+0)")
            .action_name("win.toggle-navigator")
            .build();
        let run_button = gtk::Button::builder()
            .icon_name("media-playback-start-symbolic")
            .tooltip_text("Build and then run the current scheme (Ctrl+R)")
            .action_name("win.run")
            .build();
        run_button.add_css_class("run-button");
        run_button.add_css_class("flat");
        let stop_button = gtk::Button::builder()
            .icon_name("media-playback-stop-symbolic")
            .tooltip_text("Stop the running scheme or build (Ctrl+.)")
            .action_name("win.stop")
            .build();
        stop_button.add_css_class("run-button");
        stop_button.add_css_class("flat");

        let scheme_label = gtk::Label::new(None);
        let scheme_icon = gtk::Image::from_icon_name(match project.meta.kind {
            ProjectKind::App => crate::APP_ID,
            ProjectKind::Tool => "utilities-terminal-symbolic",
            ProjectKind::Library => "package-x-generic-symbolic",
        });
        let scheme_content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        scheme_content.append(&scheme_icon);
        scheme_content.append(&scheme_label);
        let scheme_menu = gio::Menu::new();
        let scheme_button = gtk::MenuButton::builder()
            .child(&scheme_content)
            .menu_model(&scheme_menu)
            .tooltip_text("Scheme")
            .build();
        scheme_button.add_css_class("flat");

        let destination_label = gtk::Label::new(None);
        let destination_icon = gtk::Image::new();
        let dest_content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        dest_content.append(&destination_icon);
        dest_content.append(&destination_label);
        let dest_menu = gio::Menu::new();
        let host = gio::Menu::new();
        host.append(Some("My Linux PC"), Some(&format!("win.destination::{HOST_DESTINATION}")));
        dest_menu.append_section(Some("Host"), &host);
        let sims = gio::Menu::new();
        for d in simulator::DEVICES {
            sims.append(Some(d.name), Some(&format!("win.destination::{}", d.id)));
        }
        dest_menu.append_section(Some("Simulators"), &sims);
        let dest_button = gtk::MenuButton::builder()
            .child(&dest_content)
            .menu_model(&dest_menu)
            .tooltip_text("Run Destination")
            .build();
        dest_button.add_css_class("flat");

        let chevron = gtk::Image::from_icon_name("go-next-symbolic");
        chevron.add_css_class("separator-chevron");
        let scheme_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        scheme_box.add_css_class("scheme-selector");
        scheme_box.append(&scheme_button);
        scheme_box.append(&chevron);
        scheme_box.append(&dest_button);

        header.pack_start(&nav_toggle);
        header.pack_start(&run_button);
        header.pack_start(&stop_button);
        header.pack_start(&scheme_box);
        header.set_title_widget(Some(&activity.widget));
        let inspector_toggle = gtk::Button::builder()
            .icon_name("sidebar-show-right-symbolic")
            .tooltip_text("Hide or show the Inspectors (Ctrl+Alt+0)")
            .action_name("win.toggle-inspector")
            .build();
        let debug_toggle = gtk::Button::builder()
            .icon_name("lcode-debug-area-symbolic")
            .tooltip_text("Hide or show the Debug Area (Shift+Ctrl+Y)")
            .action_name("win.toggle-debug-area")
            .build();
        header.pack_end(&inspector_toggle);
        header.pack_end(&debug_toggle);

        // ---- Layout ----
        let center_pane = gtk::Paned::new(gtk::Orientation::Vertical);
        center_pane.set_start_child(Some(&editor.widget));
        center_pane.set_end_child(Some(&console.widget));
        center_pane.set_resize_end_child(false);
        center_pane.set_shrink_end_child(false);
        center_pane.set_shrink_start_child(false);
        center_pane.set_hexpand(true);

        let inspector_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        inspector_box.append(&gtk::Separator::new(gtk::Orientation::Vertical));
        inspector_box.append(&inspector.widget);
        let main_row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        main_row.append(&center_pane);
        main_row.append(&inspector_box);

        let nav_pane = gtk::Paned::new(gtk::Orientation::Horizontal);
        nav_pane.set_start_child(Some(&navigator.widget));
        nav_pane.set_end_child(Some(&main_row));
        nav_pane.set_resize_start_child(false);
        nav_pane.set_shrink_start_child(false);
        nav_pane.set_shrink_end_child(false);
        nav_pane.set_position(260);

        let toast = adw::ToastOverlay::new();
        toast.set_child(Some(&nav_pane));

        let menubar = gtk::PopoverMenuBar::from_model(Some(&crate::menus::menubar()));
        let toolbar_view = adw::ToolbarView::new();
        toolbar_view.add_top_bar(&menubar);
        toolbar_view.add_top_bar(&header);
        toolbar_view.set_content(Some(&toast));

        let window = adw::ApplicationWindow::builder()
            .application(app)
            .title(format!("{} — LCode", project.name))
            .default_width(1360)
            .default_height(860)
            .content(&toolbar_view)
            .build();

        let initial_destination = user
            .destination
            .clone()
            .filter(|d| d == HOST_DESTINATION || simulator::device::by_id(d).is_some())
            .unwrap_or_else(|| {
                if !project.meta.default_destination.is_empty() {
                    project.meta.default_destination.clone()
                } else if project.meta.kind == ProjectKind::App {
                    crate::settings::get().default_simulator
                } else {
                    HOST_DESTINATION.into()
                }
            });

        let ws = Rc::new(Workspace {
            app: app.clone(),
            window,
            project: RefCell::new(project),
            editor,
            navigator,
            console,
            inspector,
            activity,
            toast,
            nav_pane,
            center_pane,
            inspector_box,
            scheme_label,
            scheme_menu,
            destination_label,
            destination_icon,
            scheme: RefCell::new(user.scheme.clone()),
            destination: RefCell::new(initial_destination),
            task: RefCell::new(None),
            task_generation: Cell::new(0),
            reports: RefCell::new(Vec::new()),
            diagnostics: RefCell::new(Vec::new()),
            closing: Cell::new(false),
        });

        ws.setup_actions();
        ws.wire_components();
        ws.refresh_schemes();
        ws.update_destination();
        ws.update_task_actions();
        ws.restore_user_state(&user);
        ws.place_debug_area();
        ws
    }

    pub fn root(&self) -> PathBuf {
        self.project.borrow().root.clone()
    }

    fn toast(&self, message: &str) {
        self.toast.add_toast(adw::Toast::new(message));
    }

    fn alert(&self, heading: &str, body: &str) {
        let dialog = adw::AlertDialog::new(Some(heading), Some(body));
        dialog.add_response("ok", "OK");
        dialog.present(Some(&self.window));
    }

    // ---- Wiring ---------------------------------------------------------------------

    fn wire_components(self: &Rc<Self>) {
        let weak = Rc::downgrade(self);
        self.navigator.connect_open(move |path, loc| {
            if let Some(ws) = weak.upgrade() {
                ws.open_file(&path, loc);
            }
        });
        let weak = Rc::downgrade(self);
        self.navigator.connect_open_report(move |index| {
            if let Some(ws) = weak.upgrade() {
                let report = ws.reports.borrow().get(index).map(|r| (r.title.clone(), r.log.clone()));
                if let Some((title, log)) = report {
                    ws.editor.open_text(&title, if log.is_empty() { "(no output)" } else { &log });
                }
            }
        });
        let weak = Rc::downgrade(self);
        self.navigator.connect_deleted(move |path| {
            if let Some(ws) = weak.upgrade() {
                ws.editor.forget(&path);
            }
        });
        let weak = Rc::downgrade(self);
        self.editor.connect_open_request(move |path, loc| {
            if let Some(ws) = weak.upgrade() {
                ws.open_file(&path, loc);
            }
        });
        let weak = Rc::downgrade(self);
        self.editor.connect_current_changed(move |doc| {
            if let Some(ws) = weak.upgrade() {
                let root = ws.root();
                ws.inspector.show_document(doc, &root);
            }
        });
        let weak = Rc::downgrade(self);
        self.console.connect_input(move |line| {
            if let Some(ws) = weak.upgrade()
                && let Some(p) = ws.task.borrow().as_ref().and_then(|t| t.process.clone()) {
                    p.write_stdin(&line);
                }
        });
        let weak = Rc::downgrade(self);
        self.inspector.connect_project_changed(move |kind, bundle| {
            if let Some(ws) = weak.upgrade() {
                let mut project = ws.project.borrow_mut();
                project.meta.kind = kind;
                project.meta.bundle_identifier = bundle;
                let _ = project.save_meta();
            }
        });
        let weak = Rc::downgrade(self);
        self.window.connect_close_request(move |_| {
            let Some(ws) = weak.upgrade() else { return glib::Propagation::Proceed };
            ws.request_close()
        });
    }

    /// Keep the debug area at a fixed default height as the window settles,
    /// until the user drags the divider themselves.
    fn place_debug_area(self: &Rc<Self>) {
        const DEBUG_HEIGHT: i32 = 220;
        // Re-apply the default for a moment after the first allocation, while the
        // window settles; after that the user owns the divider.
        let first_placed: Rc<Cell<Option<std::time::Instant>>> = Rc::default();
        let console = self.console.widget.clone();
        self.center_pane.connect_max_position_notify(move |pane| {
            let settling = first_placed.get().is_none_or(|t| t.elapsed() < std::time::Duration::from_secs(1));
            // max-position already excludes the debug area's minimum height.
            let (console_min, _, _, _) = console.measure(gtk::Orientation::Vertical, -1);
            let total = pane.max_position() + console_min;
            if settling && total > 2 * DEBUG_HEIGHT {
                if first_placed.get().is_none() {
                    first_placed.set(Some(std::time::Instant::now()));
                }
                pane.set_position(total - DEBUG_HEIGHT.max(console_min));
            }
        });
    }

    fn restore_user_state(self: &Rc<Self>, user: &UserState) {
        for path in user.open_files.iter().filter(|p| p.is_file()) {
            let _ = self.editor.open(path, None);
        }
        let selected = user.selected_file.clone().filter(|p| p.is_file());
        if let Some(p) = selected {
            let _ = self.editor.open(&p, None);
        } else if user.open_files.is_empty() {
            // First open: show the main source file, like a fresh project would.
            if let Some(main) = self.default_file() {
                let _ = self.editor.open(&main, None);
            }
        }
    }

    fn default_file(&self) -> Option<PathBuf> {
        let root = self.root();
        let files = crate::project::walk_files(&root.join("Sources"), 200);
        files
            .iter()
            .find(|p| p.file_name().is_some_and(|n| n == "ContentView.swift" || n == "main.swift"))
            .or_else(|| files.iter().find(|p| p.extension().is_some_and(|e| e == "swift")))
            .cloned()
            .or_else(|| Some(root.join("Package.swift")).filter(|p| p.is_file()))
    }

    fn save_user_state(&self) {
        let state = UserState {
            open_files: self.editor.open_files(),
            selected_file: self.editor.current().and_then(|d| d.path.clone()),
            scheme: self.scheme.borrow().clone(),
            destination: Some(self.destination.borrow().clone()),
        };
        self.project.borrow().save_user_state(&state);
    }

    fn request_close(self: &Rc<Self>) -> glib::Propagation {
        if self.closing.get() {
            return glib::Propagation::Proceed;
        }
        if self.editor.has_unsaved_changes() {
            let dialog = adw::AlertDialog::new(
                Some("Do you want to save the changes to the open files?"),
                Some("Your changes will be lost if you don't save them."),
            );
            dialog.add_responses(&[("cancel", "Cancel"), ("discard", "Don't Save"), ("save", "Save All")]);
            dialog.set_response_appearance("discard", adw::ResponseAppearance::Destructive);
            dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
            dialog.set_close_response("cancel");
            let weak = Rc::downgrade(self);
            dialog.connect_response(None, move |_, response| {
                let Some(ws) = weak.upgrade() else { return };
                match response {
                    "save" => match ws.editor.save_all() {
                        Ok(()) => ws.finish_close(),
                        Err(e) => ws.alert("Couldn't Save", &e),
                    },
                    "discard" => ws.finish_close(),
                    _ => {}
                }
            });
            dialog.present(Some(&self.window));
            return glib::Propagation::Stop;
        }
        self.finish_close();
        glib::Propagation::Stop
    }

    fn finish_close(self: &Rc<Self>) {
        self.save_user_state();
        self.stop();
        self.closing.set(true);
        WORKSPACES.with(|w| w.borrow_mut().retain(|x| !Rc::ptr_eq(x, self)));
        self.window.close();
        if all().is_empty() {
            crate::welcome::present(&self.app);
        }
    }

    pub fn open_file(self: &Rc<Self>, path: &Path, loc: Option<(u32, u32)>) {
        if let Err(e) = self.editor.open(path, loc) {
            self.toast(&e);
        }
    }

    // ---- Schemes & destinations --------------------------------------------------------

    fn refresh_schemes(self: &Rc<Self>) {
        let products = self.project.borrow().executable_products();
        let current = self.scheme.borrow().clone();
        let scheme = current.filter(|s| products.contains(s)).or_else(|| products.first().cloned());
        *self.scheme.borrow_mut() = scheme.clone();

        self.scheme_menu.remove_all();
        let section = gio::Menu::new();
        if products.is_empty() {
            section.append(Some("No Executable Products"), Some("win.none"));
        }
        for p in &products {
            section.append(Some(p), Some(&format!("win.scheme::{p}")));
        }
        self.scheme_menu.append_section(Some("Schemes"), &section);
        let manage = gio::Menu::new();
        manage.append(Some("Edit Package.swift…"), Some("win.edit-manifest"));
        self.scheme_menu.append_section(None, &manage);

        let name = scheme.clone().unwrap_or_else(|| self.project.borrow().name.clone());
        self.scheme_label.set_text(&name);
        self.activity.set_title(&name);
        if let Some(action) = self.window.lookup_action("scheme").and_downcast::<gio::SimpleAction>() {
            action.set_state(&scheme.unwrap_or_default().to_variant());
        }
    }

    fn update_destination(&self) {
        let id = self.destination.borrow().clone();
        self.destination_label.set_text(&destination_name(&id));
        self.destination_icon.set_icon_name(Some(destination_icon(&id)));
        if let Some(action) = self.window.lookup_action("destination").and_downcast::<gio::SimpleAction>() {
            action.set_state(&id.to_variant());
        }
    }

    // ---- Actions ---------------------------------------------------------------------------

    fn action(self: &Rc<Self>, name: &str, f: impl Fn(&Rc<Workspace>) + 'static) {
        let action = gio::SimpleAction::new(name, None);
        let weak = Rc::downgrade(self);
        action.connect_activate(move |_, _| {
            if let Some(ws) = weak.upgrade() {
                f(&ws);
            }
        });
        self.window.add_action(&action);
    }

    fn setup_actions(self: &Rc<Self>) {
        // File
        self.action("new-file", |ws| {
            let dir = ws
                .editor
                .current()
                .and_then(|d| d.path.clone())
                .and_then(|p| p.parent().map(Path::to_path_buf))
                .unwrap_or_else(|| ws.root());
            let _ = ws.navigator.widget.activate_action("nav.new-file", Some(&dir.display().to_string().to_variant()));
        });
        self.action("open-quickly", |ws| {
            let weak = Rc::downgrade(ws);
            open_quickly::present(&ws.window, &ws.root(), move |path| {
                if let Some(ws) = weak.upgrade() {
                    ws.open_file(&path, None);
                }
            });
        });
        self.action("close-tab", |ws| ws.editor.close_current());
        self.action("close", |ws| ws.window.close());
        self.action("save", |ws| {
            match ws.editor.save_current() {
                Ok(()) => {}
                Err(e) => ws.alert("Couldn't Save", &e),
            }
            ws.after_save();
        });
        self.action("save-all", |ws| {
            if let Err(e) = ws.editor.save_all() {
                ws.alert("Couldn't Save", &e);
            }
            ws.after_save();
        });
        self.action("edit-manifest", |ws| {
            let manifest = ws.root().join("Package.swift");
            ws.open_file(&manifest, None);
        });
        self.action("none", |_| {});

        // Edit
        self.action("undo", |ws| {
            ws.editor.with_view(|_, b| {
                if b.can_undo() {
                    b.undo();
                }
            })
        });
        self.action("redo", |ws| {
            ws.editor.with_view(|_, b| {
                if b.can_redo() {
                    b.redo();
                }
            })
        });
        self.action("cut", |ws| ws.editor.with_view(|v, _| v.emit_by_name::<()>("cut-clipboard", &[])));
        self.action("copy", |ws| ws.editor.with_view(|v, _| v.emit_by_name::<()>("copy-clipboard", &[])));
        self.action("paste", |ws| ws.editor.with_view(|v, _| v.emit_by_name::<()>("paste-clipboard", &[])));
        self.action("select-all", |ws| ws.editor.with_view(|_, b| b.select_range(&b.start_iter(), &b.end_iter())));
        self.action("toggle-comment", |ws| ws.editor.toggle_comment());
        self.action("go-to-line", |ws| ws.prompt_go_to_line());

        // Find
        self.action("find", |ws| ws.editor.show_find());
        self.action("find-next", |ws| ws.editor.find(true, false));
        self.action("find-previous", |ws| ws.editor.find(false, false));
        self.action("find-in-project", |ws| {
            let selection = ws.editor.current().and_then(|d| {
                d.buffer.selection_bounds().map(|(s, e)| d.buffer.text(&s, &e, false).to_string())
            });
            ws.navigator_visible(true);
            ws.navigator.focus_find(selection.as_deref());
        });

        // View
        self.action("toggle-navigator", |ws| {
            let visible = !ws.navigator.widget.is_visible();
            ws.navigator_visible(visible);
        });
        self.action("toggle-debug-area", |ws| ws.console.widget.set_visible(!ws.console.widget.is_visible()));
        self.action("toggle-inspector", |ws| ws.inspector_box.set_visible(!ws.inspector_box.is_visible()));
        self.action("clear-console", |ws| ws.console.clear());
        for (name, page) in [
            ("show-project-navigator", Page::Project),
            ("show-find-navigator", Page::Find),
            ("show-issue-navigator", Page::Issues),
            ("show-report-navigator", Page::Reports),
        ] {
            self.action(name, move |ws| {
                ws.navigator_visible(true);
                ws.navigator.show_page(page);
            });
        }
        let minimap = gio::SimpleAction::new_stateful("toggle-minimap", None, &crate::settings::get().show_minimap.to_variant());
        let weak = Rc::downgrade(self);
        minimap.connect_activate(move |action, _| {
            let Some(ws) = weak.upgrade() else { return };
            let on = !action.state().and_then(|s| s.get::<bool>()).unwrap_or(true);
            action.set_state(&on.to_variant());
            crate::settings::update(|s| s.show_minimap = on);
            ws.editor.set_minimap_visible(on);
        });
        self.window.add_action(&minimap);

        // Product
        self.action("run", |ws| ws.start_build(After::Run));
        self.action("build", |ws| ws.start_build(After::Nothing));
        self.action("test", |ws| ws.start_test());
        self.action("clean", |ws| ws.start_clean());
        self.action("stop", |ws| ws.stop());

        let scheme = gio::SimpleAction::new_stateful("scheme", Some(glib::VariantTy::STRING), &String::new().to_variant());
        let weak = Rc::downgrade(self);
        scheme.connect_activate(move |action, param| {
            let (Some(ws), Some(s)) = (weak.upgrade(), param.and_then(|p| p.get::<String>())) else { return };
            action.set_state(&s.to_variant());
            *ws.scheme.borrow_mut() = Some(s);
            ws.refresh_schemes();
        });
        self.window.add_action(&scheme);

        let destination = gio::SimpleAction::new_stateful(
            "destination",
            Some(glib::VariantTy::STRING),
            &self.destination.borrow().to_variant(),
        );
        let weak = Rc::downgrade(self);
        destination.connect_activate(move |action, param| {
            let (Some(ws), Some(d)) = (weak.upgrade(), param.and_then(|p| p.get::<String>())) else { return };
            action.set_state(&d.to_variant());
            *ws.destination.borrow_mut() = d;
            ws.update_destination();
        });
        self.window.add_action(&destination);
    }

    fn navigator_visible(&self, visible: bool) {
        self.navigator.widget.set_visible(visible);
        if visible && self.nav_pane.position() < 120 {
            self.nav_pane.set_position(260);
        }
    }

    fn after_save(self: &Rc<Self>) {
        let manifest_open = self.editor.current().and_then(|d| d.path.clone()).is_some_and(|p| p.ends_with("Package.swift"));
        if manifest_open {
            self.refresh_schemes();
        }
    }

    fn prompt_go_to_line(self: &Rc<Self>) {
        let Some(doc) = self.editor.current() else { return };
        let dialog = adw::AlertDialog::new(Some("Go to Line"), None);
        let entry = gtk::Entry::builder().placeholder_text("Line number").activates_default(true).input_purpose(gtk::InputPurpose::Digits).build();
        dialog.set_extra_child(Some(&entry));
        dialog.add_responses(&[("cancel", "Cancel"), ("go", "Go")]);
        dialog.set_default_response(Some("go"));
        dialog.set_response_appearance("go", adw::ResponseAppearance::Suggested);
        let e = entry.clone();
        dialog.connect_response(Some("go"), move |_, _| {
            let text = e.text();
            let mut parts = text.split(':');
            let line = parts.next().and_then(|l| l.trim().parse().ok());
            let col = parts.next().and_then(|c| c.trim().parse().ok()).unwrap_or(1);
            if let Some(l) = line {
                doc.go_to(l, col);
            }
        });
        dialog.present(Some(&self.window));
        entry.grab_focus();
    }

    // ---- Build / Run / Test ---------------------------------------------------------------

    fn update_task_actions(&self) {
        let busy = self.task.borrow().is_some();
        if let Some(a) = self.window.lookup_action("stop").and_downcast::<gio::SimpleAction>() {
            a.set_enabled(busy);
        }
    }

    fn swift(&self) -> Option<PathBuf> {
        if !self.project.borrow().is_swift_package() {
            self.alert(
                "No Package.swift",
                "LCode builds Swift packages. Add a Package.swift to this folder, or create a new project with File ▸ New ▸ Project.",
            );
            return None;
        }
        let swift = crate::settings::swift_executable();
        if swift.is_none() {
            self.alert(
                "Swift Toolchain Not Found",
                "LCode needs a Swift toolchain to build projects.\n\nOn Arch Linux, install one from the AUR (for example “swift-bin”) or with swiftly. If it isn't on your PATH, set its location in LCode ▸ Settings.",
            );
        }
        swift
    }

    /// Stop whatever is running, then claim a new task generation.
    fn begin_task(&self, kind: TaskKind) -> u64 {
        self.stop();
        let generation = self.task_generation.get() + 1;
        self.task_generation.set(generation);
        *self.task.borrow_mut() = Some(Task { kind, process: None, in_simulator: false, cancelled: false });
        self.update_task_actions();
        generation
    }

    fn is_current(&self, generation: u64) -> bool {
        self.task_generation.get() == generation
    }

    fn end_task(&self, generation: u64) -> Option<Task> {
        if !self.is_current(generation) {
            return None;
        }
        let task = self.task.borrow_mut().take();
        self.update_task_actions();
        self.console.set_input_enabled(false);
        task
    }

    fn set_diagnostics(&self, diagnostics: Vec<Diagnostic>) {
        let errors = diagnostics.iter().filter(|d| d.severity == Severity::Error).count();
        let warnings = diagnostics.iter().filter(|d| d.severity == Severity::Warning).count();
        self.activity.set_counts(errors, warnings);
        self.navigator.set_issues(&diagnostics);
        self.editor.set_diagnostics(&diagnostics);
        *self.diagnostics.borrow_mut() = diagnostics;
    }

    fn start_report(&self, title: &str) -> usize {
        let row = self.navigator.add_report(title);
        let mut reports = self.reports.borrow_mut();
        let serial = reports.len() + 1;
        reports.insert(0, Report { title: format!("{title} ({serial})"), log: String::new(), row });
        serial
    }

    /// Reports are stored newest-first; `serial` is the count when it was created.
    fn with_report(&self, serial: usize, f: impl FnOnce(&mut Report)) {
        let mut reports = self.reports.borrow_mut();
        let len = reports.len();
        if let Some(r) = reports.get_mut(len - serial) {
            f(r);
        }
    }

    fn start_build(self: &Rc<Self>, after: After) {
        let Some(swift) = self.swift() else { return };
        if let Err(e) = self.editor.save_all() {
            self.alert("Couldn't Save", &e);
            return;
        }
        let scheme = self.scheme.borrow().clone();
        if after == After::Run && scheme.is_none() {
            self.toast("This package has no executable product to run. Building instead.");
        }
        let after = if scheme.is_some() { after } else { After::Nothing };
        let generation = self.begin_task(TaskKind::Build);
        let root = self.root();
        let mut cmd = Command::new(&swift);
        cmd.arg("build").current_dir(&root);
        if let Some(s) = &scheme {
            cmd.args(["--product", s]);
        }
        let target = scheme.clone().unwrap_or_else(|| self.project.borrow().name.clone());
        self.set_diagnostics(Vec::new());
        let serial = self.start_report(&format!("Build {target}"));
        self.activity.set_status(&format!("Building {target}…"));
        self.activity.set_progress(Some(-1.0));
        self.run_tool(cmd, generation, serial, false, move |ws, code, cancelled| {
            let has_errors = ws.diagnostics.borrow().iter().any(|d| d.severity == Severity::Error);
            if cancelled {
                ws.activity.set_status_timestamped("Build Cancelled");
            } else if code == Some(0) && !has_errors {
                ws.activity.set_status_timestamped("Build Succeeded");
                if after == After::Run {
                    ws.launch(&target);
                }
                return true;
            } else {
                ws.activity.set_status_timestamped("Build Failed");
                ws.reveal_first_error();
            }
            false
        });
    }

    fn start_test(self: &Rc<Self>) {
        let Some(swift) = self.swift() else { return };
        if let Err(e) = self.editor.save_all() {
            self.alert("Couldn't Save", &e);
            return;
        }
        let generation = self.begin_task(TaskKind::Test);
        let name = self.project.borrow().name.clone();
        let mut cmd = Command::new(&swift);
        cmd.arg("test").current_dir(self.root());
        self.set_diagnostics(Vec::new());
        let serial = self.start_report(&format!("Test {name}"));
        self.console.clear();
        self.console.widget.set_visible(true);
        self.activity.set_status(&format!("Testing {name}…"));
        self.activity.set_progress(Some(-1.0));
        self.run_tool(cmd, generation, serial, true, |ws, code, cancelled| {
            if cancelled {
                ws.activity.set_status_timestamped("Testing Cancelled");
            } else if code == Some(0) {
                ws.activity.set_status_timestamped("Test Succeeded");
                return true;
            } else {
                ws.activity.set_status_timestamped("Test Failed");
                ws.reveal_first_error();
            }
            false
        });
    }

    fn start_clean(self: &Rc<Self>) {
        let Some(swift) = self.swift() else { return };
        let generation = self.begin_task(TaskKind::Clean);
        let mut cmd = Command::new(&swift);
        cmd.args(["package", "clean"]).current_dir(self.root());
        self.set_diagnostics(Vec::new());
        let serial = self.start_report("Clean");
        self.activity.set_status("Cleaning…");
        self.activity.set_progress(Some(-1.0));
        self.run_tool(cmd, generation, serial, false, |ws, code, _| {
            ws.activity.set_status_timestamped(if code == Some(0) { "Clean Finished" } else { "Clean Failed" });
            code == Some(0)
        });
    }

    /// Run a SwiftPM command, streaming output into a report (and optionally
    /// the console), collecting diagnostics and progress. `finish` receives
    /// the exit code and whether the task was cancelled, and returns success.
    fn run_tool(
        self: &Rc<Self>,
        cmd: Command,
        generation: u64,
        serial: usize,
        to_console: bool,
        finish: impl Fn(&Rc<Workspace>, Option<i32>, bool) -> bool + 'static,
    ) {
        let weak = Rc::downgrade(self);
        let lines = RefCell::new(LineBuffer::default());
        let handle_line = move |ws: &Rc<Workspace>, line: &str| {
            let root = ws.root();
            if let Some(d) = diagnostics::parse_line(line, &root) {
                let mut all = ws.diagnostics.borrow().clone();
                if !all.contains(&d) {
                    all.push(d);
                    ws.set_diagnostics(all);
                }
            }
            if let Some((done, total)) = diagnostics::parse_progress(line)
                && total > 0 {
                    ws.activity.set_progress(Some(done as f64 / total as f64));
                    let what = line.split_once(']').map(|(_, rest)| rest.trim()).unwrap_or("");
                    ws.activity.set_status(&format!("{what}  ({done} of {total})"));
                }
        };
        let result = RunningProcess::spawn(cmd, move |ev| {
            let Some(ws) = weak.upgrade() else { return };
            if !ws.is_current(generation) {
                return;
            }
            match ev {
                ProcEvent::Stdout(text) | ProcEvent::Stderr(text) => {
                    ws.with_report(serial, |r| r.log.push_str(&diagnostics::strip_ansi(&text)));
                    if to_console {
                        ws.console.append(&text, Stream::Stdout);
                    }
                    let complete = lines.borrow_mut().push(&text);
                    for line in complete {
                        handle_line(&ws, &line);
                    }
                }
                ProcEvent::Exit(code) => {
                    if let Some(rest) = lines.borrow_mut().flush() {
                        handle_line(&ws, &rest);
                    }
                    let cancelled = ws.task.borrow().as_ref().is_some_and(|t| t.cancelled);
                    ws.end_task(generation);
                    ws.activity.set_progress(None);
                    if code != Some(0) && !cancelled && ws.diagnostics.borrow().is_empty() {
                        let message = match code {
                            Some(c) => format!("Command failed with exit code {c}. See the build log in the Report navigator."),
                            None => "Command was terminated by a signal.".to_string(),
                        };
                        ws.set_diagnostics(vec![Diagnostic { severity: Severity::Error, message, location: None }]);
                    }
                    let ok = finish(&ws, code, cancelled);
                    let status = if cancelled {
                        ReportStatus::Cancelled
                    } else if ok {
                        ReportStatus::Succeeded
                    } else {
                        ReportStatus::Failed
                    };
                    ws.with_report(serial, |r| ws.navigator.set_report_status(&r.row, status));
                }
            }
        });
        match result {
            Ok(process) => {
                if let Some(t) = self.task.borrow_mut().as_mut() {
                    t.process = Some(process);
                }
            }
            Err(e) => {
                self.end_task(generation);
                self.activity.set_progress(None);
                self.activity.set_status("Failed to start the Swift toolchain");
                self.alert("Couldn't Run Swift", &e.to_string());
            }
        }
    }

    fn reveal_first_error(self: &Rc<Self>) {
        let first = self
            .diagnostics
            .borrow()
            .iter()
            .find(|d| d.severity == Severity::Error)
            .cloned();
        let Some(d) = first else { return };
        self.navigator_visible(true);
        self.navigator.show_page(Page::Issues);
        if let Some(loc) = d.location {
            self.open_file(&loc.path, Some((loc.line, loc.column)));
        }
    }

    /// Launch the built product on the selected destination.
    fn launch(self: &Rc<Self>, product: &str) {
        let root = self.root();
        let exe = root.join(".build/debug").join(product);
        if !exe.is_file() {
            self.alert("Couldn't Find the Built Product", &format!("Expected the executable at {}.", exe.display()));
            return;
        }
        let destination = self.destination.borrow().clone();
        let dest_name = destination_name(&destination);
        let generation = self.begin_task(TaskKind::Run);
        self.console.clear();
        self.console.widget.set_visible(true);
        self.activity.set_status(&format!("Running {product} on {dest_name}"));

        let weak = Rc::downgrade(self);
        let product_name = product.to_string();
        let on_event = move |ev: ProcEvent| {
            let Some(ws) = weak.upgrade() else { return };
            if !ws.is_current(generation) {
                return;
            }
            match ev {
                ProcEvent::Stdout(t) => ws.console.append(&t, Stream::Stdout),
                ProcEvent::Stderr(t) => ws.console.append(&t, Stream::Stderr),
                ProcEvent::Exit(code) => {
                    let msg = match code {
                        Some(c) => format!("Program ended with exit code: {c}\n"),
                        None => "Program was terminated.\n".to_string(),
                    };
                    ws.console.append(&msg, Stream::System);
                    ws.end_task(generation);
                    ws.activity.set_status_timestamped(&format!("Finished running {product_name} on {dest_name}"));
                }
            }
        };

        if destination == HOST_DESTINATION {
            let mut cmd = Command::new(&exe);
            cmd.current_dir(&root);
            match RunningProcess::spawn(cmd, on_event) {
                Ok(p) => {
                    if let Some(t) = self.task.borrow_mut().as_mut() {
                        t.process = Some(p);
                    }
                    self.console.set_input_enabled(true);
                }
                Err(e) => {
                    self.end_task(generation);
                    self.alert("Couldn't Launch", &e.to_string());
                }
            }
        } else {
            if let Some(t) = self.task.borrow_mut().as_mut() {
                t.in_simulator = true;
            }
            let sim = simulator::shared(&self.app);
            sim.run_app(product, exe, root, &destination, on_event);
        }
    }

    /// Stop the current build, test or run.
    pub fn stop(&self) {
        let task = {
            let mut t = self.task.borrow_mut();
            if let Some(task) = t.as_mut() {
                task.cancelled = true;
            }
            t.as_ref().map(|t| (t.kind, t.process.clone(), t.in_simulator))
        };
        let Some((kind, process, in_simulator)) = task else { return };
        if let Some(p) = process {
            p.terminate();
        }
        if in_simulator {
            if let Some(sim) = simulator::existing() {
                sim.stop_app();
            }
            // The simulator reports the exit asynchronously; finish the task now.
            *self.task.borrow_mut() = None;
            self.task_generation.set(self.task_generation.get() + 1);
            self.update_task_actions();
            self.console.append("Program was stopped.\n", Stream::System);
            self.activity.set_status_timestamped("Stopped");
        } else if kind == TaskKind::Run {
            self.activity.set_status("Stopping…");
        }
    }

    pub fn apply_settings(&self) {
        self.editor.apply_settings();
    }
}
