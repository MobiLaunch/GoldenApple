//@ pragma AppId org.goldengate.Calculator
// Calculator, laid out like Calculator on macOS 27: a small dark window, the
// expression above a large result, four columns of round keys, and a history
// sidebar. Keyboard: digits, + - * / % . , Enter/=, Backspace, Escape (clear),
// Ctrl+C copies the result.
import Quickshell
import QtQuick
import "lib"
import "lib/theme"
import "calculator"
import "calculator/engine.js" as Engine

ShellRoot {
    AppWindow {
        id: win
        title: "Calculator"
        forceDark: true
        resizable: false
        background: "#24292d"
        sidebarWidth: calc.historyOpen ? 200 : 0
        readonly property size fixed: Qt.size(229 + (calc.historyOpen ? 208 : 0), 405)
        implicitWidth: fixed.width; implicitHeight: fixed.height
        minimumSize: fixed; maximumSize: fixed

        toolbarRight: [
            ToolbarButton {
                round: true; symbol: "sidebar"; tone: "white"
                glassColor: "#191d20"; checked: calc.historyOpen
                onClicked: calc.historyOpen = !calc.historyOpen
            },
            Item { width: 29; height: 1 },
            ToolbarButton {
                round: true; symbol: "calculator"; tone: "white"
                glassColor: "#191d20"; checked: modeMenu.visible
                onClicked: modeMenu.visible = !modeMenu.visible
            }
        ]

        sidebar: [
            Text {
                x: 8; y: 6
                text: "History"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
            },
            ListView {
                y: 28; width: parent.width; height: parent.height - 28
                clip: true
                model: calc.history
                spacing: 2
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width; height: 46
                    Rectangle { anchors.fill: parent; radius: 9; color: "#ffffff"; opacity: hover.hovered ? 0.08 : 0 }
                    Column {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        Text { anchors.right: parent.right; text: calc.sep(modelData.expr); color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
                        Text { anchors.right: parent.right; text: calc.sep(modelData.result); color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 16; weight: Font.Medium } }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: calc.recall(modelData.value) }
                }
            }
        ]

        Item {
            id: calc
            anchors.fill: parent
            focus: true

            property bool historyOpen: false
            property bool separators: true
            property var tokens: []          // numbers and "+-*/" operators
            property string current: ""      // the number being typed
            property bool done: false        // just pressed =
            property real result: 0
            property var history: []

            readonly property string pendingOp: current === "" && tokens.length && typeof tokens[tokens.length - 1] !== "number" ? tokens[tokens.length - 1] : ""
            function sep(s) { return separators ? s : s.replace(/,/g, "") }
            readonly property string exprText: sep(Engine.expression(tokens, current))
            readonly property string bigText: sep(done ? Engine.format(result)
                                            : current !== "" ? Engine.groupTyped(current)
                                            : tokens.length ? Engine.format(Engine.evaluate(tokens)) : "0")

            function digit(d) {
                if (done) { tokens = []; current = ""; done = false }
                if (current.replace(/[-.]/g, "").length >= 9) return
                current = current === "0" ? d : current === "-0" ? "-" + d : current + d
            }
            function dot() {
                if (done) { tokens = []; current = ""; done = false }
                if (current.indexOf(".") < 0) current = (current === "" || current === "-" ? current + "0" : current) + "."
            }
            function op(o) {
                if (done) { tokens = [result]; done = false }
                else if (current !== "" && current !== "-") { tokens = tokens.concat([Number(current)]); current = "" }
                else if (pendingOp) { tokens = tokens.slice(0, -1) }
                if (!tokens.length) tokens = [0]
                tokens = tokens.concat([o])
            }
            function equals() {
                let t = tokens
                if (current !== "" && current !== "-") t = t.concat([Number(current)])
                if (!t.length) return
                if (typeof t[t.length - 1] !== "number") t = t.slice(0, -1)
                if (t.length < 3 && !done) { result = t[0]; done = true; tokens = t; current = ""; return }
                result = Engine.evaluate(t)
                const entry = { expr: Engine.expression(t, ""), result: Engine.format(result), value: result }
                history = [entry].concat(history).slice(0, 50)
                tokens = t; current = ""; done = true
            }
            function clear() {
                if (current !== "" && !done) current = ""
                else { tokens = []; current = ""; done = false; result = 0 }
            }
            function backspace() {
                if (done) return
                current = current.slice(0, -1)
                if (current === "-") current = ""
            }
            function percent() {
                if (done) { result = result / 100; return }
                if (current !== "") current = String(Number(current) / 100)
            }
            function sign() {
                if (done) { result = -result; return }
                current = current.startsWith("-") ? current.slice(1) : "-" + (current || "0")
            }
            function recall(v) { tokens = []; current = ""; result = v; done = true }

            Keys.onPressed: (e) => {
                const t = e.text
                if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_C) { Quickshell.clipboardText = bigText.replace(/,/g, ""); return }
                if (/^[0-9]$/.test(t)) digit(t)
                else if (t === "." || t === ",") dot()
                else if ("+-*/".includes(t)) op(t)
                else if (t === "%") percent()
                else if (t === "=" || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) equals()
                else if (e.key === Qt.Key_Backspace) backspace()
                else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Delete) clear()
                else return
                e.accepted = true
            }

            // Display: the expression, and the number or result below it.
            Column {
                anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; top: parent.top; topMargin: 4 }
                spacing: -2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: calc.exprText
                    color: "#9a9c9d"
                    elide: Text.ElideLeft
                    font { family: Theme.fontUi; pixelSize: 17 }
                }
                Text {
                    width: parent.width; height: 48
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: calc.bigText
                    color: "#ffffff"
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 18
                    font { family: Theme.fontUi; pixelSize: 40; weight: Font.Light }
                }
            }

            // Keys: 4 × 5, 47 px, as on the Mac.
            Grid {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
                columns: 4
                columnSpacing: 6; rowSpacing: 7
                CalcKey { kind: "function"; deleteGlyph: true; onPressed: calc.backspace() }
                CalcKey { kind: "function"; label: calc.current !== "" && !calc.done ? "C" : "AC"; onPressed: calc.clear() }
                CalcKey { kind: "function"; label: "%"; onPressed: calc.percent() }
                CalcKey { kind: "operator"; label: "÷"; selected: calc.pendingOp === "/"; onPressed: calc.op("/") }
                CalcKey { label: "7"; onPressed: calc.digit("7") }
                CalcKey { label: "8"; onPressed: calc.digit("8") }
                CalcKey { label: "9"; onPressed: calc.digit("9") }
                CalcKey { kind: "operator"; label: "×"; selected: calc.pendingOp === "*"; onPressed: calc.op("*") }
                CalcKey { label: "4"; onPressed: calc.digit("4") }
                CalcKey { label: "5"; onPressed: calc.digit("5") }
                CalcKey { label: "6"; onPressed: calc.digit("6") }
                CalcKey { kind: "operator"; label: "−"; selected: calc.pendingOp === "-"; onPressed: calc.op("-") }
                CalcKey { label: "1"; onPressed: calc.digit("1") }
                CalcKey { label: "2"; onPressed: calc.digit("2") }
                CalcKey { label: "3"; onPressed: calc.digit("3") }
                CalcKey { kind: "operator"; label: "+"; selected: calc.pendingOp === "+"; onPressed: calc.op("+") }
                CalcKey { label: "+/−"; onPressed: calc.sign() }
                CalcKey { label: "0"; onPressed: calc.digit("0") }
                CalcKey { label: "."; onPressed: calc.dot() }
                CalcKey { kind: "operator"; label: "="; onPressed: calc.equals() }
            }

            // The mode menu under the calculator button (View menu on the Mac).
            MouseArea {
                anchors.fill: parent
                visible: modeMenu.visible
                onPressed: modeMenu.visible = false
            }
            Rectangle {
                id: modeMenu
                visible: false
                anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: -4 }
                width: 196; height: menuCol.implicitHeight + 10
                radius: 12
                color: "#fa2c2f33"
                border { width: 0.5; color: "#33ffffff" }
                Column {
                    id: menuCol
                    anchors { fill: parent; margins: 5 }
                    Repeater {
                        model: [
                            { t: "Basic", on: true, enabled: true },
                            { t: "Scientific", on: false, enabled: false },
                            { t: "Programmer", on: false, enabled: false },
                            { t: "-" },
                            { t: "Thousands Separators", on: calc.separators, enabled: true, toggle: true },
                        ]
                        delegate: Item {
                            required property var modelData
                            width: menuCol.width
                            height: modelData.t === "-" ? 11 : 24
                            Rectangle {
                                visible: modelData.t === "-"
                                anchors.centerIn: parent
                                width: parent.width - 20; height: 1
                                color: "#26ffffff"
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 7
                                visible: modelData.t !== "-" && modelData.enabled && rowHover.hovered
                                color: Theme.accent
                            }
                            Text {
                                visible: modelData.t !== "-" && !!modelData.on
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                text: "✓"; color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Text {
                                visible: modelData.t !== "-"
                                x: 24; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.t
                                color: modelData.enabled ? "#ffffff" : "#66ffffff"
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }
                            HoverHandler { id: rowHover }
                            TapHandler {
                                enabled: modelData.t !== "-" && !!modelData.enabled
                                onTapped: {
                                    if (modelData.toggle) calc.separators = !calc.separators
                                    modeMenu.visible = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
