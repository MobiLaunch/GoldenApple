import QtQuick
import QtQuick.Layouts
import "../lib"
import "../lib/theme"

Flickable {
    id: root
    Scroller { parent: root; flickable: root }
    property var data: ({ favorites: [], frequent: [], readingList: [], recentlyClosed: [], private: false })
    signal openUrl(string url)
    signal addFavoriteRequested()
    signal privacyRequested()
    clip: true
    contentWidth: width
    contentHeight: page.implicitHeight + 100
    boundsBehavior: Flickable.StopAtBounds

    function domain(url) {
        try {
            let s = String(url).replace(/^https?:\/\//, "").replace(/^www\./, "")
            return s.split("/")[0]
        } catch (_) { return String(url) }
    }

    Rectangle {
        anchors.fill: parent
        height: Math.max(root.height, root.contentHeight)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.dark ? "#23242a" : "#f7f8fb" }
            GradientStop { position: 0.52; color: Theme.dark ? "#1d1e23" : "#f1f4f9" }
            GradientStop { position: 1; color: Theme.dark ? "#1a1a1e" : "#eceff4" }
        }
    }

    Column {
        id: page
        width: Math.min(900, root.width - 70)
        anchors.horizontalCenter: parent.horizontalCenter
        y: 72
        spacing: 34

        Column {
            width: parent.width
            spacing: 6
            Text {
                text: root.data.private ? "Private Browsing"
                    : new Date().getHours() < 12 ? "Good Morning"
                    : new Date().getHours() < 18 ? "Good Afternoon" : "Good Evening"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 34; weight: Font.DemiBold; letterSpacing: -0.8 }
            }
            Text {
                text: root.data.private
                    ? "Pages in this window aren't added to CitronOS Web history."
                    : "Start where you left off, or head somewhere new."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
        }

        Column {
            width: parent.width
            spacing: 14
            Row {
                width: parent.width
                Text {
                    text: "Favorites"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.DemiBold }
                }
                Item { width: Math.max(0, parent.width - parent.children[0].width - addFavorite.width); height: 1 }
                Text {
                    id: addFavorite
                    visible: !root.data.private
                    text: "Add Favorite"
                    color: Theme.accent
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                    TapHandler { onTapped: root.addFavoriteRequested() }
                }
            }

            Flow {
                width: parent.width
                spacing: 18
                Repeater {
                    model: root.data.favorites
                    delegate: Item {
                        id: favorite
                        required property var modelData
                        required property int index
                        width: 102; height: 100
                        // The Start Page's favorites come up one after another as it appears.
                        property real enter: 1
                        opacity: enter
                        transform: Translate { y: (1 - favorite.enter) * 14 }
                        function appear() {
                            if (Theme.reduceMotion) return
                            enter = 0
                            favoriteIn.restart()
                        }
                        Component.onCompleted: if (root.visible) appear()
                        Connections { target: root; function onVisibleChanged() { if (root.visible) favorite.appear() } }
                        SequentialAnimation {
                            id: favoriteIn
                            PauseAnimation { duration: 40 + Math.min(favorite.index, 10) * 30 }
                            NumberAnimation { target: favorite; property: "enter"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                        }
                        Rectangle {
                            id: favIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 62; height: 62; radius: 15
                            gradient: Gradient {
                                GradientStop { position: 0; color: Theme.dark ? "#536174" : "#8fb8e9" }
                                GradientStop { position: 1; color: Theme.dark ? "#3a4455" : "#6f79bd" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: (modelData.title || root.domain(modelData.url)).charAt(0).toUpperCase()
                                color: "#ffffff"
                                font { family: Theme.fontDisplay; pixelSize: 25; weight: Font.DemiBold }
                            }
                            scale: favArea.pressed ? 0.95 : favArea.containsMouse ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 140; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        }
                        Text {
                            anchors { top: favIcon.bottom; topMargin: 9; horizontalCenter: parent.horizontalCenter }
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: modelData.title || root.domain(modelData.url)
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        MouseArea {
                            id: favArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.openUrl(modelData.url)
                        }
                    }
                }
                Item {
                    visible: root.data.favorites.length === 0
                    width: 220; height: 74
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Favorites you save appear here."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                }
            }
        }

        component LinkCard: Rectangle {
            id: card
            property var record: ({})
            signal activated()
            width: parent ? parent.width : 500
            height: 58
            radius: 13
            color: Theme.dark ? "#10ffffff" : "#b8ffffff"
            border { width: 0.5; color: Theme.dark ? "#14ffffff" : "#10000000" }
            Row {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 11
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 9
                    color: Theme.dark ? "#18ffffff" : "#0d000000"
                    Text {
                        anchors.centerIn: parent
                        text: (card.record.title || root.domain(card.record.url)).charAt(0).toUpperCase()
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60
                    Text {
                        width: parent.width
                        text: card.record.title || root.domain(card.record.url)
                        color: Theme.label; elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
                    }
                    Text {
                        width: parent.width
                        text: root.domain(card.record.url)
                        color: Theme.secondaryLabel; elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: card.activated() }
        }

        GridLayout {
            width: parent.width
            columns: root.width > 760 ? 2 : 1
            columnSpacing: 22
            rowSpacing: 28

            Column {
                Layout.fillWidth: true
                spacing: 10
                visible: root.data.frequent.length > 0
                Text { text: "Frequently Visited"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(16); weight: Font.DemiBold } }
                Repeater {
                    model: root.data.frequent.slice(0, 4)
                    LinkCard { record: modelData; onActivated: root.openUrl(record.url) }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 10
                visible: root.data.readingList.length > 0
                Text { text: "Reading List"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(16); weight: Font.DemiBold } }
                Repeater {
                    model: root.data.readingList.slice(0, 4)
                    LinkCard { record: modelData; onActivated: root.openUrl(record.url) }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 10
                visible: root.data.recentlyClosed.length > 0
                Text { text: "Recently Closed"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(16); weight: Font.DemiBold } }
                Repeater {
                    model: root.data.recentlyClosed.slice(0, 4)
                    LinkCard { record: modelData; onActivated: root.openUrl(record.url) }
                }
            }

            Rectangle {
                id: privacyCard
                Layout.fillWidth: true
                visible: !root.data.private
                height: 126
                radius: 18
                color: Theme.dark ? "#12ffffff" : "#aaffffff"
                border { width: 0.5; color: Theme.separator }
                Row {
                    anchors { fill: parent; margins: 18 }
                    spacing: 15
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48; height: 48; radius: 14
                        color: Theme.dark ? "#1affffff" : "#100078ff"
                        Symbol { anchors.centerIn: parent; name: "shield"; tone: "accent"; size: 23 }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 70
                        spacing: 4
                        Text {
                            text: "Privacy Report"
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: !root.data.privacy?.enabled
                                ? "Privacy Protection is turned off."
                                : (root.data.privacy?.blocked ?? 0) === 0
                                    ? "No known third-party tracking requests blocked in this session yet."
                                    : (root.data.privacy.blocked + " known tracking request"
                                       + (root.data.privacy.blocked === 1 ? "" : "s")
                                       + " blocked from loading.")
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                    }
                }
                scale: privacyArea.pressed ? 0.985 : privacyArea.containsMouse ? 1.008 : 1
                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 100; easing.type: Easing.OutCubic } }
                MouseArea {
                    id: privacyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.privacyRequested()
                }
            }
        }
    }
}
