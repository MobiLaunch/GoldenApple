//! "Welcome to LCode": the launch window with quick actions and recent projects.

use std::cell::RefCell;
use std::path::PathBuf;

use adw::prelude::*;
use gtk::{gio, glib};

thread_local! {
    static WINDOW: RefCell<Option<adw::ApplicationWindow>> = const { RefCell::new(None) };
}

pub fn close() {
    // Take the window out first: closing it re-enters WINDOW via close-request.
    let window = WINDOW.with(|w| w.borrow_mut().take());
    if let Some(win) = window {
        win.close();
    }
}

fn action_row(icon: &str, title: &str, subtitle: &str, action: &str) -> gtk::Button {
    let content = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    let image = gtk::Image::from_icon_name(icon);
    content.append(&image);
    let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
    let t = gtk::Label::new(Some(title));
    t.add_css_class("action-title");
    t.set_xalign(0.0);
    let s = gtk::Label::new(Some(subtitle));
    s.add_css_class("action-subtitle");
    s.set_xalign(0.0);
    text.append(&t);
    text.append(&s);
    content.append(&text);
    let button = gtk::Button::builder().child(&content).action_name(action).build();
    button.add_css_class("flat");
    button.add_css_class("welcome-action");
    button
}

pub fn present(app: &adw::Application) {
    if let Some(win) = WINDOW.with(|w| w.borrow().clone()) {
        win.present();
        return;
    }

    // Left: logo, title, actions.
    let left = gtk::Box::new(gtk::Orientation::Vertical, 6);
    left.add_css_class("welcome-left");
    left.set_hexpand(true);
    let icon = gtk::Image::from_icon_name(crate::APP_ID);
    icon.set_pixel_size(128);
    icon.set_margin_top(12);
    left.append(&icon);
    let title = gtk::Label::new(Some("LCode"));
    title.add_css_class("welcome-title");
    left.append(&title);
    let version = gtk::Label::new(Some(&format!("Version {}", env!("CARGO_PKG_VERSION"))));
    version.add_css_class("welcome-version");
    version.set_margin_bottom(24);
    left.append(&version);
    let actions = gtk::Box::new(gtk::Orientation::Vertical, 4);
    actions.set_halign(gtk::Align::Center);
    actions.append(&action_row(
        "document-new-symbolic",
        "Create New Project…",
        "Create an app, command-line tool or Swift package",
        "app.new-project",
    ));
    actions.append(&action_row(
        "folder-download-symbolic",
        "Clone Git Repository…",
        "Start working on something from a Git repository",
        "app.clone",
    ));
    actions.append(&action_row(
        "folder-open-symbolic",
        "Open Existing Project…",
        "Browse your existing projects",
        "app.open",
    ));
    left.append(&actions);
    let spacer = gtk::Box::new(gtk::Orientation::Vertical, 0);
    spacer.set_vexpand(true);
    left.append(&spacer);
    let show = gtk::CheckButton::with_label("Show this window when LCode launches");
    show.set_active(crate::settings::get().show_welcome_on_launch);
    show.set_halign(gtk::Align::Center);
    show.connect_toggled(|b| {
        let on = b.is_active();
        crate::settings::update(|s| s.show_welcome_on_launch = on);
    });
    left.append(&show);

    // Right: recent projects.
    let recents = gtk::ListBox::new();
    recents.add_css_class("navigation-sidebar");
    let empty = gtk::Label::new(Some("No Recent Projects"));
    empty.add_css_class("dim-label");
    empty.set_margin_top(48);
    recents.set_placeholder(Some(&empty));
    let paths: Vec<PathBuf> = crate::settings::recent_projects();
    for p in &paths {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        let kind = crate::project::Project::open(p).meta.kind;
        let image = gtk::Image::from_icon_name(match kind {
            crate::project::ProjectKind::App => crate::APP_ID,
            crate::project::ProjectKind::Tool => "utilities-terminal-symbolic",
            crate::project::ProjectKind::Library => "package-x-generic-symbolic",
        });
        image.set_pixel_size(32);
        row.append(&image);
        let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
        text.set_valign(gtk::Align::Center);
        let name = gtk::Label::new(p.file_name().map(|n| n.to_string_lossy().into_owned()).as_deref());
        name.set_xalign(0.0);
        name.add_css_class("heading");
        let home = glib::home_dir();
        let display = match p.strip_prefix(&home) {
            Ok(rest) => format!("~/{}", rest.display()),
            Err(_) => p.display().to_string(),
        };
        let path = gtk::Label::new(Some(&display));
        path.add_css_class("recent-path");
        path.set_xalign(0.0);
        path.set_ellipsize(gtk::pango::EllipsizeMode::Middle);
        text.append(&name);
        text.append(&path);
        row.append(&text);
        recents.append(&row);
    }
    let scroller = gtk::ScrolledWindow::builder()
        .child(&recents)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .build();
    let right = gtk::Box::new(gtk::Orientation::Vertical, 0);
    right.add_css_class("welcome-recents");
    right.set_size_request(320, -1);
    let header = adw::HeaderBar::new();
    header.set_show_title(false);
    header.add_css_class("flat");
    right.append(&header);
    right.append(&scroller);

    let left_wrap = gtk::Box::new(gtk::Orientation::Vertical, 0);
    let left_header = adw::HeaderBar::new();
    left_header.set_show_title(false);
    left_header.set_show_end_title_buttons(false);
    left_header.add_css_class("flat");
    left_wrap.append(&left_header);
    left_wrap.append(&left);
    left_wrap.set_hexpand(true);

    let content = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    content.append(&left_wrap);
    content.append(&gtk::Separator::new(gtk::Orientation::Vertical));
    content.append(&right);

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Welcome to LCode")
        .default_width(820)
        .default_height(480)
        .resizable(false)
        .content(&content)
        .build();

    let app_weak = app.downgrade();
    recents.set_activate_on_single_click(false);
    recents.connect_row_activated(move |_, row| {
        let (Some(app), Some(p)) = (app_weak.upgrade(), paths.get(row.index() as usize)) else { return };
        crate::workspace::open(&app, p);
    });

    // Right-click a recent project to remove it from the list.
    let remove_gesture = gtk::GestureClick::new();
    remove_gesture.set_button(3);
    let list = recents.clone();
    remove_gesture.connect_pressed(move |_, _, _, y| {
        let Some(row) = list.row_at_y(y as i32) else { return };
        let recent = crate::settings::recent_projects();
        if let Some(p) = recent.get(row.index() as usize) {
            crate::settings::remove_recent_project(p);
            list.remove(&row);
        }
    });
    recents.add_controller(remove_gesture);

    window.connect_close_request(|_| {
        WINDOW.with(|w| w.borrow_mut().take());
        glib::Propagation::Proceed
    });
    WINDOW.with(|w| *w.borrow_mut() = Some(window.clone()));
    window.present();
}

/// Ask for a folder and open it as a project.
pub fn choose_and_open(app: &adw::Application, parent: Option<&gtk::Window>) {
    let dialog = gtk::FileDialog::builder().title("Open Existing Project").modal(true).build();
    let app = app.clone();
    dialog.select_folder(parent, gio::Cancellable::NONE, move |result| {
        if let Ok(path) = result.map(|f| f.path())
            && let Some(path) = path {
                crate::workspace::open(&app, &path);
            }
    });
}

/// Clone a Git repository, then open it.
pub fn clone_repository(app: &adw::Application, parent: Option<&gtk::Window>) {
    let dialog = adw::AlertDialog::new(Some("Clone Git Repository"), Some("Enter a repository URL."));
    let entry = gtk::Entry::builder()
        .placeholder_text("https://github.com/owner/repository.git")
        .activates_default(true)
        .build();
    dialog.set_extra_child(Some(&entry));
    dialog.add_responses(&[("cancel", "Cancel"), ("clone", "Clone…")]);
    dialog.set_response_appearance("clone", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("clone"));
    let app = app.clone();
    let parent_owned = parent.cloned();
    dialog.connect_response(Some("clone"), move |_, _| {
        let url = entry.text().trim().to_string();
        if url.is_empty() {
            return;
        }
        let folder = gtk::FileDialog::builder().title("Choose Where to Clone").modal(true).build();
        let app = app.clone();
        let parent = parent_owned.clone();
        folder.select_folder(parent_owned.as_ref(), gio::Cancellable::NONE, move |result| {
            let Ok(Some(dir)) = result.map(|f| f.path()) else { return };
            let name = url.trim_end_matches('/').rsplit('/').next().unwrap_or("repository").trim_end_matches(".git").to_string();
            let target = dir.join(&name);
            let app = app.clone();
            let parent = parent.clone();
            let url = url.clone();
            glib::spawn_future_local(async move {
                let t = target.clone();
                let output = gio::spawn_blocking(move || {
                    std::process::Command::new("git").args(["clone", "--", &url]).arg(&t).output()
                })
                .await;
                match output {
                    Ok(Ok(o)) if o.status.success() => {
                        crate::workspace::open(&app, &target);
                    }
                    Ok(Ok(o)) => error(parent.as_ref(), "Clone Failed", &String::from_utf8_lossy(&o.stderr)),
                    Ok(Err(e)) => error(parent.as_ref(), "Clone Failed", &format!("Couldn't run git: {e}")),
                    Err(_) => error(parent.as_ref(), "Clone Failed", "The clone was interrupted."),
                }
            });
        });
    });
    match parent {
        Some(p) => dialog.present(Some(p)),
        None => dialog.present(None::<&gtk::Widget>),
    }
}

fn error(parent: Option<&gtk::Window>, heading: &str, body: &str) {
    let dialog = adw::AlertDialog::new(Some(heading), Some(body));
    dialog.add_response("ok", "OK");
    match parent {
        Some(p) => dialog.present(Some(p)),
        None => dialog.present(None::<&gtk::Widget>),
    }
}
