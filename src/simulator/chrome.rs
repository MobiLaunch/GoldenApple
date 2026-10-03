//! Drawing the simulated device: body, bezels, status bar, home indicator,
//! home screen, and the app's captured frames.

use std::f64::consts::PI;

use gtk::cairo::{self, Context, FontSlant, FontWeight, LinearGradient};

use super::device::{Cutout, Device, Orientation};

pub struct CapturedFrame {
    pub surface: cairo::ImageSurface,
    pub has_window: bool,
    pub top_color: [u8; 3],
    pub bottom_color: [u8; 3],
}

pub enum ScreenContent<'a> {
    Off,
    Booting,
    Home { apps: &'a [String], running: Option<&'a str> },
    App(&'a CapturedFrame),
}

#[derive(Debug, Clone, Copy)]
pub struct Layout {
    pub scale: f64,
    pub cx: f64,
    pub cy: f64,
}

const MARGIN: f64 = 24.0;

pub fn layout(device: &Device, o: Orientation, widget_w: f64, widget_h: f64) -> Layout {
    let (vw, vh) = device.view_size(o);
    let scale = ((widget_w - 2.0 * MARGIN) / vw).min((widget_h - 2.0 * MARGIN) / vh).clamp(0.1, 1.0);
    Layout { scale, cx: widget_w / 2.0, cy: widget_h / 2.0 }
}

/// Map a point in the widget to screen coordinates (points, origin top-left of the screen).
pub fn widget_to_screen(l: &Layout, device: &Device, o: Orientation, x: f64, y: f64) -> (f64, f64) {
    let (sw, sh) = device.screen_size(o);
    ((x - l.cx) / l.scale + sw / 2.0, (y - l.cy) / l.scale + sh / 2.0)
}

/// Map a point in the widget to the app area, if it falls inside it.
pub fn widget_to_app(l: &Layout, device: &Device, o: Orientation, x: f64, y: f64) -> Option<(f64, f64)> {
    let (sx, sy) = widget_to_screen(l, device, o, x, y);
    let i = device.insets(o);
    let (aw, ah) = device.app_size(o);
    let (ax, ay) = (sx - i.left, sy - i.top);
    (ax >= 0.0 && ay >= 0.0 && ax < aw as f64 && ay < ah as f64).then_some((ax, ay))
}

/// Whether a widget point hits the home button or home indicator.
pub fn hits_home_control(l: &Layout, device: &Device, o: Orientation, x: f64, y: f64) -> bool {
    let (sx, sy) = widget_to_screen(l, device, o, x, y);
    let (sw, sh) = device.screen_size(o);
    match device.cutout {
        Cutout::HomeButton => {
            // The home button sits below the screen in portrait, beside it in landscape.
            let r = device.bezel_y * 0.33;
            let (bx, by) = match o {
                Orientation::Portrait => (sw / 2.0, sh + device.bezel_y / 2.0),
                Orientation::LandscapeLeft => (-device.bezel_y / 2.0, sh / 2.0),
                Orientation::LandscapeRight => (sw + device.bezel_y / 2.0, sh / 2.0),
            };
            (sx - bx).hypot(sy - by) <= r * 1.2
        }
        _ => {
            let bottom = device.insets(o).bottom;
            bottom > 0.0 && sy >= sh - bottom && sy <= sh && sx >= sw * 0.3 && sx <= sw * 0.7
        }
    }
}

fn rounded_rect(cr: &Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let r = r.min(w / 2.0).min(h / 2.0).max(0.0);
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 1.5 * PI);
    cr.close_path();
}

fn rgb(cr: &Context, c: [u8; 3]) {
    cr.set_source_rgb(c[0] as f64 / 255.0, c[1] as f64 / 255.0, c[2] as f64 / 255.0);
}

fn is_dark(c: [u8; 3]) -> bool {
    let l = 0.2126 * c[0] as f64 + 0.7152 * c[1] as f64 + 0.0722 * c[2] as f64;
    l < 140.0
}

/// Draw the whole device into a widget of the given size.
pub fn draw_device(cr: &Context, device: &Device, o: Orientation, l: &Layout, content: &ScreenContent, dark_ui: bool) {
    let _ = cr.save();
    cr.translate(l.cx, l.cy);
    cr.scale(l.scale, l.scale);

    let (bw, bh) = device.body_size();
    let ph = device.height as f64;
    let body_radius = if device.cutout == Cutout::HomeButton { 56.0 } else { device.screen_corner + device.bezel_x };

    // Body, drawn in the portrait frame and rotated into place.
    let _ = cr.save();
    cr.rotate(o.angle());
    // Side buttons.
    let button = |cr: &Context, x: f64, y: f64, h: f64| {
        rounded_rect(cr, x, y, 5.0, h, 2.0);
        cr.set_source_rgb(0.23, 0.23, 0.25);
        let _ = cr.fill();
    };
    if !device.tablet {
        button(cr, -bw / 2.0 - 3.5, -bh / 2.0 + bh * 0.17, 30.0);
        button(cr, -bw / 2.0 - 3.5, -bh / 2.0 + bh * 0.25, 58.0);
        button(cr, -bw / 2.0 - 3.5, -bh / 2.0 + bh * 0.33, 58.0);
        button(cr, bw / 2.0 - 1.5, -bh / 2.0 + bh * 0.27, 92.0);
    } else {
        rounded_rect(cr, bw / 2.0 - 60.0 - 50.0, -bh / 2.0 - 3.5, 50.0, 5.0, 2.0);
        cr.set_source_rgb(0.23, 0.23, 0.25);
        let _ = cr.fill();
        button(cr, bw / 2.0 - 1.5, -bh / 2.0 + 90.0, 50.0);
        button(cr, bw / 2.0 - 1.5, -bh / 2.0 + 150.0, 50.0);
    }
    rounded_rect(cr, -bw / 2.0, -bh / 2.0, bw, bh, body_radius);
    let g = LinearGradient::new(-bw / 2.0, 0.0, bw / 2.0, 0.0);
    g.add_color_stop_rgb(0.0, 0.16, 0.16, 0.17);
    g.add_color_stop_rgb(0.5, 0.09, 0.09, 0.10);
    g.add_color_stop_rgb(1.0, 0.16, 0.16, 0.17);
    let _ = cr.set_source(&g);
    let _ = cr.fill_preserve();
    cr.set_line_width(3.0);
    if dark_ui {
        cr.set_source_rgb(0.42, 0.42, 0.45);
    } else {
        cr.set_source_rgb(0.30, 0.30, 0.32);
    }
    let _ = cr.stroke();

    if device.cutout == Cutout::HomeButton {
        let r = device.bezel_y * 0.33;
        cr.arc(0.0, ph / 2.0 + device.bezel_y / 2.0, r, 0.0, 2.0 * PI);
        cr.set_source_rgb(0.05, 0.05, 0.06);
        let _ = cr.fill_preserve();
        cr.set_line_width(2.5);
        cr.set_source_rgb(0.35, 0.35, 0.37);
        let _ = cr.stroke();
        // Earpiece and camera.
        rounded_rect(cr, -30.0, -ph / 2.0 - device.bezel_y / 2.0 - 3.0, 60.0, 6.0, 3.0);
        cr.set_source_rgb(0.22, 0.22, 0.24);
        let _ = cr.fill();
        cr.arc(-48.0, -ph / 2.0 - device.bezel_y / 2.0, 5.0, 0.0, 2.0 * PI);
        let _ = cr.fill();
    }
    let _ = cr.restore();

    // Screen contents, drawn upright in the current orientation.
    let (sw, sh) = device.screen_size(o);
    let _ = cr.save();
    cr.translate(-sw / 2.0, -sh / 2.0);
    rounded_rect(cr, 0.0, 0.0, sw, sh, device.screen_corner);
    cr.clip();
    draw_screen(cr, device, o, content, l.scale);
    let _ = cr.restore();

    if device.cutout == Cutout::Island && !matches!(content, ScreenContent::Off) {
        let _ = cr.save();
        cr.rotate(o.angle());
        rounded_rect(cr, -63.0, -ph / 2.0 + 11.0, 126.0, 37.0, 18.5);
        cr.set_source_rgb(0.0, 0.0, 0.0);
        let _ = cr.fill();
        let _ = cr.restore();
    }
    let _ = cr.restore();
}

/// Draw the screen (status bar, app/home screen, home indicator) in screen
/// coordinates. `scale` is the on-screen magnification, used to pick a
/// sampling filter for app frames.
pub fn draw_screen(cr: &Context, device: &Device, o: Orientation, content: &ScreenContent, scale: f64) {
    let (sw, sh) = device.screen_size(o);
    let insets = device.insets(o);
    match content {
        ScreenContent::Off => {
            cr.set_source_rgb(0.0, 0.0, 0.0);
            let _ = cr.paint();
        }
        ScreenContent::Booting => {
            cr.set_source_rgb(0.0, 0.0, 0.0);
            let _ = cr.paint();
            draw_logo(cr, sw / 2.0, sh / 2.0, sw.min(sh) * 0.16);
        }
        ScreenContent::Home { apps, running } => {
            draw_wallpaper(cr, sw, sh);
            let _ = cr.save();
            cr.translate(insets.left, insets.top);
            let (aw, ah) = device.app_size(o);
            draw_home_icons(cr, device, aw as f64, ah as f64, apps, *running);
            let _ = cr.restore();
            if device.shows_status_bar(o) {
                draw_status_bar(cr, device, sw, insets.top, [255, 255, 255]);
            }
            draw_home_indicator(cr, device, sw, sh, insets.bottom, [255, 255, 255]);
        }
        ScreenContent::App(frame) => {
            if !frame.has_window {
                // The app is launching but has not shown a window yet.
                cr.set_source_rgb(1.0, 1.0, 1.0);
                let _ = cr.paint();
                draw_status_bar(cr, device, sw, insets.top, [0, 0, 0]);
                draw_home_indicator(cr, device, sw, sh, insets.bottom, [0, 0, 0]);
                return;
            }
            // Tint the system areas to match the app's edges.
            rgb(cr, frame.top_color);
            cr.rectangle(0.0, 0.0, sw, insets.top + 1.0);
            let _ = cr.fill();
            rgb(cr, frame.bottom_color);
            cr.rectangle(0.0, insets.top, sw, sh - insets.top);
            let _ = cr.fill();

            let _ = cr.save();
            cr.translate(insets.left, insets.top);
            let _ = cr.set_source_surface(&frame.surface, 0.0, 0.0);
            let filter = if (scale - 1.0).abs() < 0.01 { cairo::Filter::Nearest } else { cairo::Filter::Good };
            cr.source().set_filter(filter);
            let _ = cr.paint();
            let _ = cr.restore();

            if device.shows_status_bar(o) {
                let fg = if is_dark(frame.top_color) { [255, 255, 255] } else { [0, 0, 0] };
                draw_status_bar(cr, device, sw, insets.top, fg);
            }
            let fg = if is_dark(frame.bottom_color) { [255, 255, 255] } else { [0, 0, 0] };
            draw_home_indicator(cr, device, sw, sh, insets.bottom, fg);
        }
    }
}

fn draw_logo(cr: &Context, cx: f64, cy: f64, size: f64) {
    let _ = cr.save();
    cr.translate(cx - size / 2.0, cy - size / 2.0);
    cr.scale(size / 100.0, size / 100.0);
    cr.set_source_rgb(1.0, 1.0, 1.0);
    // An "L" between angle brackets, like the LCode icon.
    cr.move_to(36.0, 8.0);
    cr.line_to(50.0, 8.0);
    cr.line_to(50.0, 78.0);
    cr.line_to(76.0, 78.0);
    cr.line_to(76.0, 92.0);
    cr.line_to(36.0, 92.0);
    cr.close_path();
    let _ = cr.fill();
    cr.set_line_width(8.0);
    cr.set_line_cap(cairo::LineCap::Round);
    cr.set_line_join(cairo::LineJoin::Round);
    cr.move_to(20.0, 30.0);
    cr.line_to(0.0, 50.0);
    cr.line_to(20.0, 70.0);
    cr.move_to(80.0, 30.0);
    cr.line_to(100.0, 50.0);
    cr.line_to(80.0, 70.0);
    let _ = cr.stroke();
    let _ = cr.restore();
}

fn draw_wallpaper(cr: &Context, w: f64, h: f64) {
    let g = LinearGradient::new(0.0, 0.0, w * 0.4, h);
    g.add_color_stop_rgb(0.0, 0.16, 0.36, 0.86);
    g.add_color_stop_rgb(0.55, 0.42, 0.22, 0.78);
    g.add_color_stop_rgb(1.0, 0.95, 0.42, 0.45);
    let _ = cr.set_source(&g);
    let _ = cr.paint();
}

fn now_text(fmt: &str) -> String {
    gtk::glib::DateTime::now_local()
        .ok()
        .and_then(|d| d.format(fmt).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "9:41".into())
}

fn draw_status_bar(cr: &Context, device: &Device, sw: f64, height: f64, fg: [u8; 3]) {
    if height <= 0.0 {
        return;
    }
    let big = height >= 44.0;
    let font = if big { 17.0 } else { 12.5 };
    let cy = if big { height / 2.0 + 3.0 } else { height / 2.0 };
    rgb(cr, fg);
    cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Bold);
    cr.set_font_size(font);
    let time = now_text("%l:%M");

    let (time_cx, icons_cx) = if device.cutout == Cutout::Island {
        let ear = (sw / 2.0 - 63.0) / 2.0;
        (ear + 4.0, sw - ear - 4.0)
    } else {
        (0.0, 0.0)
    };
    if let Ok(ext) = cr.text_extents(&time) {
        let x = if device.cutout == Cutout::Island {
            time_cx - ext.width() / 2.0 - ext.x_bearing()
        } else if device.tablet {
            20.0
        } else {
            sw / 2.0 - ext.width() / 2.0 - ext.x_bearing()
        };
        cr.move_to(x, cy + ext.height() / 2.0);
        let _ = cr.show_text(&time);
        if device.tablet {
            let date = now_text("%a %b %-d");
            cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Normal);
            cr.move_to(20.0 + ext.width() + 10.0, cy + ext.height() / 2.0);
            let _ = cr.show_text(&date);
        }
    }

    // Signal, Wi-Fi and battery glyphs, right-aligned or centered in the right ear.
    let s = if big { 1.0 } else { 0.8 };
    let total = 72.0 * s;
    let x0 = if device.cutout == Cutout::Island { icons_cx - total / 2.0 } else { sw - 14.0 - total };
    let base = cy + 5.5 * s;
    rgb(cr, fg);
    for i in 0..4 {
        let bh = (4.0 + 2.5 * i as f64) * s;
        rounded_rect(cr, x0 + i as f64 * 4.5 * s, base - bh, 3.0 * s, bh, 1.0 * s);
        let _ = cr.fill();
    }
    // Wi-Fi: three arcs above a dot.
    let wx = x0 + 28.0 * s;
    let wy = base;
    cr.set_line_width(2.0 * s);
    cr.set_line_cap(cairo::LineCap::Round);
    for r in [3.5, 7.0, 10.5] {
        cr.arc(wx, wy, r * s, -PI * 0.75, -PI * 0.25);
        let _ = cr.stroke();
    }
    cr.arc(wx, wy - 0.5 * s, 1.4 * s, 0.0, 2.0 * PI);
    let _ = cr.fill();
    // Battery.
    let bx = x0 + 44.0 * s;
    let (bw, bh) = (25.0 * s, 12.0 * s);
    rounded_rect(cr, bx, base - bh, bw, bh, 3.5 * s);
    cr.set_line_width(1.0 * s);
    let _ = cr.save();
    cr.set_source_rgba(fg[0] as f64 / 255.0, fg[1] as f64 / 255.0, fg[2] as f64 / 255.0, 0.45);
    let _ = cr.stroke();
    let _ = cr.restore();
    rounded_rect(cr, bx + 2.0 * s, base - bh + 2.0 * s, (bw - 4.0 * s) * 0.82, bh - 4.0 * s, 2.0 * s);
    let _ = cr.fill();
    rounded_rect(cr, bx + bw + 1.0 * s, base - bh / 2.0 - 2.0 * s, 1.6 * s, 4.0 * s, 0.8 * s);
    let _ = cr.fill();
}

fn draw_home_indicator(cr: &Context, device: &Device, sw: f64, sh: f64, bottom: f64, fg: [u8; 3]) {
    if bottom <= 0.0 || device.cutout == Cutout::HomeButton {
        return;
    }
    let w = (sw * 0.35).min(140.0);
    rounded_rect(cr, (sw - w) / 2.0, sh - 8.0 - 5.0, w, 5.0, 2.5);
    rgb(cr, fg);
    let _ = cr.fill();
}

/// Position of the `i`th icon on the home screen, in app-area coordinates.
pub fn home_icon_rect(device: &Device, app_w: f64, i: usize) -> (f64, f64, f64) {
    let cols = if device.tablet { 6 } else { 4 };
    let size = if device.tablet { 74.0 } else { 62.0 };
    let gap = (app_w - cols as f64 * size) / (cols as f64 + 1.0);
    let row_h = size + 34.0;
    let col = i % cols;
    let row = i / cols;
    (gap + col as f64 * (size + gap), 28.0 + row as f64 * row_h, size)
}

pub fn home_icon_at(device: &Device, app_w: f64, count: usize, x: f64, y: f64) -> Option<usize> {
    (0..count).find(|&i| {
        let (ix, iy, s) = home_icon_rect(device, app_w, i);
        x >= ix && x <= ix + s && y >= iy && y <= iy + s
    })
}

fn icon_color(name: &str) -> [f64; 3] {
    const PALETTE: [[f64; 3]; 6] = [
        [0.20, 0.47, 0.96],
        [0.20, 0.78, 0.35],
        [1.00, 0.58, 0.00],
        [0.69, 0.32, 0.87],
        [1.00, 0.23, 0.19],
        [0.35, 0.34, 0.84],
    ];
    let h = name.bytes().fold(7u32, |h, b| h.wrapping_mul(31).wrapping_add(b as u32));
    PALETTE[h as usize % PALETTE.len()]
}

fn draw_home_icons(cr: &Context, device: &Device, aw: f64, ah: f64, apps: &[String], running: Option<&str>) {
    if apps.is_empty() {
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.9);
        cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Bold);
        cr.set_font_size(48.0);
        let time = now_text("%l:%M");
        if let Ok(ext) = cr.text_extents(&time) {
            cr.move_to(aw / 2.0 - ext.width() / 2.0 - ext.x_bearing(), ah * 0.2);
            let _ = cr.show_text(&time);
        }
        cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Normal);
        cr.set_font_size(15.0);
        for (i, line) in ["No apps installed.", "Run an app project from LCode."].iter().enumerate() {
            if let Ok(ext) = cr.text_extents(line) {
                cr.move_to(aw / 2.0 - ext.width() / 2.0 - ext.x_bearing(), ah * 0.5 + i as f64 * 22.0);
                let _ = cr.show_text(line);
            }
        }
        return;
    }
    for (i, name) in apps.iter().enumerate() {
        let (x, y, s) = home_icon_rect(device, aw, i);
        let [r, g, b] = icon_color(name);
        let grad = LinearGradient::new(x, y, x, y + s);
        grad.add_color_stop_rgb(0.0, (r + 0.15).min(1.0), (g + 0.15).min(1.0), (b + 0.15).min(1.0));
        grad.add_color_stop_rgb(1.0, r * 0.85, g * 0.85, b * 0.85);
        rounded_rect(cr, x, y, s, s, s * 0.225);
        let _ = cr.set_source(&grad);
        let _ = cr.fill();

        let letter: String = name.chars().next().map(|c| c.to_uppercase().collect()).unwrap_or_default();
        cr.set_source_rgb(1.0, 1.0, 1.0);
        cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Bold);
        cr.set_font_size(s * 0.5);
        if let Ok(ext) = cr.text_extents(&letter) {
            cr.move_to(x + s / 2.0 - ext.width() / 2.0 - ext.x_bearing(), y + s / 2.0 - ext.height() / 2.0 - ext.y_bearing());
            let _ = cr.show_text(&letter);
        }
        cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Normal);
        cr.set_font_size(12.0);
        let fits = |t: &str| cr.text_extents(t).map(|e| e.width()).unwrap_or(0.0) <= s + 16.0;
        let mut label = name.clone();
        let mut chars: Vec<char> = name.chars().collect();
        while !fits(&label) && chars.len() > 1 {
            chars.pop();
            label = chars.iter().collect::<String>() + "…";
        }
        if let Ok(ext) = cr.text_extents(&label) {
            cr.move_to(x + s / 2.0 - ext.width() / 2.0 - ext.x_bearing(), y + s + 16.0);
            let _ = cr.show_text(&label);
        }
        if running == Some(name.as_str()) {
            cr.arc(x + s / 2.0, y + s + 24.0, 2.5, 0.0, 2.0 * PI);
            let _ = cr.fill();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::device::by_id;
    use super::*;

    #[test]
    fn maps_widget_points_into_the_app_area() {
        let d = by_id("lphone-16").unwrap();
        let o = Orientation::Portrait;
        let l = Layout { scale: 0.5, cx: 300.0, cy: 400.0 };
        // Screen center maps to the center of the screen.
        let (sx, sy) = widget_to_screen(&l, d, o, 300.0, 400.0);
        assert_eq!((sx, sy), (393.0 / 2.0, 852.0 / 2.0));
        // The status bar is outside the app area.
        assert!(widget_to_app(&l, d, o, 300.0, 400.0 - 852.0 / 4.0 + 5.0).is_none());
        let (ax, ay) = widget_to_app(&l, d, o, 300.0, 400.0).unwrap();
        assert_eq!((ax, ay), (393.0 / 2.0, 852.0 / 2.0 - 54.0));
    }

    #[test]
    fn finds_home_icons() {
        let d = by_id("lphone-16").unwrap();
        let (x, y, s) = home_icon_rect(d, 393.0, 1);
        assert_eq!(home_icon_at(d, 393.0, 3, x + s / 2.0, y + s / 2.0), Some(1));
        assert_eq!(home_icon_at(d, 393.0, 1, x + s / 2.0, y + s / 2.0), None);
    }
}
