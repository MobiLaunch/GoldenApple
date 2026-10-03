//! LCode — an Apple-style IDE for Swift on Linux.

mod diagnostics;
mod menus;
mod new_project;
mod preferences;
mod process;
mod project;
mod settings;
mod simulator;
mod style;
mod templates;
mod welcome;
mod workspace;

use adw::prelude::*;
use gtk::{gio, glib};

pub const APP_ID: &str = "dev.lcode.LCode";

fn active_window(app: &adw::Application) -> Option<gtk::Window> {
    app.active_window()
}

fn add_app_action(app: &adw::Application, name: &str, f: impl Fn(&adw::Application) + 'static) {
    let action = gio::SimpleAction::new(name, None);
    let weak = app.downgrade();
    action.connect_activate(move |_, _| {
        if let Some(app) = weak.upgrade() {
            f(&app);
        }
    });
    app.add_action(&action);
}

fn setup_actions(app: &adw::Application) {
    add_app_action(app, "quit", |app| {
        for ws in workspace::all() {
            ws.window.close();
        }
        if workspace::all().is_empty() {
            app.quit();
        }
    });
    add_app_action(app, "new-project", |app| new_project::present(app, active_window(app).as_ref()));
    add_app_action(app, "open", |app| welcome::choose_and_open(app, active_window(app).as_ref()));
    add_app_action(app, "clone", |app| welcome::clone_repository(app, active_window(app).as_ref()));
    add_app_action(app, "welcome", welcome::present);
    add_app_action(app, "simulator", |app| simulator::shared(app).present());
    add_app_action(app, "preferences", |app| preferences::present(active_window(app).as_ref()));
    add_app_action(app, "shortcuts", |app| menus::show_shortcuts(active_window(app).as_ref()));
    add_app_action(app, "about", |app| {
        let about = adw::AboutDialog::builder()
            .application_name("LCode")
            .application_icon(APP_ID)
            .version(env!("CARGO_PKG_VERSION"))
            .developer_name("The LCode Contributors")
            .comments("An Apple-style IDE for building and running Swift apps on Linux, with a built-in device Simulator.")
            .license_type(gtk::License::MitX11)
            .build();
        match active_window(app) {
            Some(w) => about.present(Some(&w)),
            None => about.present(None::<&gtk::Widget>),
        }
    });
    menus::install_accels(app);
}

fn main() -> glib::ExitCode {
    let app = adw::Application::builder()
        .application_id(APP_ID)
        .flags(gio::ApplicationFlags::HANDLES_OPEN)
        .build();

    app.connect_startup(|app| {
        style::install();
        setup_actions(app);
    });
    app.connect_activate(|app| {
        if let Some(w) = app.active_window() {
            w.present();
            return;
        }
        let recent = settings::recent_projects();
        if settings::get().show_welcome_on_launch || recent.is_empty() {
            welcome::present(app);
        } else {
            workspace::open(app, &recent[0]);
        }
    });
    app.connect_open(|app, files, _| {
        for file in files {
            if let Some(path) = file.path() {
                let dir = if path.is_file() { path.parent().map(|p| p.to_path_buf()).unwrap_or(path.clone()) } else { path.clone() };
                let ws = workspace::open(app, &dir);
                if path.is_file() {
                    ws.open_file(&path, None);
                }
            }
        }
    });
    app.connect_shutdown(|_| {
        if let Some(sim) = simulator::existing() {
            sim.shutdown();
        }
    });
    app.run()
}
