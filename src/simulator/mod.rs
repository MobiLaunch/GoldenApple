//! The LCode Simulator: a device-shaped window that runs compiled apps on a
//! private virtual display and mirrors them inside the device frame.

pub mod chrome;
pub mod device;
pub mod display;

use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::process::Command;
use std::rc::{Rc, Weak};

use adw::prelude::*;
use gtk::{cairo, gdk, gio, glib};

use crate::process::{ProcEvent, RunningProcess};
use chrome::{CapturedFrame, ScreenContent};
pub use device::{DEVICES, Device, Orientation};
use display::{Frame, VirtualDisplay};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Power {
    Off,
    Booting,
    On,
}

struct InstalledApp {
    name: String,
    exe: PathBuf,
    cwd: PathBuf,
}

type EventSink = Rc<dyn Fn(ProcEvent)>;
type SimAction = Box<dyn Fn(&Rc<Simulator>)>;

struct PendingLaunch {
    name: String,
    on_event: EventSink,
}

struct State {
    device: &'static Device,
    orientation: Orientation,
    power: Power,
    display: Option<VirtualDisplay>,
    /// Incremented each boot so frames from an old display are ignored.
    generation: u64,
    frame: Option<CapturedFrame>,
    showing_home: bool,
    app: Option<Rc<RunningProcess>>,
    running_name: Option<String>,
    launch_id: u64,
    installed: Vec<InstalledApp>,
    pending: Option<PendingLaunch>,
    layout: Option<chrome::Layout>,
    pressed_in_app: bool,
}

pub struct Simulator {
    window: adw::ApplicationWindow,
    title: adw::WindowTitle,
    area: gtk::DrawingArea,
    toast: adw::ToastOverlay,
    state: RefCell<State>,
    pointer: Cell<(f64, f64)>,
}

thread_local! {
    static SHARED: RefCell<Option<Rc<Simulator>>> = const { RefCell::new(None) };
}

/// The application-wide Simulator instance, created on first use.
pub fn shared(app: &adw::Application) -> Rc<Simulator> {
    SHARED.with(|s| {
        if let Some(sim) = s.borrow().as_ref() {
            return sim.clone();
        }
        let sim = Simulator::new(app);
        *s.borrow_mut() = Some(sim.clone());
        sim
    })
}

/// The Simulator if it has been opened, without creating it.
pub fn existing() -> Option<Rc<Simulator>> {
    SHARED.with(|s| s.borrow().clone())
}

impl Simulator {
    fn new(app: &adw::Application) -> Rc<Self> {
        let device = device::by_id(&crate::settings::get().default_simulator).unwrap_or(device::default_device());
        let title = adw::WindowTitle::new(device.name, &format!("{} {}", device::OS_NAME, device::OS_VERSION));
        let header = adw::HeaderBar::new();
        header.set_title_widget(Some(&title));

        let home = icon_button("go-home-symbolic", "Home (Shift+Ctrl+H)", "sim.home");
        let shot = icon_button("camera-photo-symbolic", "Save Screen (Ctrl+S)", "sim.screenshot");
        let rotate_left = icon_button("object-rotate-left-symbolic", "Rotate Left (Ctrl+Left)", "sim.rotate-left");
        let rotate_right = icon_button("object-rotate-right-symbolic", "Rotate Right (Ctrl+Right)", "sim.rotate-right");
        header.pack_start(&home);
        header.pack_end(&rotate_right);
        header.pack_end(&rotate_left);
        header.pack_end(&shot);

        let menu = gio::Menu::new();
        let devices = gio::Menu::new();
        for d in DEVICES {
            devices.append(Some(d.name), Some(&format!("sim.device::{}", d.id)));
        }
        menu.append_section(Some("Device"), &devices);
        let actions = gio::Menu::new();
        actions.append(Some("Erase All Content and Settings…"), Some("sim.erase"));
        actions.append(Some("Shut Down"), Some("sim.shutdown"));
        menu.append_section(None, &actions);
        let menu_button = gtk::MenuButton::builder()
            .icon_name("phone-symbolic")
            .tooltip_text("Choose Device")
            .menu_model(&menu)
            .build();
        header.pack_start(&menu_button);

        let area = gtk::DrawingArea::new();
        area.set_hexpand(true);
        area.set_vexpand(true);
        area.set_focusable(true);
        area.add_css_class("simulator-stage");

        let toast = adw::ToastOverlay::new();
        toast.set_child(Some(&area));
        let toolbar = adw::ToolbarView::new();
        toolbar.add_top_bar(&header);
        toolbar.set_content(Some(&toast));

        let window = adw::ApplicationWindow::builder()
            .application(app)
            .title("Simulator")
            .content(&toolbar)
            .hide_on_close(true)
            .build();

        let sim = Rc::new(Simulator {
            window,
            title,
            area,
            toast,
            state: RefCell::new(State {
                device,
                orientation: Orientation::Portrait,
                power: Power::Off,
                display: None,
                generation: 0,
                frame: None,
                showing_home: true,
                app: None,
                running_name: None,
                launch_id: 0,
                installed: Vec::new(),
                pending: None,
                layout: None,
                pressed_in_app: false,
            }),
            pointer: Cell::new((0.0, 0.0)),
        });
        sim.resize_for_device();
        sim.setup_drawing();
        sim.setup_input();
        sim.setup_actions(app);
        sim
    }

    pub fn present(self: &Rc<Self>) {
        self.window.present();
        self.boot();
    }

    fn resize_for_device(&self) {
        let st = self.state.borrow();
        let (vw, vh) = st.device.view_size(st.orientation);
        // A comfortable size that fits on a typical laptop screen.
        let scale = (760.0 / vh).min(1100.0 / vw).min(1.0);
        let width = ((vw * scale) as i32 + 60).max(520);
        self.window.set_default_size(width, (vh * scale) as i32 + 110);
        self.title.set_title(st.device.name);
    }

    // ---- Lifecycle ---------------------------------------------------------

    fn boot(self: &Rc<Self>) {
        let (side, app_size, generation) = {
            let mut st = self.state.borrow_mut();
            if st.power != Power::Off {
                return;
            }
            st.power = Power::Booting;
            st.generation += 1;
            (st.device.display_side(), st.device.app_size(st.orientation), st.generation)
        };
        self.area.queue_draw();

        let (tx, rx) = async_channel::bounded::<Frame>(2);
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let started = std::time::Instant::now();
            let result = gio::spawn_blocking(move || VirtualDisplay::start(side, app_size, tx)).await;
            // Let the boot screen show briefly, as a real device would.
            if let Some(rest) = std::time::Duration::from_millis(700).checked_sub(started.elapsed()) {
                glib::timeout_future(rest).await;
            }
            let Some(sim) = weak.upgrade() else { return };
            if sim.state.borrow().generation != generation {
                return; // shut down or switched device while booting
            }
            match result {
                Ok(Ok(display)) => {
                    {
                        let mut st = sim.state.borrow_mut();
                        st.display = Some(display);
                        st.power = Power::On;
                    }
                    let pending = sim.state.borrow_mut().pending.take();
                    if let Some(p) = pending {
                        sim.spawn_installed(&p.name, p.on_event);
                    }
                }
                Ok(Err(message)) => sim.fail_boot(&message),
                Err(_) => sim.fail_boot("The simulator display crashed while booting."),
            }
            sim.area.queue_draw();
        });

        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            while let Ok(frame) = rx.recv().await {
                let Some(sim) = weak.upgrade() else { return };
                if sim.state.borrow().generation != generation {
                    return;
                }
                if let Ok(surface) = cairo::ImageSurface::create_for_data(
                    frame.data,
                    cairo::Format::Rgb24,
                    frame.width,
                    frame.height,
                    frame.stride,
                ) {
                    sim.state.borrow_mut().frame = Some(CapturedFrame {
                        surface,
                        has_window: frame.has_window,
                        top_color: frame.top_color,
                        bottom_color: frame.bottom_color,
                    });
                    sim.area.queue_draw();
                }
            }
        });
    }

    fn fail_boot(&self, message: &str) {
        let pending = {
            let mut st = self.state.borrow_mut();
            st.power = Power::Off;
            st.pending.take()
        };
        if let Some(p) = pending {
            (p.on_event)(ProcEvent::Stderr(format!("Simulator: {message}\n")));
            (p.on_event)(ProcEvent::Exit(None));
        }
        self.toast(message);
    }

    pub fn shutdown(&self) {
        self.stop_app();
        let mut st = self.state.borrow_mut();
        st.generation += 1;
        st.display = None;
        st.frame = None;
        st.power = Power::Off;
        st.showing_home = true;
        drop(st);
        self.area.queue_draw();
    }

    pub fn set_device(self: &Rc<Self>, id: &str) {
        let Some(device) = device::by_id(id) else { return };
        if self.state.borrow().device.id == device.id {
            return;
        }
        self.shutdown();
        {
            let mut st = self.state.borrow_mut();
            st.device = device;
            st.orientation = Orientation::Portrait;
        }
        crate::settings::update(|s| s.default_simulator = id.to_string());
        self.resize_for_device();
        if self.window.is_visible() {
            self.boot();
        }
    }

    fn rotate(&self, left: bool) {
        let mut st = self.state.borrow_mut();
        st.orientation = if left { st.orientation.rotated_left() } else { st.orientation.rotated_right() };
        let size = st.device.app_size(st.orientation);
        if let Some(d) = &st.display {
            d.set_app_size(size);
        }
        // Old frames have the wrong size until the app re-renders.
        st.frame = None;
        drop(st);
        self.resize_for_device();
        self.area.queue_draw();
    }

    // ---- Apps ----------------------------------------------------------------

    /// Install `exe` under `name` and launch it, streaming its output to `on_event`.
    pub fn run_app(
        self: &Rc<Self>,
        name: &str,
        exe: PathBuf,
        cwd: PathBuf,
        device_id: &str,
        on_event: impl Fn(ProcEvent) + 'static,
    ) {
        self.set_device(device_id);
        self.stop_app();
        {
            let mut st = self.state.borrow_mut();
            st.installed.retain(|a| a.name != name);
            st.installed.push(InstalledApp { name: name.to_string(), exe, cwd });
        }
        self.window.present();
        let on_event: EventSink = Rc::new(on_event);
        let power = self.state.borrow().power;
        match power {
            Power::On => self.spawn_installed(name, on_event),
            _ => {
                self.state.borrow_mut().pending = Some(PendingLaunch { name: name.to_string(), on_event });
                self.boot();
            }
        }
    }

    fn spawn_installed(self: &Rc<Self>, name: &str, on_event: EventSink) {
        let (cmd, launch_id, device) = {
            let mut st = self.state.borrow_mut();
            let Some(app) = st.installed.iter().find(|a| a.name == name) else { return };
            let Some(display) = st.display.as_ref() else { return };
            let mut cmd = Command::new(&app.exe);
            cmd.current_dir(&app.cwd)
                .env("DISPLAY", display.display_name())
                .env_remove("WAYLAND_DISPLAY")
                .env("GDK_BACKEND", "x11")
                .env("GDK_SCALE", "1")
                .env("GSK_RENDERER", "cairo")
                // Ask for server-side decorations; with no window manager there are none,
                // so plain windows fill the screen like a phone app.
                .env("GTK_CSD", "0")
                .env("GTK_A11Y", "none")
                .env("NO_AT_BRIDGE", "1")
                .env("LIBGL_ALWAYS_SOFTWARE", "1")
                .env("QT_QPA_PLATFORM", "xcb")
                .env("SDL_VIDEODRIVER", "x11")
                .env("LCODE_SIMULATOR", "1")
                .env("LCODE_DEVICE_ID", st.device.id)
                .env("LCODE_DEVICE_NAME", st.device.name);
            st.launch_id += 1;
            (cmd, st.launch_id, st.device)
        };

        let weak: Weak<Simulator> = Rc::downgrade(self);
        let sink = on_event.clone();
        let result = RunningProcess::spawn(cmd, move |ev| {
            if let ProcEvent::Exit(_) = ev
                && let Some(sim) = weak.upgrade() {
                    let mut st = sim.state.borrow_mut();
                    if st.launch_id == launch_id {
                        st.app = None;
                        st.running_name = None;
                        st.showing_home = true;
                        drop(st);
                        sim.area.queue_draw();
                    }
                }
            sink(ev);
        });
        match result {
            Ok(proc) => {
                let mut st = self.state.borrow_mut();
                st.app = Some(proc);
                st.running_name = Some(name.to_string());
                st.showing_home = false;
                st.frame = None;
                drop(st);
                on_event(ProcEvent::Stdout(format!("Launched {name} on {}.\n", device.name)));
            }
            Err(e) => {
                on_event(ProcEvent::Stderr(format!("Failed to launch {name}: {e}\n")));
                on_event(ProcEvent::Exit(None));
            }
        }
        self.area.queue_draw();
    }

    pub fn stop_app(&self) {
        let app = {
            let mut st = self.state.borrow_mut();
            st.running_name = None;
            st.showing_home = true;
            st.app.take()
        };
        if let Some(app) = app {
            app.terminate();
        }
        self.area.queue_draw();
    }

    fn go_home(&self) {
        self.state.borrow_mut().showing_home = true;
        self.area.queue_draw();
    }

    fn toast(&self, message: &str) {
        self.toast.add_toast(adw::Toast::new(message));
    }

    // ---- Drawing ---------------------------------------------------------------

    fn setup_drawing(self: &Rc<Self>) {
        let weak = Rc::downgrade(self);
        self.area.set_draw_func(move |area, cr, w, h| {
            let Some(sim) = weak.upgrade() else { return };
            let dark = adw::StyleManager::default().is_dark();
            let mut st = sim.state.borrow_mut();
            let layout = chrome::layout(st.device, st.orientation, w as f64, h as f64);
            st.layout = Some(layout);
            let names: Vec<String> = st.installed.iter().map(|a| a.name.clone()).collect();
            let content = match st.power {
                Power::Off => ScreenContent::Off,
                Power::Booting => ScreenContent::Booting,
                Power::On => match (&st.frame, st.showing_home) {
                    (Some(frame), false) => ScreenContent::App(frame),
                    _ => ScreenContent::Home { apps: &names, running: st.running_name.as_deref() },
                },
            };
            chrome::draw_device(cr, st.device, st.orientation, &layout, &content, dark);
            let _ = area;
        });
        // Keep the status bar clock current.
        let weak = Rc::downgrade(self);
        glib::timeout_add_seconds_local(15, move || match weak.upgrade() {
            Some(sim) => {
                sim.area.queue_draw();
                glib::ControlFlow::Continue
            }
            None => glib::ControlFlow::Break,
        });
    }

    // ---- Input -------------------------------------------------------------------

    fn app_point(&self, x: f64, y: f64) -> Option<(f64, f64)> {
        let st = self.state.borrow();
        let layout = st.layout?;
        chrome::widget_to_app(&layout, st.device, st.orientation, x, y)
    }

    fn app_visible(&self) -> bool {
        let st = self.state.borrow();
        st.power == Power::On && !st.showing_home && st.app.is_some()
    }

    fn with_display(&self, f: impl FnOnce(&VirtualDisplay)) {
        if let Some(d) = self.state.borrow().display.as_ref() {
            f(d);
        }
    }

    fn setup_input(self: &Rc<Self>) {
        let drag = gtk::GestureDrag::new();
        drag.set_button(0);
        let weak = Rc::downgrade(self);
        drag.connect_drag_begin(move |g, x, y| {
            let Some(sim) = weak.upgrade() else { return };
            sim.area.grab_focus();
            sim.pointer.set((x, y));
            let button = g.current_button() as u8;
            if sim.home_control_hit(x, y) {
                sim.go_home();
                return;
            }
            if sim.app_visible() {
                if let Some((ax, ay)) = sim.app_point(x, y) {
                    sim.with_display(|d| {
                        d.pointer_motion(ax, ay);
                        d.button(button, true);
                    });
                    sim.state.borrow_mut().pressed_in_app = true;
                }
            } else if button == 1 {
                sim.tap_home_screen(x, y);
            }
        });
        let weak = Rc::downgrade(self);
        drag.connect_drag_update(move |g, dx, dy| {
            let Some(sim) = weak.upgrade() else { return };
            if !sim.state.borrow().pressed_in_app {
                return;
            }
            if let Some((sx, sy)) = g.start_point()
                && let Some((ax, ay)) = sim.app_point_clamped(sx + dx, sy + dy) {
                    sim.with_display(|d| d.pointer_motion(ax, ay));
                }
        });
        let weak = Rc::downgrade(self);
        drag.connect_drag_end(move |g, _, _| {
            let Some(sim) = weak.upgrade() else { return };
            if std::mem::take(&mut sim.state.borrow_mut().pressed_in_app) {
                let button = g.current_button() as u8;
                sim.with_display(|d| d.button(button, false));
            }
        });
        self.area.add_controller(drag);

        let motion = gtk::EventControllerMotion::new();
        let weak = Rc::downgrade(self);
        motion.connect_motion(move |_, x, y| {
            let Some(sim) = weak.upgrade() else { return };
            sim.pointer.set((x, y));
            if sim.app_visible() && !sim.state.borrow().pressed_in_app
                && let Some((ax, ay)) = sim.app_point(x, y) {
                    sim.with_display(|d| d.pointer_motion(ax, ay));
                }
        });
        self.area.add_controller(motion);

        let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::BOTH_AXES);
        let weak = Rc::downgrade(self);
        scroll.connect_scroll(move |_, dx, dy| {
            let Some(sim) = weak.upgrade() else { return glib::Propagation::Proceed };
            if !sim.app_visible() {
                return glib::Propagation::Proceed;
            }
            let (x, y) = sim.pointer.get();
            if let Some((ax, ay)) = sim.app_point(x, y) {
                sim.with_display(|d| {
                    d.pointer_motion(ax, ay);
                    let click = |button: u8, amount: f64| {
                        for _ in 0..(amount.abs().round().max(1.0) as u32).min(10) {
                            d.button(button, true);
                            d.button(button, false);
                        }
                    };
                    if dy.abs() > 0.01 {
                        click(if dy < 0.0 { 4 } else { 5 }, dy);
                    }
                    if dx.abs() > 0.01 {
                        click(if dx < 0.0 { 6 } else { 7 }, dx);
                    }
                });
            }
            glib::Propagation::Stop
        });
        self.area.add_controller(scroll);

        let keys = gtk::EventControllerKey::new();
        let weak = Rc::downgrade(self);
        keys.connect_key_pressed(move |_, _, keycode, state| {
            let Some(sim) = weak.upgrade() else { return glib::Propagation::Proceed };
            // Leave Simulator shortcuts (Ctrl+…) to the window.
            if state.contains(gdk::ModifierType::CONTROL_MASK) || !sim.app_visible() {
                return glib::Propagation::Proceed;
            }
            sim.with_display(|d| d.key(keycode, true));
            glib::Propagation::Stop
        });
        let weak = Rc::downgrade(self);
        keys.connect_key_released(move |_, _, keycode, _| {
            if let Some(sim) = weak.upgrade() {
                sim.with_display(|d| d.key(keycode, false));
            }
        });
        self.area.add_controller(keys);
    }

    fn app_point_clamped(&self, x: f64, y: f64) -> Option<(f64, f64)> {
        let st = self.state.borrow();
        let layout = st.layout?;
        let (sx, sy) = chrome::widget_to_screen(&layout, st.device, st.orientation, x, y);
        let i = st.device.insets(st.orientation);
        let (aw, ah) = st.device.app_size(st.orientation);
        Some(((sx - i.left).clamp(0.0, aw as f64 - 1.0), (sy - i.top).clamp(0.0, ah as f64 - 1.0)))
    }

    fn home_control_hit(&self, x: f64, y: f64) -> bool {
        let st = self.state.borrow();
        let Some(layout) = st.layout else { return false };
        st.power == Power::On && chrome::hits_home_control(&layout, st.device, st.orientation, x, y)
    }

    fn tap_home_screen(self: &Rc<Self>, x: f64, y: f64) {
        let Some((ax, ay)) = self.app_point(x, y) else { return };
        let (name, running) = {
            let st = self.state.borrow();
            if st.power != Power::On {
                return;
            }
            let (aw, _) = st.device.app_size(st.orientation);
            let Some(i) = chrome::home_icon_at(st.device, aw as f64, st.installed.len(), ax, ay) else { return };
            let name = st.installed[i].name.clone();
            let running = st.running_name.as_deref() == Some(name.as_str());
            (name, running)
        };
        if running {
            self.state.borrow_mut().showing_home = false;
            self.area.queue_draw();
        } else {
            self.stop_app();
            let label = name.clone();
            self.spawn_installed(
                &name,
                Rc::new(move |ev| match ev {
                    ProcEvent::Stdout(s) => print!("[{label}] {s}"),
                    ProcEvent::Stderr(s) => eprint!("[{label}] {s}"),
                    ProcEvent::Exit(_) => {}
                }),
            );
        }
    }

    // ---- Actions -------------------------------------------------------------------

    fn setup_actions(self: &Rc<Self>, app: &adw::Application) {
        let group = gio::SimpleActionGroup::new();
        let add = |name: &str, f: SimAction| {
            let action = gio::SimpleAction::new(name, None);
            let weak = Rc::downgrade(self);
            action.connect_activate(move |_, _| {
                if let Some(sim) = weak.upgrade() {
                    f(&sim);
                }
            });
            group.add_action(&action);
        };
        add("home", Box::new(|s| s.go_home()));
        add("rotate-left", Box::new(|s| s.rotate(true)));
        add("rotate-right", Box::new(|s| s.rotate(false)));
        add("screenshot", Box::new(|s| s.save_screenshot()));
        add("shutdown", Box::new(|s| s.shutdown()));
        add(
            "erase",
            Box::new(|s| {
                s.shutdown();
                s.state.borrow_mut().installed.clear();
                s.toast("All content and settings were erased.");
                s.boot();
            }),
        );

        let device_action = gio::SimpleAction::new_stateful(
            "device",
            Some(glib::VariantTy::STRING),
            &self.state.borrow().device.id.to_variant(),
        );
        let weak = Rc::downgrade(self);
        device_action.connect_activate(move |action, param| {
            let (Some(sim), Some(id)) = (weak.upgrade(), param.and_then(|p| p.get::<String>())) else { return };
            action.set_state(&id.to_variant());
            sim.set_device(&id);
        });
        group.add_action(&device_action);
        self.window.insert_action_group("sim", Some(&group));

        let shortcuts = gtk::ShortcutController::new();
        shortcuts.set_scope(gtk::ShortcutScope::Managed);
        for (accel, action) in [
            ("<Shift><Control>h", "sim.home"),
            ("<Control>s", "sim.screenshot"),
            ("<Control>Left", "sim.rotate-left"),
            ("<Control>Right", "sim.rotate-right"),
        ] {
            shortcuts.add_shortcut(gtk::Shortcut::new(
                gtk::ShortcutTrigger::parse_string(accel),
                Some(gtk::NamedAction::new(action)),
            ));
        }
        self.window.add_controller(shortcuts);
        let _ = app;
    }

    fn save_screenshot(&self) {
        let st = self.state.borrow();
        if st.power != Power::On {
            return;
        }
        let (sw, sh) = st.device.screen_size(st.orientation);
        let Ok(surface) = cairo::ImageSurface::create(cairo::Format::ARgb32, sw as i32, sh as i32) else { return };
        let Ok(cr) = cairo::Context::new(&surface) else { return };
        let names: Vec<String> = st.installed.iter().map(|a| a.name.clone()).collect();
        let content = match (&st.frame, st.showing_home) {
            (Some(frame), false) => ScreenContent::App(frame),
            _ => ScreenContent::Home { apps: &names, running: st.running_name.as_deref() },
        };
        chrome::draw_screen(&cr, st.device, st.orientation, &content, 1.0);
        drop(cr);
        let stamp = glib::DateTime::now_local()
            .ok()
            .and_then(|d| d.format("%Y-%m-%d at %H.%M.%S").ok())
            .map(|s| s.to_string())
            .unwrap_or_default();
        let dir = glib::user_special_dir(glib::UserDirectory::Pictures)
            .or_else(|| glib::user_special_dir(glib::UserDirectory::Desktop))
            .unwrap_or_else(glib::home_dir);
        let path = dir.join(format!("Simulator Screenshot - {} - {stamp}.png", st.device.name));
        drop(st);
        let saved = std::fs::File::create(&path)
            .map_err(|e| e.to_string())
            .and_then(|mut f| surface.write_to_png(&mut f).map_err(|e| e.to_string()));
        match saved {
            Ok(()) => self.toast(&format!("Saved {}", path.file_name().unwrap_or_default().to_string_lossy())),
            Err(e) => self.toast(&format!("Could not save screenshot: {e}")),
        }
    }
}

fn icon_button(icon: &str, tooltip: &str, action: &str) -> gtk::Button {
    gtk::Button::builder().icon_name(icon).tooltip_text(tooltip).action_name(action).build()
}
