// An app's icon, or any theme icon: the one way the shell draws them (CS2-004).
//
//   AppIcon { width: 54; height: 54; source: Quickshell.iconPath(entry.icon, "application-x-executable") }
//
// It's an Image, so status, scale, layer and the rest work as usual. What it
// adds is what every icon needs and was easy to forget:
// - theme icons (image://icon/…, from Quickshell.iconPath) load on the GUI
//   thread: Quickshell's icon provider calls QIcon::pixmap, which crashed the
//   shell at start-up when an Image loaded it in the background. Files (an
//   app's own artwork) still load in the background.
// - drawn from twice its size, so it's sharp on a 2× screen and scaled down
//   smoothly (mipmaps) in the Dock and Launchpad.
// - aspect kept, and left out of the accessibility tree: the app's name is
//   beside it, or on the button it's in.
// An icon whose size animates sets a fixed sourceSize, or it would be loaded
// again on every frame.
import QtQuick

Image {
    asynchronous: !String(source).startsWith("image://")
    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    Accessible.ignored: true
}
