// Setup compatibility wrapper around the shared Golden Gate Glass component.
// Optical blur/refraction now belongs to HyprGlass at the compositor boundary;
// QML only paints the shared material/chrome.
import QtQuick
import "../lib"

Glass {
    id: glass

    // Kept for source compatibility with the old shader-backed component.
    property var source: null
    property Item backdropItem: null
    property real bezel: 28
    property real strength: 34

    // Map the old bezel idea onto the shared material's edge lens.
    lens: Math.max(4, Math.min(9, bezel * 0.22))
}
