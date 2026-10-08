// Wallpaper: the current one, and any picture to choose: the CitronOS
// collection, your own (~/.local/share/backgrounds/golden-gate and
// ~/Pictures/Wallpapers), your photos (the Photos library, newest first), or
// any picture on the computer (Choose…, a browser of its folders). A picture
// from outside your wallpapers is copied into them first (lib/set-wallpaper.py),
// so the wallpaper stays if the original goes. The shell picks it up at once.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    readonly property string current: sys.prefs.wallpaper || Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/tide.png"
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string userWalls: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/backgrounds/golden-gate"
    readonly property var photoDirs: (Quickshell.env("GG_PHOTOS_DIRS") || home + "/Pictures").split(":").filter((d) => d)
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../../lib/set-wallpaper.py").toString().replace("file://", ""))
    readonly property string pictureTest: "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' \\)"

    property var system: []
    property var yours: []
    property var photos: []
    property bool allPhotos: false
    property string error: ""
    property string busy: ""              // the picture being made the wallpaper

    // Choose…: a folder being browsed ("" when not), and what's in it.
    property string folder: ""
    property var folders: []
    property var pictures: []

    function title(path) {
        return path.split("/").pop().replace(/\.\w+$/, "").replace(/-[0-9a-f]{8}$/, "").replace(/[-_]/g, " ").replace(/^\w/, (c) => c.toUpperCase())
    }
    function lines(o) { return o.split("\n").filter((l) => l) }

    function scan() {
        sys.run(["sh", "-c", "ls -1 /usr/share/backgrounds/golden-gate/*.png /usr/share/backgrounds/golden-gate/*.jpg 2>/dev/null"],
                (o) => system = lines(o))
        sys.run(["sh", "-c", "for d in \"$1\" \"$2\"; do [ -d \"$d\" ] && find -L \"$d\" -maxdepth 1 -type f " + pictureTest + " -not -name '.*' -printf '%T@\\t%p\\n'; done 2>/dev/null | sort -rn | cut -f2-",
                 "sh", userWalls, home + "/Pictures/Wallpapers"], (o) => yours = [...new Set(lines(o))])
        sys.run(["sh", "-c", "for d in \"$@\"; do [ -d \"$d\" ] && find -L \"$d\" -type f " + pictureTest + " -not -path '*/.*' -not -path '*/Wallpapers/*' -printf '%T@\\t%p\\n'; done 2>/dev/null | sort -rn | head -n 240 | cut -f2-",
                 "sh"].concat(photoDirs), (o) => photos = lines(o))
    }
    Component.onCompleted: {
        scan()
        // Opened straight into Choose… (as GG_SETTINGS_PANE opens a pane).
        const start = Quickshell.env("GG_WALLPAPER_FOLDER")
        if (start) browse(start)
    }

    // Any picture: one of your wallpapers is used as it is; anything else is
    // copied into them first.
    function choose(path) {
        error = ""
        if (system.includes(path) || path.startsWith(userWalls + "/")) {
            sys.setPref(["wallpaper"], path)
            return
        }
        busy = path
        sys.run(["python3", helper, "--copy-only", path], (out, code) => {
            busy = ""
            const made = out.trim().split("\n").pop()
            if (code !== 0 || !made) {
                error = "That picture can't be used as the wallpaper."
                return
            }
            sys.setPref(["wallpaper"], made)
            folder = ""
            scan()
        })
    }

    function browse(dir) {
        folder = dir
        folders = []; pictures = []
        sys.run(["sh", "-c", "cd \"$1\" 2>/dev/null || exit 1; find -L . -mindepth 1 -maxdepth 1 -not -name '.*' -type d -printf 'd\\t%f\\n' 2>/dev/null | sort; find -L . -mindepth 1 -maxdepth 1 -not -name '.*' -type f " + pictureTest + " -printf 'f\\t%f\\n' 2>/dev/null | sort", "sh", dir],
                (o) => {
                    const all = lines(o).map((l) => l.split("\t"))
                    folders = all.filter((e) => e[0] === "d").map((e) => dir.replace(/\/$/, "") + "/" + e[1])
                    pictures = all.filter((e) => e[0] === "f").map((e) => dir.replace(/\/$/, "") + "/" + e[1])
                })
    }

    // One picture to choose: a rounded thumbnail and its name; the current
    // wallpaper has an accent ring a little outside it.
    component Tile: Item {
        id: tile
        required property string path
        property string label: pane.title(path)
        readonly property bool chosen: path === pane.current
        width: 128; height: 100
        Item {
            width: 128; height: 80
            scale: tap.pressed ? 0.95 : hover.hovered ? 1.03 : 1
            Behavior on scale { Spring { spring: Theme.snappy } }
            Rectangle {
                anchors { fill: parent; margins: -4 }
                radius: 12
                color: "transparent"
                border { width: 3; color: Theme.accent }
                opacity: tile.chosen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            RoundedImage {
                anchors.fill: parent; radius: 8; source: "file://" + tile.path
                opacity: pane.busy === tile.path ? 0.45 : 1      // being copied into your wallpapers
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: tile.label
            color: tile.chosen ? Theme.label : Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: tile.chosen ? Font.DemiBold : Font.Normal }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: pane.choose(tile.path) }
    }
    component Tiles: Flow {
        width: parent.width
        padding: 14
        spacing: 16
    }

    Group {
        SetRow {
            title: pane.title(pane.current)
            subtitle: "Current wallpaper"
            RoundedImage { width: 160; height: 100; radius: 8; source: "file://" + pane.current }
        }
        SetRow {
            objectName: "chooseWallpaper"
            title: "Any Picture"
            subtitle: "A picture from anywhere on this computer"
            Button { text: pane.folder ? "Done" : "Choose…"; onClicked: pane.folder ? pane.folder = "" : pane.browse(pane.home + "/Pictures") }
        }
    }
    Text {
        visible: !!pane.error
        width: parent.width
        text: pane.error
        color: Theme.dark ? "#ff453a" : "#ff3b30"
        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
    }

    // Choose…: the computer's folders, starting in Pictures.
    Group {
        objectName: "chooseAPicture"
        visible: !!pane.folder
        title: "Choose a Picture"
        Row {
            x: 14; height: 44
            spacing: 8
            Button { anchors.verticalCenter: parent.verticalCenter; symbol: "chevron-left"; enabled: pane.folder !== "/"; onClicked: pane.browse(pane.folder.replace(/\/[^/]+\/?$/, "") || "/") }
            Repeater {
                model: [["Pictures", "/Pictures"], ["Desktop", "/Desktop"], ["Downloads", "/Downloads"], ["Home", ""]]
                delegate: Button {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[0]
                    prominent: pane.folder === pane.home + modelData[1]
                    onClicked: pane.browse(pane.home + modelData[1])
                }
            }
        }
        Text {
            x: 14; width: parent.width - 28
            text: pane.folder.replace(pane.home, "~")
            elide: Text.ElideMiddle
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        Tiles {
            Repeater {
                model: pane.folders
                delegate: Item {
                    id: dir
                    required property string modelData
                    width: 128; height: 100
                    Rectangle {
                        width: 128; height: 80; radius: 8
                        color: dirHover.hovered ? Theme.fill : "transparent"
                        Symbol { anchors.centerIn: parent; name: "folder"; tone: "accent"; size: 44 }
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: dir.modelData.split("/").pop()
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    HoverHandler { id: dirHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pane.browse(dir.modelData) }
                }
            }
            Repeater {
                model: pane.pictures
                delegate: Tile { required property string modelData; path: modelData; label: modelData.split("/").pop() }
            }
        }
        Text {
            visible: !pane.folders.length && !pane.pictures.length
            x: 14; height: 40
            verticalAlignment: Text.AlignVCenter
            text: "No pictures or folders here."
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
        }
    }

    Group {
        visible: !pane.folder && pane.system.length > 0
        title: "CitronOS"
        Tiles { Repeater { model: pane.system; delegate: Tile { required property string modelData; path: modelData } } }
    }
    Group {
        visible: !pane.folder && pane.yours.length > 0
        title: "Your Wallpapers"
        Tiles { Repeater { model: pane.yours; delegate: Tile { required property string modelData; path: modelData } } }
    }
    Group {
        objectName: "photosWallpapers"
        visible: !pane.folder && pane.photos.length > 0
        title: "Photos"
        Tiles {
            Repeater {
                model: pane.allPhotos ? pane.photos : pane.photos.slice(0, 12)
                delegate: Tile { required property string modelData; path: modelData; label: "" ; height: 84 }
            }
        }
        SetRow {
            visible: pane.photos.length > 12
            title: pane.allPhotos ? "Show Fewer" : "Show All " + pane.photos.length + " Photos"
            chevron: !pane.allPhotos
            onClicked: pane.allPhotos = !pane.allPhotos
        }
    }
}
