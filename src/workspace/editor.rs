//! The source editor: tabs, jump bar, find & replace, minimap and inline issues.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::sync::LazyLock;

use adw::prelude::*;
use gtk::{gdk, gio, glib};
use regex::Regex;
use sourceview5::prelude::*;

use crate::diagnostics::{Diagnostic, Severity};

struct InlineIssue {
    line: i32,
    severity: Severity,
    message: String,
    mark: gtk::TextMark,
    /// Only the first issue on a line gets an inline banner.
    show_banner: bool,
}

pub struct Document {
    pub path: Option<PathBuf>,
    pub title: String,
    pub buffer: sourceview5::Buffer,
    pub view: sourceview5::View,
    pub map: sourceview5::Map,
    pub page: adw::TabPage,
    /// Transparent layer over the view where inline issue banners are drawn.
    banners: gtk::DrawingArea,
    pub read_only: bool,
    search: sourceview5::SearchContext,
    issues: RefCell<Vec<InlineIssue>>,
}

impl Document {
    pub fn is_modified(&self) -> bool {
        !self.read_only && self.buffer.is_modified()
    }

    pub fn text(&self) -> String {
        self.buffer.text(&self.buffer.start_iter(), &self.buffer.end_iter(), true).to_string()
    }

    pub fn save(&self) -> std::io::Result<()> {
        let Some(path) = &self.path else { return Ok(()) };
        if self.read_only {
            return Ok(());
        }
        std::fs::write(path, self.text())?;
        self.buffer.set_modified(false);
        Ok(())
    }

    /// 1-based (line, column) of the cursor.
    pub fn cursor(&self) -> (i32, i32) {
        let iter = self.buffer.iter_at_offset(self.buffer.cursor_position());
        (iter.line() + 1, iter.line_offset() + 1)
    }

    pub fn go_to(&self, line: u32, column: u32) {
        let line = (line.max(1) - 1) as i32;
        let iter = self
            .buffer
            .iter_at_line_offset(line, column.max(1) as i32 - 1)
            .or_else(|| self.buffer.iter_at_line(line))
            .unwrap_or_else(|| self.buffer.end_iter());
        self.buffer.place_cursor(&iter);
        let view = self.view.clone();
        let buffer = self.buffer.clone();
        // Scroll once the view has been laid out.
        glib::timeout_add_local_once(std::time::Duration::from_millis(60), move || {
            view.scroll_to_mark(&buffer.get_insert(), 0.0, true, 0.0, 0.35);
        });
        self.view.grab_focus();
    }
}

static SYMBOL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|static|final|override|mutating|nonisolated|indirect|class|convenience|required)\s+)*(func|struct|class|enum|protocol|extension|actor|init|typealias)\b\s*([A-Za-z_][\w.]*)?",
    )
    .unwrap()
});

#[derive(Debug, Clone, PartialEq)]
pub struct Symbol {
    pub line: u32,
    pub kind: String,
    pub name: String,
}

/// A rough outline of a Swift file for the jump bar.
pub fn symbols(text: &str) -> Vec<Symbol> {
    let mut out = Vec::new();
    let mut in_block_comment = false;
    for (i, line) in text.lines().enumerate() {
        let trimmed = line.trim_start();
        if in_block_comment {
            if trimmed.contains("*/") {
                in_block_comment = false;
            }
            continue;
        }
        if trimmed.starts_with("/*") {
            in_block_comment = !trimmed.contains("*/");
            continue;
        }
        if trimmed.starts_with("//") {
            if let Some(mark) = trimmed.strip_prefix("// MARK:") {
                out.push(Symbol { line: i as u32 + 1, kind: "mark".into(), name: mark.trim().trim_start_matches("- ").to_string() });
            }
            continue;
        }
        if let Some(c) = SYMBOL.captures(line) {
            let kind = c[1].to_string();
            let name = c.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| kind.clone());
            out.push(Symbol { line: i as u32 + 1, kind, name });
        }
    }
    out
}

/// Letter badge (text, css class) for a symbol kind.
fn symbol_badge(kind: &str) -> gtk::Label {
    let (text, class) = match kind {
        "func" | "init" => ("M", "func"),
        "struct" => ("S", "type"),
        "class" => ("C", "type"),
        "actor" => ("A", "type"),
        "enum" => ("E", "enum"),
        "protocol" => ("Pr", "proto"),
        "extension" => ("Ex", "ext"),
        "typealias" => ("T", "proto"),
        _ => ("#", "mark"),
    };
    let label = gtk::Label::new(Some(text));
    label.add_css_class("symbol-badge");
    label.add_css_class(class);
    label
}

type OpenCallback = Box<dyn Fn(PathBuf, Option<(u32, u32)>)>;
type CurrentCallback = Box<dyn Fn(Option<Rc<Document>>)>;

pub struct Editor {
    pub widget: gtk::Box,
    tab_view: adw::TabView,
    stack: gtk::Stack,
    crumbs: gtk::Box,
    position: gtk::Label,
    find_revealer: gtk::Revealer,
    find_entry: gtk::SearchEntry,
    replace_entry: gtk::Entry,
    find_count: gtk::Label,
    search_settings: sourceview5::SearchSettings,
    words: sourceview5::CompletionWords,
    docs: RefCell<Vec<Rc<Document>>>,
    root: RefCell<PathBuf>,
    project_name: RefCell<String>,
    diagnostics: RefCell<Vec<Diagnostic>>,
    on_open: RefCell<Option<OpenCallback>>,
    on_current: RefCell<Vec<CurrentCallback>>,
}

impl Editor {
    pub fn new(root: &Path, project_name: &str) -> Rc<Self> {
        let tab_view = adw::TabView::new();
        let tab_bar = adw::TabBar::new();
        tab_bar.set_view(Some(&tab_view));
        tab_bar.set_autohide(false);

        // Jump bar.
        let jump = gtk::Box::new(gtk::Orientation::Horizontal, 2);
        jump.add_css_class("jump-bar");
        let crumbs = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        crumbs.set_hexpand(true);
        let position = gtk::Label::new(None);
        position.add_css_class("dim-label");
        position.add_css_class("caption");
        jump.append(&crumbs);
        jump.append(&position);

        // Find & replace bar.
        let find_entry = gtk::SearchEntry::builder().placeholder_text("Find").hexpand(true).build();
        let replace_entry = gtk::Entry::builder().placeholder_text("Replace").hexpand(true).build();
        let find_count = gtk::Label::new(None);
        find_count.add_css_class("dim-label");
        find_count.set_width_chars(10);
        let prev = gtk::Button::from_icon_name("go-up-symbolic");
        prev.set_tooltip_text(Some("Find Previous (Shift+Ctrl+G)"));
        prev.set_action_name(Some("win.find-previous"));
        let next = gtk::Button::from_icon_name("go-down-symbolic");
        next.set_tooltip_text(Some("Find Next (Ctrl+G)"));
        next.set_action_name(Some("win.find-next"));
        let nav = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        nav.add_css_class("linked");
        nav.append(&prev);
        nav.append(&next);
        let replace = gtk::Button::with_label("Replace");
        let replace_all = gtk::Button::with_label("All");
        let done = gtk::Button::with_label("Done");
        let case = gtk::ToggleButton::builder().label("Aa").tooltip_text("Match Case").build();
        let find_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        find_row.append(&find_entry);
        find_row.append(&find_count);
        find_row.append(&case);
        find_row.append(&nav);
        find_row.append(&done);
        let replace_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        replace_row.append(&replace_entry);
        replace_row.append(&replace);
        replace_row.append(&replace_all);
        let find_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
        find_box.add_css_class("find-bar");
        find_box.append(&find_row);
        find_box.append(&replace_row);
        let find_revealer = gtk::Revealer::builder().child(&find_box).reveal_child(false).build();

        let empty = gtk::Label::new(Some("No Editor"));
        empty.add_css_class("editor-empty");
        let stack = gtk::Stack::new();
        stack.add_named(&empty, Some("empty"));
        stack.add_named(&tab_view, Some("tabs"));
        stack.set_vexpand(true);

        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        widget.append(&tab_bar);
        widget.append(&jump);
        widget.append(&find_revealer);
        widget.append(&stack);

        let search_settings = sourceview5::SearchSettings::new();
        search_settings.set_wrap_around(true);
        case.bind_property("active", &search_settings, "case-sensitive").sync_create().build();

        let editor = Rc::new(Editor {
            widget,
            tab_view,
            stack,
            crumbs,
            position,
            find_revealer,
            find_entry,
            replace_entry,
            find_count,
            search_settings,
            words: sourceview5::CompletionWords::new(Some("Words")),
            docs: RefCell::new(Vec::new()),
            root: RefCell::new(root.to_path_buf()),
            project_name: RefCell::new(project_name.to_string()),
            diagnostics: RefCell::new(Vec::new()),
            on_open: RefCell::new(None),
            on_current: RefCell::new(Vec::new()),
        });
        editor.update_chrome();

        let weak = Rc::downgrade(&editor);
        editor.tab_view.connect_selected_page_notify(move |_| {
            if let Some(e) = weak.upgrade() {
                e.update_chrome();
                if let Some(doc) = e.current() {
                    doc.search.set_highlight(e.find_revealer.reveals_child());
                }
            }
        });
        let weak = Rc::downgrade(&editor);
        editor.tab_view.connect_close_page(move |tv, page| {
            if let Some(e) = weak.upgrade() {
                e.close_page(page);
            } else {
                tv.close_page_finish(page, true);
            }
            glib::Propagation::Stop
        });
        let weak = Rc::downgrade(&editor);
        editor.tab_view.connect_page_detached(move |_, page, _| {
            if let Some(e) = weak.upgrade() {
                e.docs.borrow_mut().retain(|d| &d.page != page);
                e.update_chrome();
            }
        });

        // Find bar wiring.
        let weak = Rc::downgrade(&editor);
        editor.find_entry.connect_search_changed(move |entry| {
            if let Some(e) = weak.upgrade() {
                e.search_settings.set_search_text(Some(&entry.text()).filter(|t| !t.is_empty()).map(|t| t.as_str()));
                e.find(true, true);
            }
        });
        let weak = Rc::downgrade(&editor);
        editor.find_entry.connect_activate(move |_| {
            if let Some(e) = weak.upgrade() {
                e.find(true, false);
            }
        });
        let weak = Rc::downgrade(&editor);
        editor.find_entry.connect_stop_search(move |_| {
            if let Some(e) = weak.upgrade() {
                e.hide_find();
            }
        });
        let weak = Rc::downgrade(&editor);
        done.connect_clicked(move |_| {
            if let Some(e) = weak.upgrade() {
                e.hide_find();
            }
        });
        let weak = Rc::downgrade(&editor);
        replace.connect_clicked(move |_| {
            if let Some(e) = weak.upgrade() {
                e.replace_one();
            }
        });
        let weak = Rc::downgrade(&editor);
        replace_all.connect_clicked(move |_| {
            if let Some(e) = weak.upgrade() {
                e.replace_all();
            }
        });

        // Follow light/dark changes.
        let weak = Rc::downgrade(&editor);
        adw::StyleManager::default().connect_dark_notify(move |_| {
            if let Some(e) = weak.upgrade() {
                let scheme = crate::style::editor_scheme();
                for d in e.docs.borrow().iter() {
                    d.buffer.set_style_scheme(scheme.as_ref());
                }
            }
        });
        editor
    }

    pub fn connect_open_request(&self, f: impl Fn(PathBuf, Option<(u32, u32)>) + 'static) {
        *self.on_open.borrow_mut() = Some(Box::new(f));
    }

    pub fn connect_current_changed(&self, f: impl Fn(Option<Rc<Document>>) + 'static) {
        self.on_current.borrow_mut().push(Box::new(f));
    }

    pub fn current(&self) -> Option<Rc<Document>> {
        let page = self.tab_view.selected_page()?;
        self.docs.borrow().iter().find(|d| d.page == page).cloned()
    }

    pub fn documents(&self) -> Vec<Rc<Document>> {
        self.docs.borrow().clone()
    }

    pub fn open_files(&self) -> Vec<PathBuf> {
        (0..self.tab_view.n_pages())
            .filter_map(|i| {
                let page = self.tab_view.nth_page(i);
                self.docs.borrow().iter().find(|d| d.page == page).and_then(|d| d.path.clone())
            })
            .collect()
    }

    pub fn find_document(&self, path: &Path) -> Option<Rc<Document>> {
        self.docs.borrow().iter().find(|d| d.path.as_deref() == Some(path)).cloned()
    }

    /// Open (or switch to) a file, optionally jumping to a 1-based line and column.
    pub fn open(self: &Rc<Self>, path: &Path, location: Option<(u32, u32)>) -> Result<Rc<Document>, String> {
        if let Some(doc) = self.find_document(path) {
            self.tab_view.set_selected_page(&doc.page);
            if let Some((l, c)) = location {
                doc.go_to(l, c);
            }
            return Ok(doc);
        }
        let bytes = std::fs::read(path).map_err(|e| format!("Couldn't open “{}”: {e}", path.display()))?;
        if bytes.len() > 8 * 1024 * 1024 {
            return Err(format!("“{}” is too large to edit.", path.display()));
        }
        let (text, read_only) = match String::from_utf8(bytes) {
            Ok(t) => (t, false),
            Err(e) => {
                if e.as_bytes().iter().take(8000).any(|&b| b == 0) {
                    return Err(format!("“{}” is a binary file.", path.display()));
                }
                (String::from_utf8_lossy(e.as_bytes()).into_owned(), true)
            }
        };
        let title = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let doc = self.add_document(Some(path.to_path_buf()), &title, &text, read_only);
        if let Some((l, c)) = location {
            doc.go_to(l, c);
        }
        Ok(doc)
    }

    /// Open read-only text (e.g. a build log) in a tab.
    pub fn open_text(self: &Rc<Self>, title: &str, text: &str) -> Rc<Document> {
        if let Some(doc) = self.docs.borrow().iter().find(|d| d.path.is_none() && d.title == title).cloned() {
            doc.buffer.set_text(text);
            self.tab_view.set_selected_page(&doc.page);
            return doc;
        }
        self.add_document(None, title, text, true)
    }

    fn add_document(self: &Rc<Self>, path: Option<PathBuf>, title: &str, text: &str, read_only: bool) -> Rc<Document> {
        let settings = crate::settings::get();
        let buffer = sourceview5::Buffer::new(None::<&gtk::TextTagTable>);
        if let Some(p) = &path
            && let Some(lang) = sourceview5::LanguageManager::default().guess_language(Some(p), None) {
                buffer.set_language(Some(&lang));
            }
        buffer.set_style_scheme(crate::style::editor_scheme().as_ref());
        buffer.set_highlight_matching_brackets(true);
        buffer.begin_irreversible_action();
        buffer.set_text(text);
        buffer.end_irreversible_action();
        buffer.set_modified(false);
        buffer.place_cursor(&buffer.start_iter());
        buffer.create_tag(Some("issue-error"), &[("underline", &gtk::pango::Underline::Error)]);
        buffer.create_tag(Some("issue-warning"), &[("underline", &gtk::pango::Underline::Error), ("underline-rgba", &gdk::RGBA::new(1.0, 0.8, 0.0, 1.0))]);

        let view = sourceview5::View::with_buffer(&buffer);
        view.add_css_class("editor-view");
        view.set_monospace(true);
        view.set_show_line_numbers(true);
        view.set_show_line_marks(true);
        view.set_highlight_current_line(true);
        view.set_auto_indent(true);
        view.set_indent_on_tab(true);
        view.set_smart_backspace(true);
        view.set_smart_home_end(sourceview5::SmartHomeEndType::Before);
        view.set_tab_width(settings.tab_width.clamp(1, 16));
        view.set_indent_width(-1);
        view.set_insert_spaces_instead_of_tabs(settings.indent_with_spaces);
        view.set_editable(!read_only);
        view.set_left_margin(4);
        view.set_top_margin(4);
        view.set_bottom_margin(200);
        view.set_has_tooltip(true);
        for (category, icon, color) in [
            ("error", "dialog-error-symbolic", gdk::RGBA::new(1.0, 0.23, 0.19, 0.14)),
            ("warning", "dialog-warning-symbolic", gdk::RGBA::new(1.0, 0.8, 0.0, 0.14)),
        ] {
            let attrs = sourceview5::MarkAttributes::new();
            attrs.set_icon_name(icon);
            attrs.set_background(&color);
            view.set_mark_attributes(category, &attrs, 10);
        }
        if !read_only {
            self.words.register(&buffer);
            view.completion().add_provider(&self.words);
        }

        let map = sourceview5::Map::new();
        map.set_view(&view);
        map.add_css_class("editor-map");
        map.set_visible(settings.show_minimap && !read_only);

        let scroller = gtk::ScrolledWindow::builder().child(&view).hexpand(true).vexpand(true).build();
        let banners = gtk::DrawingArea::new();
        banners.set_can_target(false);
        let overlay = gtk::Overlay::new();
        overlay.set_child(Some(&scroller));
        overlay.add_overlay(&banners);
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        row.append(&overlay);
        row.append(&map);

        let page = self.tab_view.append(&row);
        page.set_title(title);
        page.set_tooltip(&path.as_ref().map(|p| p.display().to_string()).unwrap_or_else(|| title.to_string()));
        let (icon, _) = crate::style::file_icon(title, false);
        page.set_icon(Some(&gio::ThemedIcon::new(if read_only && path.is_none() { "text-x-generic-symbolic" } else { icon })));

        let search = sourceview5::SearchContext::new(&buffer, Some(&self.search_settings));
        search.set_highlight(false);

        let doc = Rc::new(Document {
            path,
            title: title.to_string(),
            buffer: buffer.clone(),
            view: view.clone(),
            map,
            page: page.clone(),
            banners: banners.clone(),
            read_only,
            search: search.clone(),
            issues: RefCell::new(Vec::new()),
        });
        self.docs.borrow_mut().push(doc.clone());

        let weak_doc = Rc::downgrade(&doc);
        let title_owned = title.to_string();
        buffer.connect_modified_changed(move |b| {
            if let Some(d) = weak_doc.upgrade() {
                d.page.set_title(&if b.is_modified() { format!("{title_owned} •") } else { title_owned.clone() });
            }
        });
        let weak: Weak<Editor> = Rc::downgrade(self);
        buffer.connect_cursor_position_notify(move |_| {
            if let Some(e) = weak.upgrade() {
                e.update_position();
            }
        });
        let weak_doc = Rc::downgrade(&doc);
        banners.set_draw_func(move |area, cr, _, _| {
            if let Some(d) = weak_doc.upgrade() {
                draw_banners(&d, area, cr);
            }
        });
        let redraw = {
            let banners = banners.clone();
            move || banners.queue_draw()
        };
        {
            let r = redraw.clone();
            buffer.connect_changed(move |_| r());
            let r = redraw.clone();
            scroller.vadjustment().connect_value_changed(move |_| r());
            let r = redraw.clone();
            scroller.hadjustment().connect_value_changed(move |_| r());
        }
        let weak = Rc::downgrade(self);
        search.connect_occurrences_count_notify(move |_| {
            if let Some(e) = weak.upgrade() {
                e.update_find_count();
            }
        });
        let weak_doc = Rc::downgrade(&doc);
        view.connect_query_tooltip(move |view, x, y, _, tooltip| {
            let Some(d) = weak_doc.upgrade() else { return false };
            let (bx, by) = view.window_to_buffer_coords(gtk::TextWindowType::Widget, x, y);
            let Some(iter) = view.iter_at_location(bx, by) else { return false };
            let messages: Vec<String> = d
                .issues
                .borrow()
                .iter()
                .filter(|i| i.line == iter.line())
                .map(|i| format!("{}: {}", if i.severity == Severity::Error { "error" } else { "warning" }, i.message))
                .collect();
            if messages.is_empty() {
                return false;
            }
            tooltip.set_text(Some(&messages.join("\n")));
            true
        });

        self.apply_diagnostics(&doc);
        self.tab_view.set_selected_page(&page);
        self.update_chrome();
        view.grab_focus();
        doc
    }

    fn close_page(self: &Rc<Self>, page: &adw::TabPage) {
        let doc = self.docs.borrow().iter().find(|d| &d.page == page).cloned();
        let Some(doc) = doc.filter(|d| d.is_modified()) else {
            self.tab_view.close_page_finish(page, true);
            return;
        };
        let dialog = adw::AlertDialog::new(
            Some(&format!("Do you want to keep the changes you made to “{}”?", doc.title)),
            Some("Your changes will be lost if you don't save them."),
        );
        dialog.add_responses(&[("cancel", "Cancel"), ("discard", "Don't Save"), ("save", "Save")]);
        dialog.set_response_appearance("discard", adw::ResponseAppearance::Destructive);
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));
        dialog.set_close_response("cancel");
        let weak = Rc::downgrade(self);
        let page = page.clone();
        dialog.connect_response(None, move |_, response| {
            let Some(e) = weak.upgrade() else { return };
            match response {
                "save" => {
                    let ok = doc.save().is_ok();
                    e.tab_view.close_page_finish(&page, ok);
                }
                "discard" => e.tab_view.close_page_finish(&page, true),
                _ => e.tab_view.close_page_finish(&page, false),
            }
        });
        dialog.present(Some(&self.widget));
    }

    pub fn close_current(&self) {
        if let Some(page) = self.tab_view.selected_page() {
            self.tab_view.close_page(&page);
        }
    }

    /// Close the tab for a file without prompting (used after deletes).
    pub fn forget(&self, path: &Path) {
        let docs: Vec<_> =
            self.docs.borrow().iter().filter(|d| d.path.as_deref().is_some_and(|p| p.starts_with(path))).cloned().collect();
        for d in docs {
            d.buffer.set_modified(false);
            self.tab_view.close_page(&d.page);
        }
    }

    pub fn save_current(&self) -> Result<(), String> {
        match self.current() {
            Some(doc) => doc.save().map_err(|e| format!("Couldn't save “{}”: {e}", doc.title)),
            None => Ok(()),
        }
    }

    pub fn save_all(&self) -> Result<(), String> {
        for doc in self.documents() {
            if doc.is_modified() {
                doc.save().map_err(|e| format!("Couldn't save “{}”: {e}", doc.title))?;
            }
        }
        Ok(())
    }

    pub fn has_unsaved_changes(&self) -> bool {
        self.docs.borrow().iter().any(|d| d.is_modified())
    }

    pub fn apply_settings(&self) {
        let s = crate::settings::get();
        for d in self.docs.borrow().iter() {
            d.view.set_tab_width(s.tab_width.clamp(1, 16));
            d.view.set_insert_spaces_instead_of_tabs(s.indent_with_spaces);
            d.map.set_visible(s.show_minimap && !d.read_only);
        }
    }

    pub fn set_minimap_visible(&self, visible: bool) {
        for d in self.docs.borrow().iter() {
            d.map.set_visible(visible && !d.read_only);
        }
    }

    // ---- Chrome: jump bar & position ------------------------------------------------

    fn update_chrome(self: &Rc<Self>) {
        let doc = self.current();
        self.stack.set_visible_child_name(if self.tab_view.n_pages() > 0 { "tabs" } else { "empty" });
        self.rebuild_crumbs(doc.as_ref());
        self.update_position();
        for cb in self.on_current.borrow().iter() {
            cb(doc.clone());
        }
    }

    fn update_position(self: &Rc<Self>) {
        match self.current() {
            Some(doc) => {
                let (l, c) = doc.cursor();
                self.position.set_text(&format!("Line: {l}  Col: {c}"));
                self.update_symbol_crumb(&doc);
            }
            None => self.position.set_text(""),
        }
    }

    fn rebuild_crumbs(self: &Rc<Self>, doc: Option<&Rc<Document>>) {
        while let Some(child) = self.crumbs.first_child() {
            self.crumbs.remove(&child);
        }
        let root = self.root.borrow().clone();
        let chevron = || {
            let i = gtk::Image::from_icon_name("go-next-symbolic");
            i.add_css_class("crumb-chevron");
            i
        };
        let project = self.crumb_button(&self.project_name.borrow(), crate::APP_ID, Some(root.clone()));
        self.crumbs.append(&project);
        let Some(doc) = doc else { return };
        let Some(path) = &doc.path else {
            self.crumbs.append(&chevron());
            let l = gtk::Label::new(Some(&doc.title));
            self.crumbs.append(&l);
            return;
        };
        let rel = path.strip_prefix(&root).unwrap_or(path);
        let mut acc = root.clone();
        let components: Vec<_> = rel.components().collect();
        for (i, comp) in components.iter().enumerate() {
            acc.push(comp);
            let name = comp.as_os_str().to_string_lossy().into_owned();
            let is_last = i + 1 == components.len();
            let (icon, _) = crate::style::file_icon(&name, !is_last);
            self.crumbs.append(&chevron());
            // Each crumb lists its siblings, so it opens the parent directory.
            let parent = acc.parent().map(Path::to_path_buf);
            self.crumbs.append(&self.crumb_button(&name, icon, parent));
        }
        self.crumbs.append(&chevron());
        let symbol = gtk::MenuButton::new();
        symbol.add_css_class("flat");
        symbol.set_widget_name("symbol-crumb");
        let weak = Rc::downgrade(self);
        symbol.set_create_popup_func(move |mb| {
            if let Some(e) = weak.upgrade() {
                mb.set_popover(Some(&e.symbol_popover()));
            }
        });
        self.crumbs.append(&symbol);
        self.update_symbol_crumb(doc);
    }

    fn update_symbol_crumb(&self, doc: &Rc<Document>) {
        let mut child = self.crumbs.last_child();
        while let Some(w) = child {
            if w.widget_name() == "symbol-crumb" {
                if let Some(mb) = w.downcast_ref::<gtk::MenuButton>() {
                    let (line, _) = doc.cursor();
                    let syms = symbols(&doc.text());
                    let current = syms.iter().rev().find(|s| s.line as i32 <= line && s.kind != "mark");
                    mb.set_label(&current.map(|s| s.name.clone()).unwrap_or_else(|| "No Selection".into()));
                }
                return;
            }
            child = w.prev_sibling();
        }
    }

    fn symbol_popover(self: &Rc<Self>) -> gtk::Popover {
        let list = gtk::ListBox::new();
        list.set_selection_mode(gtk::SelectionMode::None);
        let syms = self.current().map(|d| symbols(&d.text())).unwrap_or_default();
        if syms.is_empty() {
            list.append(&gtk::Label::new(Some("No Symbols")));
        }
        for s in &syms {
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            let indent = if matches!(s.kind.as_str(), "func" | "init" | "typealias") { 16 } else { 0 };
            row.set_margin_start(indent);
            row.append(&symbol_badge(&s.kind));
            let label = gtk::Label::new(Some(&s.name));
            if s.kind == "mark" {
                label.add_css_class("heading");
            }
            row.append(&label);
            list.append(&row);
        }
        let popover = gtk::Popover::new();
        let scroller = gtk::ScrolledWindow::builder()
            .child(&list)
            .propagate_natural_height(true)
            .max_content_height(480)
            .min_content_width(260)
            .build();
        popover.set_child(Some(&scroller));
        let weak = Rc::downgrade(self);
        let pop = popover.clone();
        list.set_activate_on_single_click(true);
        list.connect_row_activated(move |_, row| {
            if let (Some(e), Some(s)) = (weak.upgrade(), syms.get(row.index() as usize))
                && let Some(d) = e.current() {
                    d.go_to(s.line, 1);
                }
            pop.popdown();
        });
        popover
    }

    fn crumb_button(self: &Rc<Self>, label: &str, icon: &str, dir: Option<PathBuf>) -> gtk::MenuButton {
        let content = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        let image = gtk::Image::from_icon_name(icon);
        image.set_pixel_size(14);
        content.append(&image);
        content.append(&gtk::Label::new(Some(label)));
        let mb = gtk::MenuButton::builder().child(&content).always_show_arrow(false).build();
        mb.add_css_class("flat");
        let weak = Rc::downgrade(self);
        mb.set_create_popup_func(move |mb| {
            let (Some(e), Some(dir)) = (weak.upgrade(), dir.clone()) else { return };
            mb.set_popover(Some(&e.directory_popover(&dir)));
        });
        mb
    }

    fn directory_popover(self: &Rc<Self>, dir: &Path) -> gtk::Popover {
        let list = gtk::ListBox::new();
        let mut entries: Vec<(String, PathBuf, bool)> = std::fs::read_dir(dir)
            .map(|rd| {
                rd.flatten()
                    .filter_map(|e| {
                        let name = e.file_name().to_string_lossy().into_owned();
                        (!crate::project::is_ignored(&name)).then(|| {
                            let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                            (name, e.path(), is_dir)
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        entries.sort_by(|a, b| b.2.cmp(&a.2).then(a.0.to_lowercase().cmp(&b.0.to_lowercase())));
        for (name, _, is_dir) in &entries {
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            row.add_css_class("file-row");
            let (icon, class) = crate::style::file_icon(name, *is_dir);
            let image = gtk::Image::from_icon_name(icon);
            image.add_css_class(class);
            row.append(&image);
            row.append(&gtk::Label::new(Some(name)));
            list.append(&row);
        }
        let popover = gtk::Popover::new();
        let scroller = gtk::ScrolledWindow::builder()
            .child(&list)
            .propagate_natural_height(true)
            .max_content_height(480)
            .min_content_width(220)
            .build();
        popover.set_child(Some(&scroller));
        let weak = Rc::downgrade(self);
        let pop = popover.clone();
        list.set_activate_on_single_click(true);
        list.connect_row_activated(move |_, row| {
            pop.popdown();
            let (Some(e), Some((_, path, is_dir))) = (weak.upgrade(), entries.get(row.index() as usize)) else { return };
            if !is_dir
                && let Some(cb) = e.on_open.borrow().as_ref() {
                    cb(path.clone(), None);
                }
        });
        popover
    }

    // ---- Diagnostics -----------------------------------------------------------------

    pub fn set_diagnostics(&self, diagnostics: &[Diagnostic]) {
        *self.diagnostics.borrow_mut() = diagnostics.to_vec();
        for doc in self.docs.borrow().iter() {
            self.apply_diagnostics(doc);
        }
    }

    fn apply_diagnostics(&self, doc: &Rc<Document>) {
        let buffer = &doc.buffer;
        for issue in doc.issues.borrow_mut().drain(..) {
            buffer.delete_mark(&issue.mark);
        }
        let (start, end) = buffer.bounds();
        buffer.remove_source_marks(&start, &end, None);
        buffer.remove_tag_by_name("issue-error", &start, &end);
        buffer.remove_tag_by_name("issue-warning", &start, &end);
        let Some(path) = &doc.path else { return };

        let mut issues = Vec::new();
        for d in self.diagnostics.borrow().iter() {
            let Some(loc) = &d.location else { continue };
            if &loc.path != path || d.severity == Severity::Note {
                continue;
            }
            let line = loc.line.max(1) as i32 - 1;
            let Some(line_start) = buffer.iter_at_line(line) else { continue };
            let from = buffer.iter_at_line_offset(line, loc.column.max(1) as i32 - 1).unwrap_or(line_start);
            let mut to = from;
            if !to.ends_line() {
                to.forward_to_line_end();
            }
            let (category, tag) =
                if d.severity == Severity::Error { ("error", "issue-error") } else { ("warning", "issue-warning") };
            buffer.create_source_mark(None, category, &line_start);
            buffer.apply_tag_by_name(tag, &from, &to);
            let show_banner = !issues.iter().any(|i: &InlineIssue| i.line == line);
            issues.push(InlineIssue {
                line,
                severity: d.severity,
                message: d.message.clone(),
                mark: buffer.create_mark(None, &line_start, true),
                show_banner,
            });
        }
        *doc.issues.borrow_mut() = issues;
        doc.banners.queue_draw();
    }

    // ---- Find & replace ----------------------------------------------------------------

    pub fn show_find(self: &Rc<Self>) {
        let Some(doc) = self.current() else { return };
        if let Some((s, e)) = doc.buffer.selection_bounds()
            && s.line() == e.line() {
                self.find_entry.set_text(&doc.buffer.text(&s, &e, false));
            }
        self.find_revealer.set_reveal_child(true);
        doc.search.set_highlight(true);
        self.find_entry.grab_focus();
        self.find_entry.select_region(0, -1);
    }

    pub fn hide_find(&self) {
        self.find_revealer.set_reveal_child(false);
        for d in self.docs.borrow().iter() {
            d.search.set_highlight(false);
        }
        if let Some(doc) = self.current() {
            doc.view.grab_focus();
        }
    }

    /// Select the next (or previous) match. `from_selection_start` keeps the
    /// current match selected while typing.
    pub fn find(&self, forward: bool, from_selection_start: bool) {
        let Some(doc) = self.current() else { return };
        let buffer = &doc.buffer;
        let (sel_start, sel_end) = buffer
            .selection_bounds()
            .unwrap_or_else(|| {
                let i = buffer.iter_at_offset(buffer.cursor_position());
                (i, i)
            });
        let found = if forward {
            doc.search.forward(if from_selection_start { &sel_start } else { &sel_end })
        } else {
            doc.search.backward(&sel_start)
        };
        if let Some((start, end, _)) = found {
            buffer.select_range(&start, &end);
            let mark = buffer.get_insert();
            doc.view.scroll_to_mark(&mark, 0.15, false, 0.0, 0.0);
        }
        self.update_find_count();
    }

    fn update_find_count(&self) {
        let text = match self.current().map(|d| d.search.occurrences_count()) {
            _ if self.find_entry.text().is_empty() => String::new(),
            Some(n) if n >= 0 => format!("{n} match{}", if n == 1 { "" } else { "es" }),
            _ => String::new(),
        };
        self.find_count.set_text(&text);
    }

    fn replace_one(&self) {
        let Some(doc) = self.current() else { return };
        if let Some((mut s, mut e)) = doc.buffer.selection_bounds() {
            let _ = doc.search.replace(&mut s, &mut e, &self.replace_entry.text());
        }
        self.find(true, false);
    }

    fn replace_all(&self) {
        if let Some(doc) = self.current() {
            let _ = doc.search.replace_all(&self.replace_entry.text());
        }
    }

    // ---- Editing commands ------------------------------------------------------------------

    pub fn toggle_comment(&self) {
        let Some(doc) = self.current() else { return };
        if doc.read_only {
            return;
        }
        let buffer = &doc.buffer;
        let (s, e) = buffer.selection_bounds().unwrap_or_else(|| {
            let i = buffer.iter_at_offset(buffer.cursor_position());
            (i, i)
        });
        let first = s.line();
        let mut last = e.line();
        if last > first && e.line_offset() == 0 {
            last -= 1;
        }
        let lines: Vec<String> = (first..=last)
            .map(|l| {
                let start = buffer.iter_at_line(l).unwrap();
                let mut end = start;
                if !end.ends_line() {
                    end.forward_to_line_end();
                }
                buffer.text(&start, &end, false).to_string()
            })
            .collect();
        let new_lines = toggle_comment_lines(&lines);
        buffer.begin_user_action();
        for (i, line) in new_lines.iter().enumerate().rev() {
            let l = first + i as i32;
            let mut start = buffer.iter_at_line(l).unwrap();
            let mut end = start;
            if !end.ends_line() {
                end.forward_to_line_end();
            }
            buffer.delete(&mut start, &mut end);
            buffer.insert(&mut start, line);
        }
        buffer.end_user_action();
    }

    pub fn with_view(&self, f: impl FnOnce(&sourceview5::View, &sourceview5::Buffer)) {
        if let Some(doc) = self.current() {
            f(&doc.view, &doc.buffer);
        }
    }
}

/// Comment out lines with `// ` at their common indentation, or uncomment
/// them if every non-blank line is already commented.
pub fn toggle_comment_lines(lines: &[String]) -> Vec<String> {
    let non_blank: Vec<&String> = lines.iter().filter(|l| !l.trim().is_empty()).collect();
    if non_blank.is_empty() {
        return lines.to_vec();
    }
    let all_commented = non_blank.iter().all(|l| l.trim_start().starts_with("//"));
    if all_commented {
        return lines
            .iter()
            .map(|l| {
                let indent = l.len() - l.trim_start().len();
                let rest = &l[indent..];
                match rest.strip_prefix("// ").or_else(|| rest.strip_prefix("//")) {
                    Some(r) => format!("{}{}", &l[..indent], r),
                    None => l.clone(),
                }
            })
            .collect();
    }
    let indent = non_blank.iter().map(|l| l.len() - l.trim_start().len()).min().unwrap_or(0);
    lines
        .iter()
        .map(|l| if l.trim().is_empty() { l.clone() } else { format!("{}// {}", &l[..indent], &l[indent..]) })
        .collect()
}

/// Draw a rounded message banner after the end of each line that has an issue.
fn draw_banners(doc: &Document, area: &gtk::DrawingArea, cr: &gtk::cairo::Context) {
    let dark = adw::StyleManager::default().is_dark();
    // Banners use the UI font, slightly smaller than body text.
    let font = area.pango_context().font_description().map(|mut f| {
        f.set_size(f.size() * 85 / 100);
        f
    });
    for issue in doc.issues.borrow().iter().filter(|i| i.show_banner) {
        let iter = doc.buffer.iter_at_mark(&issue.mark);
        let mut end = iter;
        if !end.ends_line() {
            end.forward_to_line_end();
        }
        let rect = doc.view.iter_location(&end);
        let (y, height) = doc.view.line_yrange(&iter);
        let (wx, wy) = doc.view.buffer_to_window_coords(gtk::TextWindowType::Widget, rect.x() + 28, y);
        let Some(point) = doc.view.compute_point(area, &gtk::graphene::Point::new(wx as f32, wy as f32)) else { continue };
        let (x, y) = (point.x() as f64, point.y() as f64);
        if y + (height as f64) < 0.0 || y > (area.height() as f64) {
            continue;
        }

        let mut text: String = issue.message.chars().take(120).collect();
        if issue.message.chars().count() > 120 {
            text.push('…');
        }
        let layout = area.create_pango_layout(Some(&text));
        layout.set_font_description(font.as_ref());
        let (_, logical) = layout.pixel_extents();
        let (w, h) = (logical.width() as f64 + 12.0, (height as f64 - 2.0).max(logical.height() as f64));
        let (r, g, b) = if issue.severity == Severity::Error { (1.0, 0.23, 0.19) } else { (1.0, 0.75, 0.0) };
        let radius = 4.0;
        let top = y + 1.0;
        cr.new_sub_path();
        cr.arc(x + w - radius, top + radius, radius, -std::f64::consts::FRAC_PI_2, 0.0);
        cr.arc(x + w - radius, top + h - radius, radius, 0.0, std::f64::consts::FRAC_PI_2);
        cr.arc(x + radius, top + h - radius, radius, std::f64::consts::FRAC_PI_2, std::f64::consts::PI);
        cr.arc(x + radius, top + radius, radius, std::f64::consts::PI, 1.5 * std::f64::consts::PI);
        cr.close_path();
        cr.set_source_rgba(r, g, b, if dark { 0.30 } else { 0.20 });
        let _ = cr.fill();
        let fg = if dark { 0.92 } else { 0.12 };
        cr.set_source_rgb(fg, fg, fg);
        cr.move_to(x + 6.0, top + (h - logical.height() as f64) / 2.0);
        pangocairo::functions::show_layout(cr, &layout);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn outlines_swift_files() {
        let src = "import Foundation\n\n// MARK: - Model\nstruct Point {\n    var x = 0\n    mutating func move() {}\n}\n/* func hidden() */\n@MainActor public final class Store {\n    init() {}\n}\nextension Point: Equatable {}\n";
        let syms = symbols(src);
        let names: Vec<_> = syms.iter().map(|s| (s.line, s.kind.as_str(), s.name.as_str())).collect();
        assert_eq!(
            names,
            vec![
                (3, "mark", "Model"),
                (4, "struct", "Point"),
                (6, "func", "move"),
                (9, "class", "Store"),
                (10, "init", "init"),
                (12, "extension", "Point"),
            ]
        );
    }

    #[test]
    fn toggles_comments() {
        let lines = vec!["    let a = 1".to_string(), "".to_string(), "        let b = 2".to_string()];
        let commented = toggle_comment_lines(&lines);
        assert_eq!(commented, vec!["    // let a = 1", "", "    //     let b = 2"]);
        assert_eq!(toggle_comment_lines(&commented), lines);
    }
}
