//! Open Quickly (Shift+Ctrl+O): fuzzy file finder.

use std::path::{Path, PathBuf};
use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;

/// Fuzzy subsequence score: higher is better, `None` if not all characters match.
pub fn score(query: &str, candidate: &str) -> Option<i32> {
    if query.is_empty() {
        return Some(0);
    }
    let q: Vec<char> = query.to_lowercase().chars().filter(|c| !c.is_whitespace()).collect();
    let c: Vec<char> = candidate.to_lowercase().chars().collect();
    let original: Vec<char> = candidate.chars().collect();
    let mut score = 0;
    let mut qi = 0;
    let mut last_match: Option<usize> = None;
    for (i, ch) in c.iter().enumerate() {
        if qi < q.len() && *ch == q[qi] {
            score += 1;
            if last_match == Some(i.wrapping_sub(1)) {
                score += 5; // consecutive
            }
            let boundary = i == 0
                || matches!(original.get(i - 1), Some('/' | '_' | '-' | '.' | ' '))
                || (original[i].is_uppercase() && original.get(i - 1).is_some_and(|p| p.is_lowercase()));
            if boundary {
                score += 8;
            }
            last_match = Some(i);
            qi += 1;
        }
    }
    if qi < q.len() {
        return None;
    }
    // Prefer shorter names.
    Some(score * 10 - c.len() as i32)
}

pub fn present(parent: &impl IsA<gtk::Window>, root: &Path, on_open: impl Fn(PathBuf) + 'static) {
    let files: Rc<Vec<PathBuf>> = Rc::new(crate::project::walk_files(root, 20_000));
    let root = root.to_path_buf();

    let window = gtk::Window::builder()
        .transient_for(parent)
        .modal(true)
        .decorated(false)
        .default_width(640)
        .default_height(420)
        .title("Open Quickly")
        .build();
    window.add_css_class("open-quickly");

    let entry = gtk::SearchEntry::builder().placeholder_text("Open Quickly").build();
    let list = gtk::ListBox::new();
    list.add_css_class("navigation-sidebar");
    let scroller = gtk::ScrolledWindow::builder().child(&list).vexpand(true).build();
    let content = gtk::Box::new(gtk::Orientation::Vertical, 6);
    content.set_margin_top(10);
    content.set_margin_bottom(10);
    content.set_margin_start(10);
    content.set_margin_end(10);
    content.append(&entry);
    content.append(&scroller);
    window.set_child(Some(&content));

    let shown: Rc<std::cell::RefCell<Vec<PathBuf>>> = Rc::default();
    let refresh = {
        let (files, list, shown, root) = (files.clone(), list.clone(), shown.clone(), root.clone());
        move |query: &str| {
            while let Some(c) = list.first_child() {
                list.remove(&c);
            }
            let mut scored: Vec<(i32, &PathBuf)> = files
                .iter()
                .filter_map(|p| {
                    let name = p.file_name()?.to_string_lossy();
                    let rel = p.strip_prefix(&root).unwrap_or(p).to_string_lossy();
                    let s = score(query, &name).map(|s| s + 1000).or_else(|| score(query, &rel))?;
                    Some((s, p))
                })
                .collect();
            scored.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(b.1)));
            scored.truncate(60);
            let mut paths = Vec::new();
            for (_, p) in scored {
                let name = p.file_name().unwrap_or_default().to_string_lossy().into_owned();
                let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                row.add_css_class("file-row");
                let (icon, class) = crate::style::file_icon(&name, false);
                let image = gtk::Image::from_icon_name(icon);
                image.add_css_class(class);
                row.append(&image);
                let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
                text.append(&gtk::Label::builder().label(&name).xalign(0.0).build());
                let rel = p.parent().and_then(|d| d.strip_prefix(&root).ok()).map(|d| d.display().to_string()).unwrap_or_default();
                let sub = gtk::Label::builder().label(&rel).xalign(0.0).build();
                sub.add_css_class("oq-path");
                text.append(&sub);
                row.append(&text);
                list.append(&row);
                paths.push(p.clone());
            }
            if let Some(first) = list.row_at_index(0) {
                list.select_row(Some(&first));
            }
            *shown.borrow_mut() = paths;
        }
    };
    refresh("");

    let on_open = Rc::new(on_open);
    let open_row = {
        let (shown, window, on_open) = (shown.clone(), window.clone(), on_open.clone());
        move |index: i32| {
            let path = shown.borrow().get(index as usize).cloned();
            if let Some(p) = path {
                window.close();
                on_open(p);
            }
        }
    };
    let open_row = Rc::new(open_row);
    {
        let refresh = refresh.clone();
        entry.connect_search_changed(move |e| refresh(&e.text()));
    }
    {
        let (list, open_row) = (list.clone(), open_row.clone());
        entry.connect_activate(move |_| {
            let index = list.selected_row().map(|r| r.index()).unwrap_or(0);
            open_row(index);
        });
    }
    {
        let open_row = open_row.clone();
        list.connect_row_activated(move |_, row| open_row(row.index()));
    }
    {
        let window = window.clone();
        entry.connect_stop_search(move |_| window.close());
    }
    // Arrow keys move the selection while typing.
    let keys = gtk::EventControllerKey::new();
    keys.set_propagation_phase(gtk::PropagationPhase::Capture);
    {
        let list = list.clone();
        keys.connect_key_pressed(move |_, key, _, _| {
            let delta = match key {
                gtk::gdk::Key::Down => 1,
                gtk::gdk::Key::Up => -1,
                _ => return glib::Propagation::Proceed,
            };
            let current = list.selected_row().map(|r| r.index()).unwrap_or(-1);
            if let Some(row) = list.row_at_index((current + delta).max(0)) {
                list.select_row(Some(&row));
            }
            glib::Propagation::Stop
        });
    }
    window.add_controller(keys);
    window.present();
    entry.grab_focus();
}

#[cfg(test)]
mod tests {
    use super::score;

    #[test]
    fn ranks_better_matches_higher() {
        assert!(score("cv", "ContentView.swift").is_some());
        assert!(score("xyz", "ContentView.swift").is_none());
        assert!(score("cont", "ContentView.swift") > score("cont", "AccountNotes.swift"));
        assert!(score("main", "main.swift") > score("main", "Domain/Remaining.swift"));
    }
}
