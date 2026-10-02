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
    "SidebarRow.qml", "SidebarSection.qml", "AccountRow.qml", "EmptyState.qml",
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


# The shell keeps thin adapters only, over the canonical store it reaches
# through ui/ (installed: a link to /usr/share/golden-gate/ui).
shell_components = root / "shell/components"
for name in ("Glass.qml", "TextField.qml", "Symbol.qml", "Spring.qml", "SpringValue.qml"):
    path = shell_components / name
    text = path.read_text(encoding="utf-8")
    if 'import "../ui" as Shared' not in text or "Shared." not in text:
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

# Web hosts Chromium outside Quickshell, but its QML uses the same shared
# controls and theme as every other app, not a private widget layer.
web = (root / "apps/browser/Browser.qml").read_text(encoding="utf-8")
for needle in ('import "../lib"', 'import "../lib/theme"'):
    if needle not in web:
        errors.append(f"Web no longer uses the shared UI: {needle}")
browser = (root / "apps/browser/browser.py").read_text(encoding="utf-8")
for forbidden in ("QPushButton", "QLineEdit", "QToolButton"):
    if re.search(rf"\\b{forbidden}\\b", browser):
        errors.append(f"Web reintroduced ad-hoc Qt widget controls: {forbidden}")

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
    'cp -a "$REPO/apps/lib" "$T/ui"',
    'cp "$REPO/shell/components/$shared" "$T/components/$shared"',
    'cp "$REPO/shell/components/LockSurface.qml" "$T/components/LockSurface.qml"',
    'cp "$REPO/shell/components/SystemClockProxy.qml" "$T/components/SystemClockProxy.qml"',
]:
    if needle not in install:
        errors.append(f"SDDM no longer consumes canonical shared UI: {needle}")
if 'cp -a "$REPO/shell/components" "$REPO/shell/theme" "$T/"' in install:
    errors.append("SDDM reverted to copying the whole shell component tree")

for needle in [
    'ln -s "$SHARED_UI" "$SHELL_RUNTIME/ui"',
    'ln -s "/usr/share/golden-gate/ui" "$SHELL_SKEL/ui"',
]:
    if needle not in install:
        errors.append(f"installer no longer links the shell to the canonical UI: {needle}")

# One Theme module per process: the shell and the greeter reach the theme only
# through ui/ (the shared store), never through a second theme directory, so
# the singleton the shell sets is the one every shared control reads.
if (root / "shell/theme").exists():
    errors.append("shell/theme is back: a second Theme module splits the singleton")
for qml in sorted([*(root / "shell").glob("*.qml"), *(root / "shell/components").glob("*.qml"),
                   root / "themes/sddm/golden-gate/Main.qml"]):
    for line in qml.read_text(encoding="utf-8").splitlines():
        m = re.match(r'import "([^"]*)"', line.strip())
        if not m:
            continue
        path = m.group(1)
        if path.endswith("theme") and path not in ("ui/theme", "../ui/theme"):
            errors.append(f"{qml.relative_to(root)} imports a theme outside ui/: {path}")
        if "apps/lib" in path:
            errors.append(f"{qml.relative_to(root)} imports apps/lib directly instead of ui/: {path}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("Shared UI architecture: one canonical application component store")
