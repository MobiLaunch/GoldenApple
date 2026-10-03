//! The inspector area: File inspector (identity, type, text settings) and
//! project settings.

use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use adw::prelude::*;
use gtk::gio;
use sourceview5::prelude::*;

use super::editor::Document;
use crate::project::{Project, ProjectKind};

type ProjectChanged = Box<dyn Fn(ProjectKind, String)>;

pub struct Inspector {
    pub widget: gtk::Box,
    name: gtk::Label,
    kind: gtk::Label,
    location: gtk::Label,
    full_path: gtk::Label,
    size: gtk::Label,
    modified: gtk::Label,
    indent: gtk::DropDown,
    tab_width: gtk::SpinButton,
    file_box: gtk::Box,
    empty: gtk::Label,
    project_kind: gtk::DropDown,
    bundle_id: gtk::Entry,
    current: RefCell<Option<Rc<Document>>>,
    updating: std::cell::Cell<bool>,
    on_project_changed: RefCell<Option<ProjectChanged>>,
}

fn section(title: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(title));
    l.add_css_class("inspector-section");
    l.set_xalign(0.0);
    l
}

fn grid_row(grid: &gtk::Grid, row: i32, key: &str, value: &impl IsA<gtk::Widget>) {
    let k = gtk::Label::new(Some(key));
    k.add_css_class("inspector-key");
    k.set_xalign(1.0);
    k.set_valign(gtk::Align::Start);
    grid.attach(&k, 0, row, 1, 1);
    grid.attach(value, 1, row, 1, 1);
}

fn value_label() -> gtk::Label {
    let l = gtk::Label::new(None);
    l.add_css_class("inspector-value");
    l.set_xalign(0.0);
    l.set_wrap(true);
    l.set_wrap_mode(gtk::pango::WrapMode::WordChar);
    l.set_selectable(true);
    l.set_hexpand(true);
    l
}

fn new_grid() -> gtk::Grid {
    let g = gtk::Grid::new();
    g.set_column_spacing(8);
    g.set_row_spacing(6);
    g.set_margin_start(12);
    g.set_margin_end(12);
    g
}

impl Inspector {
    pub fn new(project: &Project) -> Rc<Self> {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        widget.add_css_class("inspector");
        widget.set_size_request(250, -1);

        let header = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        header.add_css_class("navigator-tabs");
        let file_tab = gtk::Image::from_icon_name("text-x-generic-symbolic");
        file_tab.set_tooltip_text(Some("File Inspector"));
        file_tab.add_css_class("accent");
        file_tab.set_hexpand(true);
        header.append(&file_tab);
        widget.append(&header);

        let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
        let scroller = gtk::ScrolledWindow::builder()
            .child(&content)
            .vexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .build();
        widget.append(&scroller);

        // Identity and Type.
        let file_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
        file_box.append(&section("Identity and Type"));
        let grid = new_grid();
        let (name, kind, location, full_path, size, modified) =
            (value_label(), value_label(), value_label(), value_label(), value_label(), value_label());
        grid_row(&grid, 0, "Name", &name);
        grid_row(&grid, 1, "Type", &kind);
        grid_row(&grid, 2, "Location", &location);
        grid_row(&grid, 3, "Full Path", &full_path);
        grid_row(&grid, 4, "Size", &size);
        grid_row(&grid, 5, "Modified", &modified);
        file_box.append(&grid);

        file_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
        file_box.append(&section("Text Settings"));
        let text_grid = new_grid();
        let encoding = value_label();
        encoding.set_text("Unicode (UTF-8)");
        let endings = value_label();
        endings.set_text("Unix (LF)");
        let indent = gtk::DropDown::from_strings(&["Spaces", "Tabs"]);
        let tab_width = gtk::SpinButton::with_range(1.0, 16.0, 1.0);
        grid_row(&text_grid, 0, "Text Encoding", &encoding);
        grid_row(&text_grid, 1, "Line Endings", &endings);
        grid_row(&text_grid, 2, "Indent Using", &indent);
        grid_row(&text_grid, 3, "Widths", &tab_width);
        file_box.append(&text_grid);

        let empty = gtk::Label::new(Some("No Selection"));
        empty.add_css_class("placeholder");
        empty.add_css_class("dim-label");
        empty.set_margin_top(24);
        content.append(&empty);
        content.append(&file_box);

        // Project settings.
        content.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
        content.append(&section("Project"));
        let project_grid = new_grid();
        let project_name = value_label();
        project_name.set_text(&project.name);
        let project_kind = gtk::DropDown::from_strings(&["App", "Command Line Tool", "Library"]);
        project_kind.set_selected(match project.meta.kind {
            ProjectKind::App => 0,
            ProjectKind::Tool => 1,
            ProjectKind::Library => 2,
        });
        let bundle_id = gtk::Entry::builder().text(&project.meta.bundle_identifier).placeholder_text("com.example.app").build();
        grid_row(&project_grid, 0, "Name", &project_name);
        grid_row(&project_grid, 1, "Product Type", &project_kind);
        grid_row(&project_grid, 2, "Bundle ID", &bundle_id);
        content.append(&project_grid);

        let inspector = Rc::new(Inspector {
            widget,
            name,
            kind,
            location,
            full_path,
            size,
            modified,
            indent,
            tab_width,
            file_box,
            empty,
            project_kind,
            bundle_id,
            current: RefCell::new(None),
            updating: std::cell::Cell::new(false),
            on_project_changed: RefCell::new(None),
        });
        inspector.show_document(None, &project.root);

        let weak = Rc::downgrade(&inspector);
        inspector.indent.connect_selected_notify(move |dd| {
            let Some(i) = weak.upgrade() else { return };
            if i.updating.get() {
                return;
            }
            if let Some(doc) = i.current.borrow().as_ref() {
                doc.view.set_insert_spaces_instead_of_tabs(dd.selected() == 0);
            }
        });
        let weak = Rc::downgrade(&inspector);
        inspector.tab_width.connect_value_changed(move |sb| {
            let Some(i) = weak.upgrade() else { return };
            if i.updating.get() {
                return;
            }
            if let Some(doc) = i.current.borrow().as_ref() {
                doc.view.set_tab_width(sb.value() as u32);
            }
        });
        let weak = Rc::downgrade(&inspector);
        inspector.project_kind.connect_selected_notify(move |_| {
            if let Some(i) = weak.upgrade() {
                i.emit_project_changed();
            }
        });
        let weak = Rc::downgrade(&inspector);
        inspector.bundle_id.connect_changed(move |_| {
            if let Some(i) = weak.upgrade() {
                i.emit_project_changed();
            }
        });
        inspector
    }

    pub fn connect_project_changed(&self, f: impl Fn(ProjectKind, String) + 'static) {
        *self.on_project_changed.borrow_mut() = Some(Box::new(f));
    }

    fn emit_project_changed(&self) {
        let kind = match self.project_kind.selected() {
            0 => ProjectKind::App,
            1 => ProjectKind::Tool,
            _ => ProjectKind::Library,
        };
        if let Some(cb) = self.on_project_changed.borrow().as_ref() {
            cb(kind, self.bundle_id.text().to_string());
        }
    }

    pub fn show_document(&self, doc: Option<Rc<Document>>, root: &Path) {
        *self.current.borrow_mut() = doc.clone();
        let Some(path) = doc.as_ref().and_then(|d| d.path.clone()) else {
            self.file_box.set_visible(false);
            self.empty.set_visible(true);
            return;
        };
        let doc = doc.unwrap();
        self.file_box.set_visible(true);
        self.empty.set_visible(false);
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        self.name.set_text(&name);
        let (content_type, _) = gio::content_type_guess(Some(&path), None);
        let description = if name.ends_with(".swift") {
            "Swift Source".to_string()
        } else {
            gio::content_type_get_description(&content_type).to_string()
        };
        self.kind.set_text(&description);
        self.location.set_text(&path.parent().and_then(|p| p.strip_prefix(root).ok()).map(|p| {
            if p.as_os_str().is_empty() { "Project root".to_string() } else { p.display().to_string() }
        }).unwrap_or_default());
        self.full_path.set_text(&path.display().to_string());
        let meta = std::fs::metadata(&path).ok();
        self.size.set_text(&meta.as_ref().map(|m| glib_format_size(m.len())).unwrap_or_default());
        let modified = meta
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .and_then(|d| gtk::glib::DateTime::from_unix_local(d.as_secs() as i64).ok())
            .and_then(|d| d.format("%-d %b %Y at %H:%M").ok())
            .map(|s| s.to_string())
            .unwrap_or_default();
        self.modified.set_text(&modified);
        self.updating.set(true);
        self.indent.set_selected(if doc.view.is_insert_spaces_instead_of_tabs() { 0 } else { 1 });
        self.tab_width.set_value(doc.view.tab_width() as f64);
        self.updating.set(false);
    }
}

fn glib_format_size(bytes: u64) -> String {
    gtk::glib::format_size(bytes).to_string()
}
