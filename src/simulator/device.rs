//! Simulated device catalog. Sizes are in points and mirror common phone and
//! tablet form factors; names are LCode's own.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cutout {
    /// Pill-shaped camera cutout at the top of the screen.
    Island,
    /// Classic design: thick bezels and a round home button.
    HomeButton,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Orientation {
    Portrait,
    /// Rotated counter-clockwise: the top of the device points left.
    LandscapeLeft,
    /// Rotated clockwise: the top of the device points right.
    LandscapeRight,
}

impl Orientation {
    pub fn is_landscape(self) -> bool {
        self != Orientation::Portrait
    }

    pub fn rotated_left(self) -> Self {
        match self {
            Orientation::Portrait => Orientation::LandscapeLeft,
            Orientation::LandscapeLeft => Orientation::Portrait,
            Orientation::LandscapeRight => Orientation::Portrait,
        }
    }

    pub fn rotated_right(self) -> Self {
        match self {
            Orientation::Portrait => Orientation::LandscapeRight,
            Orientation::LandscapeRight => Orientation::Portrait,
            Orientation::LandscapeLeft => Orientation::Portrait,
        }
    }

    /// Rotation of the device body, in radians, when drawn on screen.
    pub fn angle(self) -> f64 {
        match self {
            Orientation::Portrait => 0.0,
            Orientation::LandscapeLeft => -std::f64::consts::FRAC_PI_2,
            Orientation::LandscapeRight => std::f64::consts::FRAC_PI_2,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Insets {
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
    pub left: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Device {
    pub id: &'static str,
    pub name: &'static str,
    pub tablet: bool,
    /// Portrait screen size in points.
    pub width: u32,
    pub height: u32,
    pub screen_corner: f64,
    pub bezel_x: f64,
    pub bezel_y: f64,
    pub status_bar: f64,
    pub home_indicator: f64,
    pub cutout: Cutout,
}

pub const OS_NAME: &str = "LOS";
pub const OS_VERSION: &str = "26.0";

pub const DEVICES: &[Device] = &[
    Device {
        id: "lphone-16",
        name: "LPhone 16",
        tablet: false,
        width: 393,
        height: 852,
        screen_corner: 55.0,
        bezel_x: 14.0,
        bezel_y: 14.0,
        status_bar: 54.0,
        home_indicator: 34.0,
        cutout: Cutout::Island,
    },
    Device {
        id: "lphone-16-pro-max",
        name: "LPhone 16 Pro Max",
        tablet: false,
        width: 440,
        height: 956,
        screen_corner: 62.0,
        bezel_x: 14.0,
        bezel_y: 14.0,
        status_bar: 62.0,
        home_indicator: 34.0,
        cutout: Cutout::Island,
    },
    Device {
        id: "lphone-se",
        name: "LPhone SE",
        tablet: false,
        width: 375,
        height: 667,
        screen_corner: 0.0,
        bezel_x: 22.0,
        bezel_y: 96.0,
        status_bar: 20.0,
        home_indicator: 0.0,
        cutout: Cutout::HomeButton,
    },
    Device {
        id: "lpad-air-11",
        name: "LPad Air 11-inch",
        tablet: true,
        width: 820,
        height: 1180,
        screen_corner: 18.0,
        bezel_x: 24.0,
        bezel_y: 24.0,
        status_bar: 24.0,
        home_indicator: 20.0,
        cutout: Cutout::None,
    },
    Device {
        id: "lpad-pro-13",
        name: "LPad Pro 13-inch",
        tablet: true,
        width: 1032,
        height: 1376,
        screen_corner: 18.0,
        bezel_x: 22.0,
        bezel_y: 22.0,
        status_bar: 24.0,
        home_indicator: 20.0,
        cutout: Cutout::None,
    },
];

pub fn by_id(id: &str) -> Option<&'static Device> {
    DEVICES.iter().find(|d| d.id == id)
}

pub fn default_device() -> &'static Device {
    &DEVICES[0]
}

impl Device {
    /// Full screen size (points) in the given orientation.
    pub fn screen_size(&self, o: Orientation) -> (f64, f64) {
        let (w, h) = (self.width as f64, self.height as f64);
        if o.is_landscape() { (h, w) } else { (w, h) }
    }

    /// Size of the whole device body (points) in portrait.
    pub fn body_size(&self) -> (f64, f64) {
        (self.width as f64 + 2.0 * self.bezel_x, self.height as f64 + 2.0 * self.bezel_y)
    }

    /// Body size as laid out in the given orientation.
    pub fn view_size(&self, o: Orientation) -> (f64, f64) {
        let (w, h) = self.body_size();
        if o.is_landscape() { (h, w) } else { (w, h) }
    }

    /// Areas of the screen reserved for system UI (status bar, home indicator,
    /// camera housing). The app's window fills the rest, like a safe area.
    pub fn insets(&self, o: Orientation) -> Insets {
        if !o.is_landscape() {
            return Insets { top: self.status_bar, bottom: self.home_indicator, ..Default::default() };
        }
        if self.tablet {
            return Insets { top: self.status_bar, bottom: self.home_indicator, ..Default::default() };
        }
        match self.cutout {
            // Phones hide the status bar in landscape; the camera housing side is kept clear.
            Cutout::Island => Insets { left: 59.0, right: 59.0, bottom: 21.0, top: 0.0 },
            _ => Insets::default(),
        }
    }

    /// Size (whole pixels) of the app window in the given orientation.
    pub fn app_size(&self, o: Orientation) -> (u16, u16) {
        let (w, h) = self.screen_size(o);
        let i = self.insets(o);
        ((w - i.left - i.right).round() as u16, (h - i.top - i.bottom).round() as u16)
    }

    /// Side of the square virtual display, big enough for both orientations.
    pub fn display_side(&self) -> u16 {
        let (pw, ph) = self.app_size(Orientation::Portrait);
        let (lw, lh) = self.app_size(Orientation::LandscapeLeft);
        pw.max(ph).max(lw).max(lh)
    }

    pub fn shows_status_bar(&self, o: Orientation) -> bool {
        self.insets(o).top > 0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_area_excludes_system_ui() {
        let d = by_id("lphone-16").unwrap();
        assert_eq!(d.app_size(Orientation::Portrait), (393, 852 - 54 - 34));
        assert_eq!(d.app_size(Orientation::LandscapeLeft), (852 - 118, 393 - 21));
        assert_eq!(d.display_side(), 764);
        let se = by_id("lphone-se").unwrap();
        assert_eq!(se.app_size(Orientation::LandscapeRight), (667, 375));
    }

    #[test]
    fn device_ids_are_unique() {
        for (i, a) in DEVICES.iter().enumerate() {
            assert!(DEVICES[i + 1..].iter().all(|b| b.id != a.id));
        }
    }
}
