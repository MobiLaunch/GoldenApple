//! The debug area: console output of builds, tests and running programs,
//! with a line of input forwarded to the running program's stdin.

use std::cell::RefCell;

use adw::prelude::*;
use gtk::glib;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stream {
    Stdout,
    Stderr,
    System,
}

const MAX_LINES: i32 = 20_000;

type InputCallback = Box<dyn Fn(String)>;

pub struct Console {
    pub widget: gtk::Box,
    view: gtk::TextView,
    buffer: gtk::TextBuffer,
    input: gtk::Entry,
    scroller: gtk::ScrolledWindow,
    on_input: RefCell<Option<InputCallback>>,
}

impl Console {
    pub fn new() -> std::rc::Rc<Self> {
        let buffer = gtk::TextBuffer::new(None);
        buffer.create_tag(Some("stderr"), &[("foreground", &"#FF5F57")]);
        buffer.create_tag(Some("system"), &[("foreground", &"#8E8E93"), ("style", &gtk::pango::Style::Italic)]);

        let view = gtk::TextView::builder()
            .buffer(&buffer)
            .editable(false)
            .cursor_visible(false)
            .monospace(true)
            .wrap_mode(gtk::WrapMode::WordChar)
            .build();
        view.add_css_class("console-view");
        let scroller = gtk::ScrolledWindow::builder().child(&view).vexpand(true).build();

        let input = gtk::Entry::builder()
            .placeholder_text("Send input to the running program…")
            .sensitive(false)
            .build();
        input.add_css_class("console-input");
        input.add_css_class("flat");

        let bar = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        bar.add_css_class("debug-bar");
        let hide_button = gtk::Button::builder()
            .icon_name("pan-down-symbolic")
            .tooltip_text("Hide the Debug Area (Shift+Ctrl+Y)")
            .action_name("win.toggle-debug-area")
            .build();
        hide_button.add_css_class("flat");
        bar.append(&hide_button);
        let title = gtk::Label::new(Some("Console"));
        title.add_css_class("dim-label");
        title.add_css_class("caption-heading");
        title.set_hexpand(true);
        title.set_xalign(0.0);
        bar.append(&title);
        let clear = gtk::Button::builder().icon_name("user-trash-symbolic").tooltip_text("Clear Console (Ctrl+K)").build();
        clear.add_css_class("flat");
        bar.append(&clear);

        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        widget.append(&bar);
        widget.append(&scroller);
        widget.append(&input);
        widget.set_size_request(-1, 120);

        let console = std::rc::Rc::new(Console {
            widget,
            view,
            buffer,
            input,
            scroller,
            on_input: RefCell::new(None),
        });

        let weak = std::rc::Rc::downgrade(&console);
        clear.connect_clicked(move |_| {
            if let Some(c) = weak.upgrade() {
                c.clear();
            }
        });
        let weak = std::rc::Rc::downgrade(&console);
        console.input.connect_activate(move |entry| {
            let Some(c) = weak.upgrade() else { return };
            let line = format!("{}\n", entry.text());
            entry.set_text("");
            c.append(&line, Stream::Stdout);
            if let Some(cb) = c.on_input.borrow().as_ref() {
                cb(line);
            }
        });
        console
    }

    pub fn connect_input(&self, f: impl Fn(String) + 'static) {
        *self.on_input.borrow_mut() = Some(Box::new(f));
    }

    pub fn set_input_enabled(&self, enabled: bool) {
        self.input.set_sensitive(enabled);
    }

    pub fn clear(&self) {
        self.buffer.set_text("");
    }

    pub fn append(&self, text: &str, stream: Stream) {
        let text = crate::diagnostics::strip_ansi(text);
        let adj = self.scroller.vadjustment();
        let at_bottom = adj.value() + adj.page_size() >= adj.upper() - 4.0;

        let mut end = self.buffer.end_iter();
        match stream {
            Stream::Stdout => self.buffer.insert(&mut end, &text),
            Stream::Stderr => self.buffer.insert_with_tags_by_name(&mut end, &text, &["stderr"]),
            Stream::System => self.buffer.insert_with_tags_by_name(&mut end, &text, &["system"]),
        }

        let excess = self.buffer.line_count() - MAX_LINES;
        if excess > 0 {
            let mut start = self.buffer.start_iter();
            if let Some(mut cut) = self.buffer.iter_at_line(excess) {
                self.buffer.delete(&mut start, &mut cut);
            }
        }

        if at_bottom {
            let view = self.view.clone();
            let buffer = self.buffer.clone();
            glib::idle_add_local_once(move || {
                let mut end = buffer.end_iter();
                view.scroll_to_iter(&mut end, 0.0, false, 0.0, 1.0);
            });
        }
    }
}
