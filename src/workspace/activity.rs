//! The activity view: the status pill in the middle of the toolbar showing
//! what LCode is doing ("Building…", "Build Succeeded", "Running…") along
//! with build progress and issue counts.

use adw::prelude::*;
use gtk::glib;

pub struct Activity {
    pub widget: gtk::Box,
    title: gtk::Label,
    status: gtk::Label,
    progress: gtk::ProgressBar,
    errors: gtk::Box,
    errors_label: gtk::Label,
    warnings: gtk::Box,
    warnings_label: gtk::Label,
    pulse: std::cell::RefCell<Option<glib::SourceId>>,
}

fn badge(icon: &str, class: &str, action: &str) -> (gtk::Box, gtk::Label) {
    let b = gtk::Box::new(gtk::Orientation::Horizontal, 3);
    b.add_css_class("badge");
    b.add_css_class(class);
    let image = gtk::Image::from_icon_name(icon);
    image.set_pixel_size(13);
    let label = gtk::Label::new(None);
    b.append(&image);
    b.append(&label);
    b.set_visible(false);
    let click = gtk::GestureClick::new();
    let action = action.to_string();
    click.connect_released(move |g, _, _, _| {
        if let Some(w) = g.widget() {
            let _ = w.activate_action(&action, None);
        }
    });
    b.add_controller(click);
    b.set_cursor_from_name(Some("pointer"));
    (b, label)
}

impl Activity {
    pub fn new(project_name: &str) -> Self {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        widget.add_css_class("activity-view");
        widget.set_valign(gtk::Align::Center);

        let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        row.set_vexpand(true);
        row.set_valign(gtk::Align::Center);
        let icon = gtk::Image::from_icon_name(crate::APP_ID);
        icon.set_pixel_size(16);
        let title = gtk::Label::new(Some(project_name));
        title.add_css_class("activity-title");
        let sep = gtk::Label::new(Some("|"));
        sep.add_css_class("dim-label");
        let status = gtk::Label::new(Some("Ready"));
        status.add_css_class("activity-status");
        status.set_ellipsize(gtk::pango::EllipsizeMode::End);
        status.set_hexpand(true);
        status.set_xalign(0.0);
        let (errors, errors_label) = badge("dialog-error-symbolic", "errors", "win.show-issue-navigator");
        let (warnings, warnings_label) = badge("dialog-warning-symbolic", "warnings", "win.show-issue-navigator");
        row.append(&icon);
        row.append(&title);
        row.append(&sep);
        row.append(&status);
        row.append(&warnings);
        row.append(&errors);

        let progress = gtk::ProgressBar::new();
        progress.set_visible(false);
        widget.append(&row);
        widget.append(&progress);

        Activity {
            widget,
            title,
            status,
            progress,
            errors,
            errors_label,
            warnings,
            warnings_label,
            pulse: Default::default(),
        }
    }

    pub fn set_title(&self, text: &str) {
        self.title.set_text(text);
    }

    pub fn set_status(&self, text: &str) {
        self.status.set_text(text);
        self.status.set_tooltip_text(Some(text));
    }

    /// Status with a timestamp, e.g. "Build Succeeded | Today at 10:42".
    pub fn set_status_timestamped(&self, text: &str) {
        let time = glib::DateTime::now_local()
            .ok()
            .and_then(|d| d.format("%H:%M").ok())
            .map(|s| s.to_string())
            .unwrap_or_default();
        self.set_status(&format!("{text}  |  Today at {time}"));
    }

    /// `Some(fraction)` shows determinate progress, `Some(-1.0)` an indeterminate pulse, `None` hides it.
    pub fn set_progress(&self, value: Option<f64>) {
        if let Some(id) = self.pulse.borrow_mut().take() {
            id.remove();
        }
        match value {
            None => self.progress.set_visible(false),
            Some(f) if f < 0.0 => {
                self.progress.set_visible(true);
                let bar = self.progress.clone();
                let id = glib::timeout_add_local(std::time::Duration::from_millis(120), move || {
                    bar.pulse();
                    glib::ControlFlow::Continue
                });
                *self.pulse.borrow_mut() = Some(id);
            }
            Some(f) => {
                self.progress.set_visible(true);
                self.progress.set_fraction(f.clamp(0.0, 1.0));
            }
        }
    }

    pub fn set_counts(&self, errors: usize, warnings: usize) {
        self.errors.set_visible(errors > 0);
        self.errors_label.set_text(&errors.to_string());
        self.warnings.set_visible(warnings > 0);
        self.warnings_label.set_text(&warnings.to_string());
    }
}
