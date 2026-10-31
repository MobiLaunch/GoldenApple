pragma Singleton
// Which CitronOS this is: the name, the release's name and its version, in one
// place. About This Computer shows them; the live image writes the same into
// /usr/lib/os-release (distro/archiso/build.sh reads them from here).
import QtQuick

QtObject {
    readonly property string name: "CitronOS"
    readonly property string release: "Club Soda"
    readonly property string version: "4.0"
    readonly property string fullName: name + " " + release            // CitronOS Club Soda
    readonly property string pretty: fullName + " " + version          // CitronOS Club Soda 4.0
}
