//! The new project assistant: choose a template, set options, pick a folder.

use std::cell::Cell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::gio;

use crate::templates::{Template, TemplateOptions, create_project};

fn footer(buttons: &[&gtk::Button]) -> gtk::Box {
    let bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    bar.set_margin_top(12);
    bar.set_margin_bottom(12);
    bar.set_margin_start(16);
    bar.set_margin_end(16);
    let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    spacer.set_hexpand(true);
    bar.append(&spacer);
    for b in buttons {
        bar.append(*b);
    }
    bar
}

fn heading(text: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class("title-4");
    l.set_xalign(0.0);
    l.set_margin_top(16);
    l.set_margin_start(20);
    l.set_margin_bottom(4);
    l
}

pub fn present(app: &adw::Application, parent: Option<&gtk::Window>) {
    let chosen = Rc::new(Cell::new(Template::App));
    let nav = adw::NavigationView::new();

    // ---- Page 1: template ----
    let tiles = gtk::FlowBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .homogeneous(true)
        .max_children_per_line(5)
        .column_spacing(8)
        .row_spacing(8)
        .margin_start(20)
        .margin_end(20)
        .margin_top(8)
        .build();
    let description = gtk::Label::new(Some(Template::App.subtitle()));
    description.add_css_class("dim-label");
    description.set_xalign(0.0);
    description.set_margin_start(20);
    description.set_margin_top(8);
    description.set_wrap(true);
    let mut first: Option<gtk::ToggleButton> = None;
    for t in Template::ALL {
        let content = gtk::Box::new(gtk::Orientation::Vertical, 8);
        let icon = gtk::Image::from_icon_name(if t == Template::App { crate::APP_ID } else { t.icon_name() });
        icon.set_pixel_size(48);
        content.append(&icon);
        content.append(&gtk::Label::new(Some(t.title())));
        let tile = gtk::ToggleButton::builder().child(&content).build();
        tile.add_css_class("flat");
        tile.add_css_class("template-tile");
        match &first {
            Some(f) => tile.set_group(Some(f)),
            None => {
                tile.set_active(true);
                first = Some(tile.clone());
            }
        }
        let chosen = chosen.clone();
        let description = description.clone();
        tile.connect_toggled(move |b| {
            if b.is_active() {
                chosen.set(t);
                description.set_text(t.subtitle());
            }
        });
        tiles.insert(&tile, -1);
    }
    let platform = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    platform.add_css_class("linked");
    platform.add_css_class("platform-tabs");
    platform.set_halign(gtk::Align::Center);
    let linux = gtk::ToggleButton::builder().label("Linux").active(true).build();
    platform.append(&linux);

    let cancel1 = gtk::Button::with_label("Cancel");
    let next1 = gtk::Button::with_label("Next");
    next1.add_css_class("suggested-action");
    let page1_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    page1_box.append(&heading("Choose a template for your new project:"));
    page1_box.append(&platform);
    let app_section = gtk::Label::new(Some("Application"));
    app_section.add_css_class("heading");
    app_section.set_xalign(0.0);
    app_section.set_margin_start(20);
    app_section.set_margin_top(12);
    page1_box.append(&app_section);
    page1_box.append(&tiles);
    page1_box.append(&description);
    let spacer = gtk::Box::new(gtk::Orientation::Vertical, 0);
    spacer.set_vexpand(true);
    page1_box.append(&spacer);
    page1_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
    page1_box.append(&footer(&[&cancel1, &next1]));
    let page1_view = adw::ToolbarView::new();
    page1_view.add_top_bar(&adw::HeaderBar::new());
    page1_view.set_content(Some(&page1_box));
    let page1 = adw::NavigationPage::new(&page1_view, "New Project");
    nav.add(&page1);

    // ---- Page 2: options ----
    let settings = crate::settings::get();
    let name = adw::EntryRow::builder().title("Product Name").build();
    let org = adw::EntryRow::builder().title("Organization Name").text(&settings.organization_name).build();
    let org_id = adw::EntryRow::builder().title("Organization Identifier").text(&settings.organization_identifier).build();
    let bundle = adw::ActionRow::builder().title("Bundle Identifier").subtitle("—").build();
    bundle.add_css_class("property");
    let tests = adw::SwitchRow::builder().title("Include Tests").active(true).build();
    let git = adw::SwitchRow::builder().title("Create Git repository").active(true).build();
    let group = adw::PreferencesGroup::new();
    for row in [name.upcast_ref::<gtk::Widget>(), org.upcast_ref(), org_id.upcast_ref(), bundle.upcast_ref()] {
        group.add(row);
    }
    let group2 = adw::PreferencesGroup::new();
    group2.add(&tests);
    group2.add(&git);
    let form = adw::PreferencesPage::new();
    form.add(&group);
    form.add(&group2);

    let update_bundle = {
        let (name, org_id, bundle) = (name.clone(), org_id.clone(), bundle.clone());
        move || {
            let opts = TemplateOptions {
                product_name: name.text().to_string(),
                organization_name: String::new(),
                organization_identifier: org_id.text().to_string(),
                include_tests: false,
                create_git_repository: false,
            };
            bundle.set_subtitle(&if name.text().is_empty() { "—".into() } else { opts.bundle_identifier() });
        }
    };
    let update_bundle = Rc::new(update_bundle);
    {
        let u = update_bundle.clone();
        name.connect_changed(move |_| u());
        let u = update_bundle.clone();
        org_id.connect_changed(move |_| u());
    }

    let cancel2 = gtk::Button::with_label("Cancel");
    let previous = gtk::Button::with_label("Previous");
    let next2 = gtk::Button::with_label("Next");
    next2.add_css_class("suggested-action");
    next2.set_sensitive(false);
    {
        let next2 = next2.clone();
        name.connect_changed(move |e| next2.set_sensitive(!e.text().trim().is_empty()));
    }
    let page2_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    page2_box.append(&heading("Choose options for your new project:"));
    form.set_vexpand(true);
    page2_box.append(&form);
    page2_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
    page2_box.append(&footer(&[&cancel2, &previous, &next2]));
    let page2_view = adw::ToolbarView::new();
    page2_view.add_top_bar(&adw::HeaderBar::new());
    page2_view.set_content(Some(&page2_box));
    let page2 = adw::NavigationPage::builder().child(&page2_view).title("Options").tag("options").build();
    nav.add(&page2);

    let dialog = adw::Dialog::builder().title("New Project").content_width(720).content_height(520).child(&nav).build();

    {
        let d = dialog.clone();
        cancel1.connect_clicked(move |_| {
            d.close();
        });
        let d = dialog.clone();
        cancel2.connect_clicked(move |_| {
            d.close();
        });
        let n = nav.clone();
        let name = name.clone();
        next1.connect_clicked(move |_| {
            n.push_by_tag("options");
            name.grab_focus();
        });
        let n = nav.clone();
        previous.connect_clicked(move |_| {
            n.pop();
        });
    }

    let app = app.clone();
    let d = dialog.clone();
    next2.connect_clicked(move |button| {
        let opts = TemplateOptions {
            product_name: name.text().trim().to_string(),
            organization_name: org.text().trim().to_string(),
            organization_identifier: org_id.text().trim().to_string(),
            include_tests: tests.is_active(),
            create_git_repository: git.is_active(),
        };
        crate::settings::update(|s| {
            s.organization_name = opts.organization_name.clone();
            s.organization_identifier = opts.organization_identifier.clone();
        });
        let template = chosen.get();
        let folder = gtk::FileDialog::builder().title("Choose a Location for the Project").modal(true).build();
        let window = button.root().and_downcast::<gtk::Window>();
        let app = app.clone();
        let d = d.clone();
        folder.select_folder(window.as_ref(), gio::Cancellable::NONE, move |result| {
            let Ok(Some(dir)) = result.map(|f| f.path()) else { return };
            match create_project(&dir, template, &opts) {
                Ok(root) => {
                    d.close();
                    crate::workspace::open(&app, &root);
                }
                Err(e) => {
                    let alert = adw::AlertDialog::new(Some("Couldn't Create the Project"), Some(&e.to_string()));
                    alert.add_response("ok", "OK");
                    alert.present(Some(&d));
                }
            }
        });
    });

    match parent {
        Some(p) => dialog.present(Some(p)),
        // Without a parent, libadwaita shows the dialog in a window of its own.
        None => dialog.present(None::<&gtk::Widget>),
    }
}
