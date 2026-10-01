#!/usr/bin/env python3
"""Keep Golden Gate application controls centralized in apps/lib."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
lib = root / "apps/lib"
standard = {
    "AppWindow.qml", "Button.qml", "Checkbox.qml", "FocusRing.qml", "Glass.qml",
    "PopUpButton.qml", "PopupMenu.qml", "ProgressBar.qml", "RoundedImage.qml", "Segmented.qml",
    "SidebarRow.qml", "EmptyState.qml",
    "Slider.qml", "Spring.qml", "SpringValue.qml", "Switch.qml", "Symbol.qml",
    "TextField.qml", "TextArea.qml", "ToolbarButton.qml", "ToolbarPill.qml", "TrafficLights.qml",
}
errors = []
for name in sorted(standard):
    if not (lib / name).is_file():
        errors.append(f"shared component missing: apps/lib/{name}")

for path in (root / "apps").rglob("*.qml"):
    if lib in path.parents:
        continue
    text = path.read_text(encoding="utf-8")
    if path.name in standard:
        errors.append(f"forked standard control outside shared store: {path.relative_to(root)}")
    if "TextInput {" in text:
        errors.append(f"raw TextInput outside shared TextField: {path.relative_to(root)}")
    if "TextEdit {" in text:
        errors.append(f"raw TextEdit outside shared TextArea: {path.relative_to(root)}")


packages = {
    line.strip()
    for line in (root / "distro/archiso/packages.x86_64").read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
}
foreign_primary = {
    "nautilus", "gnome-software", "gnome-control-center", "gnome-clocks",
    "gnome-text-editor", "gnome-calendar", "loupe", "geary", "fractal", "firefox",
}
for package in sorted(foreign_primary & packages):
    errors.append(f"foreign primary UI package returned to default image: {package}")

# Golden Gate desktop entries may use mature engines internally (for example
# Terminal -> ghostty), but must not directly launch the foreign primary apps
# that have native Golden Gate replacements.
foreign_exec = ("nautilus", "gnome-software", "gnome-control-center", "gnome-calendar",
                "geary", "fractal", "firefox", "gnome-text-editor", "gnome-clocks", "loupe")
for desktop in sorted((root / "apps/desktop").glob("*.desktop")):
    text = desktop.read_text(encoding="utf-8").lower()
    for command in foreign_exec:
        if f"exec={command}" in text or f"exec=sh -c '{command}" in text:
            errors.append(f"Golden Gate desktop entry launches foreign primary UI: {desktop.name} -> {command}")

dock = (root / "shell/Dock.qml").read_text(encoding="utf-8")
for app_id in [
    "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail",
    "org.goldengate.Messages", "org.goldengate.Calendar", "org.goldengate.Software",
    "org.goldengate.Settings", "org.goldengate.Terminal",
]:
    if app_id not in dock:
        errors.append(f"Dock no longer pins native app: {app_id}")
for foreign_id in ["org.gnome.Nautilus", "org.gnome.Geary", "org.gnome.Fractal", "org.gnome.Calendar"]:
    if foreign_id in dock:
        errors.append(f"Dock reintroduced foreign application: {foreign_id}")


# The source shell keeps thin adapters only; runtime install replaces them
# with direct symlinks to the canonical store.
shell_components = root / "shell/components"
for name in ("Glass.qml", "TextField.qml", "Symbol.qml", "Spring.qml", "SpringValue.qml"):
    path = shell_components / name
    text = path.read_text(encoding="utf-8")
    if 'import "../../apps/lib" as Shared' not in text or "Shared." not in text:
        errors.append(f"shell primitive is no longer a shared-UI adapter: {path.relative_to(root)}")

# Setup must consume the canonical controls too. Compatibility wrappers are
# allowed only when they delegate to the shared implementation.
setup = root / "apps" / "setup"
if (setup / "Checkbox.qml").exists():
    errors.append("Setup reintroduced a private Checkbox instead of apps/lib/Checkbox.qml")

for qml in setup.rglob("*.qml"):
    text = qml.read_text(encoding="utf-8")
    if "ShaderEffect" in text:
        errors.append(f"legacy private glass shader in Setup: {qml.relative_to(root)}")

liquid = (setup / "LiquidGlass.qml").read_text(encoding="utf-8")
for needle in ['import "../lib"', "Glass {"]:
    if needle not in liquid:
        errors.append(f"Setup LiquidGlass wrapper no longer delegates to shared Glass: {needle}")

if (setup / "shaders").exists():
    errors.append("legacy Setup shader directory exists; HyprGlass is the compositor glass implementation")

# Web is deliberately isolated from Quickshell because it hosts Chromium, but
# it still has one browser-local adapter layer rather than one-off Qt widgets.
browser = (root / "apps/browser/browser.py").read_text(encoding="utf-8")
browser_ui = root / "apps/browser/ui.py"
if not browser_ui.is_file():
    errors.append("Web is missing its centralized browser UI adapter")
for forbidden in ("QPushButton", "QLineEdit", "QToolButton", "QIcon"):
    if re.search(rf"\\b{forbidden}\\b", browser):
        errors.append(f"Web reintroduced ad-hoc Qt control plumbing: {forbidden}")
if re.search(r"^ASSETS\\s*=", browser, flags=re.M):
    errors.append("Web reintroduced a private browser asset-path constant")
for required in ("GGButton", "GGLineEdit", "GGToolButton", "refresh_icons", "stylesheet"):
    if required not in browser:
        errors.append(f"Web no longer consumes centralized browser UI primitive: {required}")

install = (root / "scripts/install.sh").read_text(encoding="utf-8")
for needle in [
    'cp -a "$REPO/apps/lib" "$SHARE/ui"',
    'ln -s ../ui "$SHARE/apps/lib"',
    'cp -a "$REPO/apps/lib" "$DATA/golden-gate/ui"',
    'ln -s ../ui "$DATA/golden-gate/apps/lib"',
]:
    if needle not in install:
        errors.append(f"installer no longer guarantees canonical shared UI: {needle}")

# SDDM must stage canonical primitives rather than copying the entire shell
# component tree and silently forking the login-screen UI.
for needle in [
    'cp "$REPO/apps/lib/$shared" "$T/components/$shared"',
    'cp "$REPO/apps/lib/theme/Theme.qml" "$T/theme/Theme.qml"',
    'cp "$REPO/shell/components/LockSurface.qml" "$T/components/LockSurface.qml"',
    'cp "$REPO/shell/components/SystemClockProxy.qml" "$T/components/SystemClockProxy.qml"',
]:
    if needle not in install:
        errors.append(f"SDDM no longer consumes canonical shared UI: {needle}")
if 'cp -a "$REPO/shell/components" "$REPO/shell/theme" "$T/"' in install:
    errors.append("SDDM reverted to copying the whole shell component tree")

for needle in [
    'ln -s "$SHARED_UI/$shared" "$SHELL_RUNTIME/components/$shared"',
    'ln -s "$SHARED_UI/theme/Theme.qml" "$SHELL_RUNTIME/theme/Theme.qml"',
    'ln -s "/usr/share/golden-gate/ui/$shared" "$SHELL_SKEL/components/$shared"',
]:
    if needle not in install:
        errors.append(f"installer no longer links shell primitives to canonical UI: {needle}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("Shared UI architecture: one canonical application component store")
