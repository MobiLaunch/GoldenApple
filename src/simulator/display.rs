//! The Simulator's virtual screen: a private, headless X server (Xvfb) that
//! the simulated app draws into. A capture thread streams its pixels back
//! to the device window, and touches and keys are injected with XTEST.
//!
//! There is no window manager on this display. LCode acts as a minimal one
//! instead: every top-level window is pinned to the origin and resized to
//! the device's app area, the way a phone OS shows apps full screen.

use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{self, ConfigureWindowAux, ConnectionExt as _, ImageFormat, MapState};
use x11rb::protocol::xtest::ConnectionExt as _;
use x11rb::rust_connection::RustConnection;

pub struct Frame {
    /// Pixels in BGRX order (cairo's RGB24 layout on little-endian machines).
    pub data: Vec<u8>,
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    /// Whether any app window is mapped. If not, the Simulator shows the home screen.
    pub has_window: bool,
    /// Average color of the frame's top and bottom rows, used to tint the status bar.
    pub top_color: [u8; 3],
    pub bottom_color: [u8; 3],
}

pub struct VirtualDisplay {
    pub number: u32,
    server: Child,
    input: RustConnection,
    root: xproto::Window,
    region: Arc<Mutex<(u16, u16)>>,
    stop: Arc<AtomicBool>,
}

const FRAME_INTERVAL: Duration = Duration::from_millis(33);

impl VirtualDisplay {
    /// Start Xvfb with a `side`×`side` screen and begin streaming the
    /// `app_size` region into `frames`. Blocks until the server accepts
    /// connections, so call it off the main thread.
    pub fn start(
        side: u16,
        app_size: (u16, u16),
        frames: async_channel::Sender<Frame>,
    ) -> Result<Self, String> {
        let xvfb = glib_find("Xvfb").ok_or_else(|| {
            "Xvfb was not found. Install it with: sudo pacman -S xorg-server-xvfb".to_string()
        })?;
        let number = free_display_number().ok_or("No free X display number is available.")?;
        let name = format!(":{number}");
        let mut server = Command::new(xvfb)
            .arg(&name)
            .args(["-screen", "0", &format!("{side}x{side}x24")])
            .args(["-nolisten", "tcp", "-dpi", "96", "-br", "-noreset"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("Could not start Xvfb: {e}"))?;

        let deadline = Instant::now() + Duration::from_secs(10);
        let (input, screen) = loop {
            if let Ok(Some(status)) = server.try_wait() {
                return Err(format!("Xvfb exited during startup ({status})."));
            }
            match x11rb::connect(Some(&name)) {
                Ok(c) => break c,
                Err(_) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(50)),
                Err(e) => {
                    let _ = server.kill();
                    return Err(format!("Could not connect to the simulator display: {e}"));
                }
            }
        };
        let root = input.setup().roots[screen].root;
        // Keyboard focus follows the pointer, since there is no window manager to assign it.
        let _ = input.set_input_focus(xproto::InputFocus::POINTER_ROOT, 1u32, x11rb::CURRENT_TIME);
        let _ = input.flush();

        let region = Arc::new(Mutex::new(app_size));
        let stop = Arc::new(AtomicBool::new(false));
        {
            let (region, stop, name) = (region.clone(), stop.clone(), name.clone());
            std::thread::Builder::new()
                .name("simulator-capture".into())
                .spawn(move || {
                    if let Ok((conn, screen)) = x11rb::connect(Some(&name)) {
                        let root = conn.setup().roots[screen].root;
                        capture_loop(&conn, root, &region, &stop, &frames);
                    }
                })
                .map_err(|e| e.to_string())?;
        }

        Ok(VirtualDisplay { number, server, input, root, region, stop })
    }

    pub fn display_name(&self) -> String {
        format!(":{}", self.number)
    }

    /// Change the app area, e.g. after rotating the device.
    pub fn set_app_size(&self, size: (u16, u16)) {
        *self.region.lock().unwrap() = size;
    }

    fn fake(&self, kind: u8, detail: u8, x: i16, y: i16) {
        let _ = self.input.xtest_fake_input(kind, detail, x11rb::CURRENT_TIME, self.root, x, y, 0);
        let _ = self.input.flush();
    }

    pub fn pointer_motion(&self, x: f64, y: f64) {
        self.fake(xproto::MOTION_NOTIFY_EVENT, 0, x.round() as i16, y.round() as i16);
    }

    pub fn button(&self, button: u8, pressed: bool) {
        let kind = if pressed { xproto::BUTTON_PRESS_EVENT } else { xproto::BUTTON_RELEASE_EVENT };
        self.fake(kind, button, 0, 0);
    }

    /// Inject a key by X keycode. Host keycodes (evdev + 8) match Xvfb's default keymap.
    pub fn key(&self, keycode: u32, pressed: bool) {
        if !(8..=255).contains(&keycode) {
            return;
        }
        let kind = if pressed { xproto::KEY_PRESS_EVENT } else { xproto::KEY_RELEASE_EVENT };
        self.fake(kind, keycode as u8, 0, 0);
    }
}

impl Drop for VirtualDisplay {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = self.server.kill();
        let _ = self.server.wait();
    }
}

fn glib_find(program: &str) -> Option<std::path::PathBuf> {
    gtk::glib::find_program_in_path(program)
}

fn free_display_number() -> Option<u32> {
    (90..400).find(|n| {
        !Path::new(&format!("/tmp/.X11-unix/X{n}")).exists() && !Path::new(&format!("/tmp/.X{n}-lock")).exists()
    })
}

fn capture_loop(
    conn: &RustConnection,
    root: xproto::Window,
    region: &Mutex<(u16, u16)>,
    stop: &AtomicBool,
    frames: &async_channel::Sender<Frame>,
) {
    let mut last: Vec<u8> = Vec::new();
    let mut last_has_window = false;
    let mut tick: u32 = 0;
    let mut has_window = false;
    while !stop.load(Ordering::SeqCst) && !frames.is_closed() {
        let started = Instant::now();
        let (w, h) = *region.lock().unwrap();
        if tick.is_multiple_of(5) {
            match manage_windows(conn, root, w, h) {
                Ok(found) => has_window = found,
                Err(_) => break, // server went away
            }
        }
        tick = tick.wrapping_add(1);

        let image = match conn.get_image(ImageFormat::Z_PIXMAP, root, 0, 0, w, h, !0).map(|c| c.reply()) {
            Ok(Ok(img)) => img,
            _ => break,
        };
        let stride = w as i32 * 4;
        if image.data.len() >= (stride * h as i32) as usize
            && (image.data != last || has_window != last_has_window)
        {
            let frame = Frame {
                top_color: average_row(&image.data, stride as usize, 0, w as usize),
                bottom_color: average_row(&image.data, stride as usize, h.saturating_sub(1) as usize, w as usize),
                data: image.data.clone(),
                width: w as i32,
                height: h as i32,
                stride,
                has_window,
            };
            // Drop frames rather than queueing them if the UI falls behind.
            if frames.is_empty() {
                let _ = frames.try_send(frame);
                last = image.data;
                last_has_window = has_window;
            }
        }
        if let Some(rest) = FRAME_INTERVAL.checked_sub(started.elapsed()) {
            std::thread::sleep(rest);
        }
    }
}

/// Pin every mapped top-level window to the app area. Returns whether any exist.
fn manage_windows(conn: &RustConnection, root: xproto::Window, w: u16, h: u16) -> Result<bool, ()> {
    let tree = conn.query_tree(root).map_err(|_| ())?.reply().map_err(|_| ())?;
    let mut found = false;
    for child in tree.children {
        let Ok(Ok(attrs)) = conn.get_window_attributes(child).map(|c| c.reply()) else { continue };
        if attrs.override_redirect || attrs.map_state != MapState::VIEWABLE {
            continue;
        }
        found = true;
        let Ok(Ok(geo)) = conn.get_geometry(child).map(|c| c.reply()) else { continue };
        if geo.x != 0 || geo.y != 0 || geo.width != w || geo.height != h || geo.border_width != 0 {
            let aux = ConfigureWindowAux::new().x(0).y(0).width(w as u32).height(h as u32).border_width(0);
            let _ = conn.configure_window(child, &aux);
        }
    }
    let _ = conn.flush();
    Ok(found)
}

fn average_row(data: &[u8], stride: usize, row: usize, width: usize) -> [u8; 3] {
    let start = row * stride;
    let Some(slice) = data.get(start..start + width * 4) else { return [0, 0, 0] };
    let (mut r, mut g, mut b, mut n) = (0u64, 0u64, 0u64, 0u64);
    for px in slice.chunks_exact(4).step_by(4) {
        b += px[0] as u64;
        g += px[1] as u64;
        r += px[2] as u64;
        n += 1;
    }
    if n == 0 {
        return [0, 0, 0];
    }
    [(r / n) as u8, (g / n) as u8, (b / n) as u8]
}
