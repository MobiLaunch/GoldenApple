//! The navigator area: Project, Find, Issue and Report navigators.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};

use crate::diagnostics::{Diagnostic, Severity};
use crate::project::is_ignored;

type Location = Option<(u32, u32)>;

const FILE_ATTRIBUTES: &str = "standard::name,standard::display-name,standard::type";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Page {
    Project,
    Find,
    Issues,
    Reports,
}

impl Page {
    fn name(self) -> &'static str {
        match self {
            Page::Project => "project",
            Page::Find => "find",
            Page::Issues => "issues",
            Page::Reports => "reports",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportStatus {
    Succeeded,
    Failed,
    Cancelled,
}

struct Callbacks {
    open: Option<Box<dyn Fn(PathBuf, Location)>>,
    open_report: Option<Box<dyn Fn(usize)>>,
    deleted: Option<Box<dyn Fn(PathBuf)>>,
}

pub struct Navigator {
    pub widget: gtk::Box,
    root: PathBuf,
    project_name: String,
    stack: gtk::Stack,
    tabs: Vec<(Page, gtk::ToggleButton)>,
    tree_stack: gtk::Stack,
    filter_results: gtk::ListBox,
    filter_paths: RefCell<Vec<PathBuf>>,
    selection: gtk::SingleSelection,
    find_entry: gtk::SearchEntry,
    find_case: gtk::ToggleButton,
    find_summary: gtk::Label,
    find_results: gtk::ListBox,
    find_locations: RefCell<Vec<Option<(PathBuf, u32, u32)>>>,
    issues_list: gtk::ListBox,
    issue_locations: RefCell<Vec<Option<(PathBuf, u32, u32)>>>,
    reports_list: gtk::ListBox,
    reports: RefCell<Vec<gtk::Box>>,
    callbacks: RefCell<Callbacks>,
}

fn file_of(info: &gio::FileInfo) -> Option<gio::File> {
    info.attribute_object("standard::file").and_then(|o| o.downcast::<gio::File>().ok())
}

fn directory_model(dir: &gio::File) -> gio::ListModel {
    let list = gtk::DirectoryList::new(Some(FILE_ATTRIBUTES), Some(dir));
    let filter = gtk::CustomFilter::new(|obj| {
        obj.downcast_ref::<gio::FileInfo>().is_some_and(|i| !is_ignored(&i.name().to_string_lossy()))
    });
    let filtered = gtk::FilterListModel::new(Some(list), Some(filter));
    let sorter = gtk::CustomSorter::new(|a, b| {
        let a = a.downcast_ref::<gio::FileInfo>().unwrap();
        let b = b.downcast_ref::<gio::FileInfo>().unwrap();
        let a_dir = a.file_type() == gio::FileType::Directory;
        let b_dir = b.file_type() == gio::FileType::Directory;
        // Folders first, then case-insensitive names, like Finder's default sort.
        b_dir
            .cmp(&a_dir)
            .then_with(|| a.name().to_string_lossy().to_lowercase().cmp(&b.name().to_string_lossy().to_lowercase()))
            .into()
    });
    gtk::SortListModel::new(Some(filtered), Some(sorter)).upcast()
}

fn placeholder(text: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class("placeholder");
    l.set_wrap(true);
    l.set_justify(gtk::Justification::Center);
    l
}

fn scrolled(child: &impl IsA<gtk::Widget>) -> gtk::ScrolledWindow {
    gtk::ScrolledWindow::builder()
        .child(child)
        .vexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .build()
}

impl Navigator {
    pub fn new(root: &Path, project_name: &str) -> Rc<Self> {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        widget.add_css_class("navigator");
        widget.set_size_request(200, -1);

        let tab_strip = gtk::Box::new(gtk::Orientation::Horizontal, 2);
        tab_strip.add_css_class("navigator-tabs");
        tab_strip.set_homogeneous(true);
        let stack = gtk::Stack::new();
        stack.set_vexpand(true);
        stack.set_transition_type(gtk::StackTransitionType::None);

        let mut tabs = Vec::new();
        let mut group: Option<gtk::ToggleButton> = None;
        for (page, icon, tip) in [
            (Page::Project, "folder-symbolic", "Project Navigator (Ctrl+1)"),
            (Page::Find, "system-search-symbolic", "Find Navigator (Ctrl+4)"),
            (Page::Issues, "dialog-warning-symbolic", "Issue Navigator (Ctrl+5)"),
            (Page::Reports, "document-open-recent-symbolic", "Report Navigator (Ctrl+9)"),
        ] {
            let b = gtk::ToggleButton::builder().icon_name(icon).tooltip_text(tip).build();
            b.add_css_class("flat");
            if let Some(g) = &group {
                b.set_group(Some(g));
            } else {
                group = Some(b.clone());
            }
            tab_strip.append(&b);
            tabs.push((page, b));
        }
        widget.append(&tab_strip);
        widget.append(&stack);

        // --- Project navigator ---
        let root_file = gio::File::for_path(root);
        let tree = gtk::TreeListModel::new(directory_model(&root_file), false, false, |item| -> Option<gio::ListModel> {
            let info = item.downcast_ref::<gio::FileInfo>()?;
            if info.file_type() != gio::FileType::Directory {
                return None;
            }
            Some(directory_model(&file_of(info)?))
        });
        let selection = gtk::SingleSelection::new(Some(tree));
        selection.set_autoselect(false);
        selection.set_can_unselect(true);
        let factory = gtk::SignalListItemFactory::new();
        let list_view = gtk::ListView::new(Some(selection.clone()), Some(factory.clone()));

        let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        header.add_css_class("file-row");
        header.set_margin_start(12);
        header.set_margin_top(6);
        header.set_margin_bottom(2);
        let project_icon = gtk::Image::from_icon_name(crate::APP_ID);
        project_icon.set_pixel_size(16);
        header.append(&project_icon);
        let project_label = gtk::Label::new(Some(project_name));
        project_label.add_css_class("heading");
        header.append(&project_label);

        let filter_results = gtk::ListBox::new();
        filter_results.add_css_class("navigation-sidebar");
        filter_results.set_placeholder(Some(&placeholder("No Matches")));
        let tree_stack = gtk::Stack::new();
        tree_stack.add_named(&scrolled(&list_view), Some("tree"));
        tree_stack.add_named(&scrolled(&filter_results), Some("filter"));
        tree_stack.set_vexpand(true);

        let filter_bar = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        filter_bar.add_css_class("filter-bar");
        let add_menu = gio::Menu::new();
        add_menu.append(Some("New File…"), Some(&format!("nav.new-file::{}", root.display())));
        add_menu.append(Some("New Folder…"), Some(&format!("nav.new-folder::{}", root.display())));
        let add = gtk::MenuButton::builder().icon_name("list-add-symbolic").menu_model(&add_menu).tooltip_text("Add").build();
        add.add_css_class("flat");
        let filter_entry = gtk::SearchEntry::builder().placeholder_text("Filter").hexpand(true).build();
        filter_bar.append(&add);
        filter_bar.append(&filter_entry);

        let project_page = gtk::Box::new(gtk::Orientation::Vertical, 0);
        project_page.append(&header);
        project_page.append(&tree_stack);
        project_page.append(&filter_bar);
        stack.add_named(&project_page, Some(Page::Project.name()));

        // --- Find navigator ---
        let find_entry = gtk::SearchEntry::builder().placeholder_text("Find in Project").hexpand(true).build();
        let find_case = gtk::ToggleButton::builder().label("Aa").tooltip_text("Match Case").build();
        find_case.add_css_class("flat");
        let find_row = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        find_row.set_margin_start(6);
        find_row.set_margin_end(6);
        find_row.set_margin_top(6);
        find_row.append(&find_entry);
        find_row.append(&find_case);
        let find_summary = gtk::Label::new(None);
        find_summary.add_css_class("dim-label");
        find_summary.add_css_class("caption");
        find_summary.set_xalign(0.0);
        find_summary.set_margin_start(10);
        find_summary.set_margin_top(4);
        let find_results = gtk::ListBox::new();
        find_results.add_css_class("navigation-sidebar");
        let find_page = gtk::Box::new(gtk::Orientation::Vertical, 0);
        find_page.append(&find_row);
        find_page.append(&find_summary);
        find_page.append(&scrolled(&find_results));
        stack.add_named(&find_page, Some(Page::Find.name()));

        // --- Issue navigator ---
        let issues_list = gtk::ListBox::new();
        issues_list.add_css_class("navigation-sidebar");
        issues_list.set_placeholder(Some(&placeholder("No Issues")));
        stack.add_named(&scrolled(&issues_list), Some(Page::Issues.name()));

        // --- Report navigator ---
        let reports_list = gtk::ListBox::new();
        reports_list.add_css_class("navigation-sidebar");
        reports_list.set_placeholder(Some(&placeholder("No Reports\n\nBuild the project to create a build log.")));
        stack.add_named(&scrolled(&reports_list), Some(Page::Reports.name()));

        let nav = Rc::new(Navigator {
            widget,
            root: root.to_path_buf(),
            project_name: project_name.to_string(),
            stack,
            tabs,
            tree_stack,
            filter_results,
            filter_paths: RefCell::new(Vec::new()),
            selection,
            find_entry,
            find_case,
            find_summary,
            find_results,
            find_locations: RefCell::new(Vec::new()),
            issues_list,
            issue_locations: RefCell::new(Vec::new()),
            reports_list,
            reports: RefCell::new(Vec::new()),
            callbacks: RefCell::new(Callbacks { open: None, open_report: None, deleted: None }),
        });

        for (page, button) in &nav.tabs {
            let weak = Rc::downgrade(&nav);
            let page = *page;
            button.connect_toggled(move |b| {
                if b.is_active()
                    && let Some(n) = weak.upgrade() {
                        n.stack.set_visible_child_name(page.name());
                    }
            });
        }
        nav.tabs[0].1.set_active(true);

        nav.setup_tree_factory(&factory);
        let weak = Rc::downgrade(&nav);
        nav.selection.connect_selection_changed(move |sel, _, _| {
            let Some(n) = weak.upgrade() else { return };
            let Some(row) = sel.selected_item().and_downcast::<gtk::TreeListRow>() else { return };
            let Some(info) = row.item().and_downcast::<gio::FileInfo>() else { return };
            if info.file_type() != gio::FileType::Directory
                && let Some(path) = file_of(&info).and_then(|f| f.path()) {
                    n.emit_open(path, None);
                }
        });
        list_view.connect_activate(|lv, pos| {
            let Some(model) = lv.model() else { return };
            if let Some(row) = model.item(pos).and_downcast::<gtk::TreeListRow>()
                && row.is_expandable() {
                    row.set_expanded(!row.is_expanded());
                }
        });

        let weak = Rc::downgrade(&nav);
        filter_entry.connect_search_changed(move |e| {
            if let Some(n) = weak.upgrade() {
                n.apply_filter(&e.text());
            }
        });
        let weak = Rc::downgrade(&nav);
        nav.filter_results.connect_row_activated(move |_, row| {
            if let Some(n) = weak.upgrade() {
                let path = n.filter_paths.borrow().get(row.index() as usize).cloned();
                if let Some(p) = path {
                    n.emit_open(p, None);
                }
            }
        });

        let weak = Rc::downgrade(&nav);
        nav.find_entry.connect_activate(move |_| {
            if let Some(n) = weak.upgrade() {
                n.run_find();
            }
        });
        let weak = Rc::downgrade(&nav);
        nav.find_results.connect_row_activated(move |_, row| {
            if let Some(n) = weak.upgrade() {
                let loc = n.find_locations.borrow().get(row.index() as usize).cloned().flatten();
                if let Some((p, l, c)) = loc {
                    n.emit_open(p, Some((l, c)));
                }
            }
        });
        let weak = Rc::downgrade(&nav);
        nav.issues_list.connect_row_activated(move |_, row| {
            if let Some(n) = weak.upgrade() {
                let loc = n.issue_locations.borrow().get(row.index() as usize).cloned().flatten();
                if let Some((p, l, c)) = loc {
                    n.emit_open(p, Some((l, c)));
                }
            }
        });
        let weak = Rc::downgrade(&nav);
        nav.reports_list.connect_row_activated(move |_, row| {
            if let Some(n) = weak.upgrade()
                && let Some(cb) = n.callbacks.borrow().open_report.as_ref() {
                    cb(row.index() as usize);
                }
        });

        nav.setup_file_actions();
        nav
    }

    pub fn connect_open(&self, f: impl Fn(PathBuf, Location) + 'static) {
        self.callbacks.borrow_mut().open = Some(Box::new(f));
    }

    pub fn connect_open_report(&self, f: impl Fn(usize) + 'static) {
        self.callbacks.borrow_mut().open_report = Some(Box::new(f));
    }

    pub fn connect_deleted(&self, f: impl Fn(PathBuf) + 'static) {
        self.callbacks.borrow_mut().deleted = Some(Box::new(f));
    }

    fn emit_open(&self, path: PathBuf, loc: Location) {
        if let Some(cb) = self.callbacks.borrow().open.as_ref() {
            cb(path, loc);
        }
    }

    pub fn show_page(&self, page: Page) {
        if let Some((_, b)) = self.tabs.iter().find(|(p, _)| *p == page) {
            b.set_active(true);
        }
        self.stack.set_visible_child_name(page.name());
    }

    pub fn focus_find(&self, text: Option<&str>) {
        self.show_page(Page::Find);
        if let Some(t) = text.filter(|t| !t.is_empty()) {
            self.find_entry.set_text(t);
        }
        self.find_entry.grab_focus();
    }

    // ---- Project tree ------------------------------------------------------------------

    fn setup_tree_factory(self: &Rc<Self>, factory: &gtk::SignalListItemFactory) {
        let weak = Rc::downgrade(self);
        factory.connect_setup(move |_, item| {
            let item = item.downcast_ref::<gtk::ListItem>().unwrap();
            let expander = gtk::TreeExpander::new();
            expander.set_indent_for_icon(true);
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            row.add_css_class("file-row");
            row.append(&gtk::Image::new());
            row.append(&gtk::Label::builder().xalign(0.0).ellipsize(gtk::pango::EllipsizeMode::Middle).build());
            expander.set_child(Some(&row));
            item.set_child(Some(&expander));

            let menu_click = gtk::GestureClick::new();
            menu_click.set_button(3);
            let weak = weak.clone();
            let row_widget = row.clone();
            menu_click.connect_pressed(move |_, _, x, y| {
                let Some(n) = weak.upgrade() else { return };
                let path = PathBuf::from(row_widget.widget_name().as_str());
                n.show_context_menu(&row_widget, &path, x, y);
            });
            row.add_controller(menu_click);
        });
        factory.connect_bind(|_, item| {
            let item = item.downcast_ref::<gtk::ListItem>().unwrap();
            let Some(row) = item.item().and_downcast::<gtk::TreeListRow>() else { return };
            let Some(expander) = item.child().and_downcast::<gtk::TreeExpander>() else { return };
            expander.set_list_row(Some(&row));
            let Some(info) = row.item().and_downcast::<gio::FileInfo>() else { return };
            let Some(content) = expander.child().and_downcast::<gtk::Box>() else { return };
            let image = content.first_child().and_downcast::<gtk::Image>().unwrap();
            let label = content.last_child().and_downcast::<gtk::Label>().unwrap();
            let name = info.display_name().to_string();
            let is_dir = info.file_type() == gio::FileType::Directory;
            let (icon, class) = crate::style::file_icon(&name, is_dir);
            image.set_icon_name(Some(icon));
            for c in ["swift-icon", "folder-icon", "package-icon"] {
                image.remove_css_class(c);
            }
            image.add_css_class(class);
            label.set_text(&name);
            if let Some(path) = file_of(&info).and_then(|f| f.path()) {
                content.set_widget_name(&path.to_string_lossy());
                content.set_tooltip_text(None);
            }
        });
    }

    fn show_context_menu(&self, anchor: &gtk::Box, path: &Path, x: f64, y: f64) {
        let p = path.display().to_string();
        let menu = gio::Menu::new();
        let create = gio::Menu::new();
        create.append(Some("New File…"), Some(&format!("nav.new-file::{p}")));
        create.append(Some("New Folder…"), Some(&format!("nav.new-folder::{p}")));
        menu.append_section(None, &create);
        let manage = gio::Menu::new();
        manage.append(Some("Rename…"), Some(&format!("nav.rename::{p}")));
        manage.append(Some("Show in Files"), Some(&format!("nav.reveal::{p}")));
        manage.append(Some("Copy Path"), Some(&format!("nav.copy-path::{p}")));
        menu.append_section(None, &manage);
        let danger = gio::Menu::new();
        danger.append(Some("Move to Trash"), Some(&format!("nav.delete::{p}")));
        menu.append_section(None, &danger);

        let popover = gtk::PopoverMenu::from_model(Some(&menu));
        popover.set_parent(anchor);
        popover.set_has_arrow(false);
        popover.set_pointing_to(Some(&gtk::gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover.connect_closed(|p| {
            let p = p.clone();
            glib::idle_add_local_once(move || p.unparent());
        });
        popover.popup();
    }

    fn apply_filter(&self, text: &str) {
        let needle = text.trim().to_lowercase();
        if needle.is_empty() {
            self.tree_stack.set_visible_child_name("tree");
            return;
        }
        self.tree_stack.set_visible_child_name("filter");
        while let Some(child) = self.filter_results.first_child() {
            self.filter_results.remove(&child);
        }
        let matches: Vec<PathBuf> = crate::project::walk_files(&self.root, 20_000)
            .into_iter()
            .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().to_lowercase().contains(&needle)))
            .take(500)
            .collect();
        for p in &matches {
            let name = p.file_name().unwrap().to_string_lossy().into_owned();
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            row.add_css_class("file-row");
            let (icon, class) = crate::style::file_icon(&name, false);
            let image = gtk::Image::from_icon_name(icon);
            image.add_css_class(class);
            row.append(&image);
            let label = gtk::Label::new(Some(&name));
            label.set_tooltip_text(Some(&p.strip_prefix(&self.root).unwrap_or(p).display().to_string()));
            row.append(&label);
            self.filter_results.append(&row);
        }
        *self.filter_paths.borrow_mut() = matches;
    }

    // ---- File operations ------------------------------------------------------------------

    fn setup_file_actions(self: &Rc<Self>) {
        let group = gio::SimpleActionGroup::new();
        let add = |name: &str, f: fn(&Rc<Navigator>, PathBuf)| {
            let action = gio::SimpleAction::new(name, Some(glib::VariantTy::STRING));
            let weak = Rc::downgrade(self);
            action.connect_activate(move |_, param| {
                let (Some(n), Some(p)) = (weak.upgrade(), param.and_then(|v| v.get::<String>())) else { return };
                f(&n, PathBuf::from(p));
            });
            group.add_action(&action);
        };
        add("new-file", |n, p| n.prompt_new(p, false));
        add("new-folder", |n, p| n.prompt_new(p, true));
        add("rename", |n, p| n.prompt_rename(p));
        add("delete", |n, p| n.confirm_delete(p));
        add("reveal", |_, p| {
            let target = if p.is_dir() { p } else { p.parent().map(Path::to_path_buf).unwrap_or(p) };
            let uri = gio::File::for_path(&target).uri();
            let _ = gio::AppInfo::launch_default_for_uri(&uri, None::<&gio::AppLaunchContext>);
        });
        add("copy-path", |n, p| n.widget.clipboard().set_text(&p.display().to_string()));
        self.widget.insert_action_group("nav", Some(&group));
    }

    fn ask_name(&self, heading: &str, initial: &str, accept: &str, on_ok: impl Fn(String) + 'static) {
        let dialog = adw::AlertDialog::new(Some(heading), None);
        let entry = gtk::Entry::builder().text(initial).activates_default(true).build();
        dialog.set_extra_child(Some(&entry));
        dialog.add_responses(&[("cancel", "Cancel"), ("ok", accept)]);
        dialog.set_response_appearance("ok", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("ok"));
        dialog.set_close_response("cancel");
        let e = entry.clone();
        dialog.connect_response(Some("ok"), move |_, _| {
            let name = e.text().trim().to_string();
            if !name.is_empty() && !name.contains('/') {
                on_ok(name);
            }
        });
        dialog.present(Some(&self.widget));
        // Select the stem so typing replaces the name but keeps the extension.
        let stem_len = initial.rfind('.').unwrap_or(initial.len()) as i32;
        glib::idle_add_local_once(move || {
            entry.grab_focus();
            entry.select_region(0, stem_len);
        });
    }

    fn prompt_new(self: &Rc<Self>, target: PathBuf, folder: bool) {
        let dir = if target.is_dir() { target } else { target.parent().map(Path::to_path_buf).unwrap_or(target) };
        let weak = Rc::downgrade(self);
        let (heading, initial) = if folder { ("New Folder", "New Folder") } else { ("New File", "File.swift") };
        self.ask_name(heading, initial, "Create", move |name| {
            let Some(n) = weak.upgrade() else { return };
            let path = dir.join(&name);
            if path.exists() {
                n.error(&format!("“{name}” already exists."));
                return;
            }
            let result = if folder {
                std::fs::create_dir_all(&path)
            } else {
                use crate::templates::FileTemplate;
                let template = if name.ends_with("View.swift") {
                    FileTemplate::SwiftUIView
                } else if name.ends_with(".swift") {
                    FileTemplate::SwiftFile
                } else {
                    FileTemplate::Empty
                };
                let meta = crate::project::Project::open(&n.root).meta;
                let contents = template.contents(&name, &n.project_name, &meta.organization);
                std::fs::write(&path, contents)
            };
            match result {
                Ok(()) if !folder => n.emit_open(path, None),
                Ok(()) => {}
                Err(e) => n.error(&format!("Couldn't create “{name}”: {e}")),
            }
        });
    }

    fn prompt_rename(self: &Rc<Self>, path: PathBuf) {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let weak = Rc::downgrade(self);
        self.ask_name("Rename", &name.clone(), "Rename", move |new_name| {
            let Some(n) = weak.upgrade() else { return };
            if new_name == name {
                return;
            }
            let target = path.with_file_name(&new_name);
            if target.exists() {
                n.error(&format!("“{new_name}” already exists."));
                return;
            }
            match std::fs::rename(&path, &target) {
                Ok(()) => {
                    if let Some(cb) = n.callbacks.borrow().deleted.as_ref() {
                        cb(path.clone());
                    }
                    if target.is_file() {
                        n.emit_open(target, None);
                    }
                }
                Err(e) => n.error(&format!("Couldn't rename “{name}”: {e}")),
            }
        });
    }

    fn confirm_delete(self: &Rc<Self>, path: PathBuf) {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let dialog = adw::AlertDialog::new(
            Some(&format!("Move “{name}” to the Trash?")),
            Some("You can restore it from the Trash later."),
        );
        dialog.add_responses(&[("cancel", "Cancel"), ("trash", "Move to Trash")]);
        dialog.set_response_appearance("trash", adw::ResponseAppearance::Destructive);
        dialog.set_close_response("cancel");
        let weak = Rc::downgrade(self);
        dialog.connect_response(Some("trash"), move |_, _| {
            let Some(n) = weak.upgrade() else { return };
            match gio::File::for_path(&path).trash(gio::Cancellable::NONE) {
                Ok(()) => {
                    if let Some(cb) = n.callbacks.borrow().deleted.as_ref() {
                        cb(path.clone());
                    }
                }
                Err(e) => n.error(&format!("Couldn't move “{name}” to the Trash: {e}")),
            }
        });
        dialog.present(Some(&self.widget));
    }

    fn error(&self, message: &str) {
        let dialog = adw::AlertDialog::new(Some(message), None);
        dialog.add_response("ok", "OK");
        dialog.present(Some(&self.widget));
    }

    // ---- Find in project ------------------------------------------------------------------

    fn run_find(self: &Rc<Self>) {
        let query = self.find_entry.text().to_string();
        if query.is_empty() {
            return;
        }
        let case_sensitive = self.find_case.is_active();
        let root = self.root.clone();
        self.find_summary.set_text("Searching…");
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let results = gio::spawn_blocking(move || search_project(&root, &query, case_sensitive)).await.unwrap_or_default();
            if let Some(n) = weak.upgrade() {
                n.show_find_results(results);
            }
        });
    }

    fn show_find_results(&self, results: Vec<FileMatches>) {
        while let Some(child) = self.find_results.first_child() {
            self.find_results.remove(&child);
        }
        let mut locations = Vec::new();
        let total: usize = results.iter().map(|f| f.lines.len()).sum();
        self.find_summary.set_text(&format!(
            "{total} result{} in {} file{}",
            if total == 1 { "" } else { "s" },
            results.len(),
            if results.len() == 1 { "" } else { "s" }
        ));
        for file in results {
            let name = file.path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            header.add_css_class("file-row");
            let (icon, class) = crate::style::file_icon(&name, false);
            let image = gtk::Image::from_icon_name(icon);
            image.add_css_class(class);
            header.append(&image);
            let label = gtk::Label::new(Some(&name));
            label.add_css_class("result-file");
            header.append(&label);
            header.set_tooltip_text(Some(&file.path.strip_prefix(&self.root).unwrap_or(&file.path).display().to_string()));
            let row = gtk::ListBoxRow::builder().child(&header).activatable(false).selectable(false).build();
            self.find_results.append(&row);
            locations.push(None);
            for m in file.lines {
                let snippet = gtk::Label::new(None);
                snippet.set_markup(&m.markup);
                snippet.add_css_class("result-line");
                snippet.set_xalign(0.0);
                snippet.set_ellipsize(gtk::pango::EllipsizeMode::End);
                snippet.set_margin_start(22);
                self.find_results.append(&snippet);
                locations.push(Some((file.path.clone(), m.line, m.column)));
            }
        }
        *self.find_locations.borrow_mut() = locations;
    }

    // ---- Issues ----------------------------------------------------------------------------

    pub fn set_issues(&self, diagnostics: &[Diagnostic]) {
        while let Some(child) = self.issues_list.first_child() {
            self.issues_list.remove(&child);
        }
        let mut locations = Vec::new();
        let mut groups: Vec<(Option<PathBuf>, Vec<&Diagnostic>)> = Vec::new();
        for d in diagnostics.iter().filter(|d| d.severity != Severity::Note) {
            let key = d.location.as_ref().map(|l| l.path.clone());
            match groups.iter_mut().find(|(k, _)| *k == key) {
                Some((_, list)) => list.push(d),
                None => groups.push((key, vec![d])),
            }
        }
        for (path, list) in groups {
            let title = match &path {
                Some(p) => p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
                None => format!("Build {}", self.project_name),
            };
            let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            header.add_css_class("file-row");
            let (icon, class) = crate::style::file_icon(&title, false);
            let image = gtk::Image::from_icon_name(if path.is_some() { icon } else { "emblem-system-symbolic" });
            image.add_css_class(class);
            header.append(&image);
            let label = gtk::Label::new(Some(&title));
            label.add_css_class("result-file");
            header.append(&label);
            let count = gtk::Label::new(Some(&list.len().to_string()));
            count.add_css_class("dim-label");
            count.set_hexpand(true);
            count.set_xalign(1.0);
            header.append(&count);
            let row = gtk::ListBoxRow::builder().child(&header).activatable(false).selectable(false).build();
            self.issues_list.append(&row);
            locations.push(None);
            for d in list {
                let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                line.add_css_class(d.severity.css_class());
                line.set_margin_start(14);
                let icon = gtk::Image::from_icon_name(d.severity.icon_name());
                icon.add_css_class("severity");
                icon.set_valign(gtk::Align::Start);
                line.append(&icon);
                let text = gtk::Label::new(Some(&d.message));
                text.set_wrap(true);
                text.set_wrap_mode(gtk::pango::WrapMode::WordChar);
                text.set_xalign(0.0);
                text.set_hexpand(true);
                line.append(&text);
                if let Some(loc) = &d.location {
                    let pos = gtk::Label::new(Some(&loc.line.to_string()));
                    pos.add_css_class("dim-label");
                    pos.add_css_class("caption");
                    pos.set_valign(gtk::Align::Start);
                    line.append(&pos);
                }
                self.issues_list.append(&line);
                locations.push(d.location.as_ref().map(|l| (l.path.clone(), l.line, l.column)));
            }
        }
        *self.issue_locations.borrow_mut() = locations;
    }

    // ---- Reports ----------------------------------------------------------------------------

    /// Add a report row (newest first) and return its handle.
    pub fn add_report(&self, title: &str) -> gtk::Box {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let icon = gtk::Image::from_icon_name("content-loading-symbolic");
        row.append(&icon);
        let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
        let label = gtk::Label::new(Some(title));
        label.set_xalign(0.0);
        let time = glib::DateTime::now_local()
            .ok()
            .and_then(|d| d.format("Today at %H:%M:%S").ok())
            .map(|s| s.to_string())
            .unwrap_or_default();
        let sub = gtk::Label::new(Some(&time));
        sub.add_css_class("dim-label");
        sub.add_css_class("caption");
        sub.set_xalign(0.0);
        text.append(&label);
        text.append(&sub);
        row.append(&text);
        self.reports_list.prepend(&row);
        self.reports.borrow_mut().insert(0, row.clone());
        row
    }

    pub fn set_report_status(&self, row: &gtk::Box, status: ReportStatus) {
        if let Some(icon) = row.first_child().and_downcast::<gtk::Image>() {
            let (name, class) = match status {
                ReportStatus::Succeeded => ("object-select-symbolic", "success"),
                ReportStatus::Failed => ("dialog-error-symbolic", "error"),
                ReportStatus::Cancelled => ("process-stop-symbolic", "warning"),
            };
            icon.set_icon_name(Some(name));
            if !class.is_empty() {
                icon.add_css_class(class);
            }
        }
    }
}

pub struct LineMatch {
    pub line: u32,
    pub column: u32,
    pub markup: String,
}

pub struct FileMatches {
    pub path: PathBuf,
    pub lines: Vec<LineMatch>,
}

/// Plain-text search across project files (skips hidden folders and binaries).
pub fn search_project(root: &Path, query: &str, case_sensitive: bool) -> Vec<FileMatches> {
    let needle = if case_sensitive { query.to_string() } else { query.to_lowercase() };
    let mut out = Vec::new();
    let mut total = 0;
    for path in crate::project::walk_files(root, 50_000) {
        let Ok(meta) = std::fs::metadata(&path) else { continue };
        if meta.len() > 2 * 1024 * 1024 {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(&path) else { continue };
        let mut lines = Vec::new();
        for (i, line) in text.lines().enumerate() {
            let hay = if case_sensitive { line.to_string() } else { line.to_lowercase() };
            // Lowercasing can change byte lengths for non-ASCII text; only trust ASCII offsets.
            let Some(idx) = hay.find(&needle) else { continue };
            let (before, matched, after) = if hay.len() == line.len() && line.is_char_boundary(idx) && line.is_char_boundary(idx + needle.len()) {
                (&line[..idx], &line[idx..idx + needle.len()], &line[idx + needle.len()..])
            } else {
                (line, "", "")
            };
            let lead = before.len() - before.trim_start().len();
            let markup = format!(
                "{}<b>{}</b>{}",
                glib::markup_escape_text(&before[lead..]),
                glib::markup_escape_text(matched),
                glib::markup_escape_text(after)
            );
            lines.push(LineMatch { line: i as u32 + 1, column: before.chars().count() as u32 + 1, markup });
            total += 1;
            if total >= 2000 {
                break;
            }
        }
        if !lines.is_empty() {
            out.push(FileMatches { path, lines });
        }
        if total >= 2000 {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_matches_with_positions() {
        let dir = std::env::temp_dir().join(format!("lcode-find-{}", std::process::id()));
        std::fs::create_dir_all(dir.join(".build")).unwrap();
        std::fs::write(dir.join("a.swift"), "let x = 1\n    print(<Hello>)\n").unwrap();
        std::fs::write(dir.join(".build/b.swift"), "print(hello)\n").unwrap();
        let r = search_project(&dir, "hello", false);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].lines[0].line, 2);
        assert_eq!(r[0].lines[0].column, 12);
        assert_eq!(r[0].lines[0].markup, "print(&lt;<b>Hello</b>&gt;)");
        assert!(search_project(&dir, "hello", true).is_empty());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
