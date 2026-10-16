//@ pragma AppId org.goldengate.Calculator
// Calculator, as on the Mac (macOS 15+): Basic, Scientific and Programmer,
// unit conversion in Basic and Scientific, and a history sidebar. A small dark
// window that grows for the mode you choose. Keyboard: digits, + - * / ^ % . ,
// ( ), Enter/=, Backspace, Escape (clear), Ctrl+C copies the result; in
// Programmer also a–f, & | << >>.
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
        // Basic: 4 columns of keys; Scientific adds 6; Programmer is 7 with its bits.
        readonly property int keysWide: calc.mode === "scientific" ? 10 : calc.mode === "programmer" ? 7 : 4
        readonly property int keysHigh: calc.mode === "programmer" ? 6 : 5
        readonly property real gridW: keysWide * 47 + (keysWide - 1) * 6
        readonly property real gridH: keysHigh * 47 + (keysHigh - 1) * 7
        readonly property real displayH: 92 + (calc.mode === "programmer" ? 96 : 0) + (calc.converting ? 52 : 0)
        readonly property size fixed: Qt.size(gridW + 28 + (calc.historyOpen ? 208 : 0), 52 + displayH + gridH + 20)
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
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
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
                        width: parent.width - 20
                        Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft; text: calc.sep(modelData.expr); color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                        Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft; text: calc.sep(modelData.result); color: "#ffffff"; font { family: Theme.fontUi; pixelSize: Theme.fs(16); weight: Font.Medium } }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: calc.recall(modelData) }
                }
            }
        ]

        Item {
            id: calc
            objectName: "calculator"
            anchors.fill: parent
            focus: true

            property string mode: Quickshell.env("GG_CALC_MODE") || "basic"     // basic | scientific | programmer
            property bool convert: Quickshell.env("GG_CALC_CONVERT") === "1"
            readonly property bool converting: convert && mode !== "programmer"
            property bool historyOpen: false
            property bool separators: true
            property var history: []

            // ---------------------------------------------- Basic and Scientific
            property var tokens: []          // numbers, operators and parentheses
            property string current: ""      // the number being typed (or a function's result)
            property bool computed: false    // current holds a computed number, not typing
            property bool done: false        // just pressed =
            property real result: 0
            property bool second: false      // 2nd: the inverse functions
            property bool rad: false
            property real memory: 0
            readonly property int digits: mode === "scientific" ? 12 : 9
            readonly property int openParens: {
                let n = 0
                for (const t of tokens) n += t === "(" ? 1 : t === ")" ? -1 : 0
                return n
            }

            readonly property string pendingOp: current === "" && tokens.length && typeof tokens[tokens.length - 1] === "string"
                && tokens[tokens.length - 1] !== ")" && tokens[tokens.length - 1] !== "(" ? tokens[tokens.length - 1] : ""
            function sep(s) { return separators ? s : String(s).replace(/,/g, "") }
            function value() {
                if (current !== "" && current !== "-") return Number(current)
                if (done) return result
                return tokens.length ? Engine.evaluate(tokens) : 0
            }
            readonly property string exprText: sep(Engine.expression(tokens, computed ? Engine.format(Number(current), digits) : current, digits))
            readonly property string bigText: sep(done ? Engine.format(result, digits)
                                            : current !== "" ? (computed ? Engine.format(Number(current), digits) : Engine.groupTyped(current))
                                            : tokens.length ? Engine.format(Engine.evaluate(tokens), digits) : "0")

            function fresh() { if (done) { tokens = []; current = ""; done = false } if (computed) { current = ""; computed = false } }
            function digit(d) {
                fresh()
                if (current.replace(/[-.]/g, "").length >= (mode === "scientific" ? 15 : 9)) return
                current = current === "0" ? d : current === "-0" ? "-" + d : current + d
            }
            function dot() {
                fresh()
                if (current.indexOf(".") < 0) current = (current === "" || current === "-" ? current + "0" : current) + "."
            }
            function setValue(v) { current = String(v); computed = true; done = false }
            function op(o) {
                if (done) { tokens = [result]; done = false }
                else if (current !== "" && current !== "-") { tokens = tokens.concat([Number(current)]); current = ""; computed = false }
                else if (pendingOp) { tokens = tokens.slice(0, -1) }
                if (!tokens.length || tokens[tokens.length - 1] === "(") tokens = tokens.concat([0])
                tokens = tokens.concat([o])
            }
            function open() {
                if (done) { tokens = []; done = false }
                if (current !== "" && current !== "-") { tokens = tokens.concat([Number(current), "*"]); current = ""; computed = false }
                tokens = tokens.concat(["("])
            }
            function close() {
                if (openParens <= 0) return
                if (current !== "" && current !== "-") { tokens = tokens.concat([Number(current)]); current = ""; computed = false }
                else if (pendingOp) tokens = tokens.slice(0, -1)
                tokens = tokens.concat([")"])
            }
            function equals() {
                let t = tokens
                if (current !== "" && current !== "-") t = t.concat([Number(current)])
                if (!t.length) return
                while (t.length && typeof t[t.length - 1] === "string" && t[t.length - 1] !== ")") t = t.slice(0, -1)
                for (let i = 0; i < openParens; i++) t = t.concat([")"])
                if (t.length < 3 && !done) { result = Engine.evaluate(t); done = true; tokens = t; current = ""; computed = false; return }
                result = Engine.evaluate(t)
                remember(Engine.expression(t, "", digits), Engine.format(result, digits), result)
                tokens = t; current = ""; computed = false; done = true
            }
            function remember(expr, shown, v) {
                history = [{ expr: expr, result: shown, value: v, mode: mode }].concat(history).slice(0, 50)
            }
            function clear() {
                if (current !== "" && !done) { current = ""; computed = false }
                else { tokens = []; current = ""; computed = false; done = false; result = 0 }
            }
            function backspace() {
                if (done || computed) return
                current = current.slice(0, -1)
                if (current === "-") current = ""
            }
            function percent() { fn("percent") }
            function sign() {
                if (done) { result = -result; return }
                if (computed) { current = String(-Number(current)); return }
                current = current.startsWith("-") ? current.slice(1) : "-" + (current || "0")
            }
            // A function of the number on the display, as the Mac's Scientific keys.
            function fn(name) {
                const v = Engine.unary(name, value(), rad)
                if (done) { tokens = []; done = false }
                setValue(v)
            }
            function constant(v) { if (done) { tokens = []; done = false } setValue(v) }
            function memoryKey(k) {
                if (k === "mc") memory = 0
                else if (k === "m+") memory += value()
                else if (k === "m-") memory -= value()
                else if (k === "mr") constant(memory)
            }
            function recall(entry) {
                if (entry.mode === "programmer") { if (mode === "programmer") { ptokens = []; pcurrent = ""; presult = entry.value; pdone = true } return }
                if (mode === "programmer") return
                tokens = []; current = ""; computed = false; result = entry.value; done = true
            }

            // ------------------------------------------------------ Programmer
            property int base: 10
            property var ptokens: []
            property string pcurrent: ""
            property var presult: [0, 0, 0, 0]
            property bool pdone: false
            property bool perror: false
            readonly property var pvalue: pcurrent !== "" ? Engine.parseInt64(pcurrent, base) : pdone ? presult
                : ptokens.length ? (Engine.pevaluate(ptokens) || [0, 0, 0, 0]) : [0, 0, 0, 0]
            readonly property string pPending: pcurrent === "" && ptokens.length && !Engine.isU64(ptokens[ptokens.length - 1]) ? ptokens[ptokens.length - 1] : ""
            function plain(v) { return Engine.toBase(v, base).replace(/[ ,]/g, "") }
            function pdigit(d) {
                if (pdone) { ptokens = []; pcurrent = ""; pdone = false; perror = false }
                if ("0123456789ABCDEF".indexOf(d.charAt(0)) >= base) return
                const next = (pcurrent === "0" ? "" : pcurrent) + d
                // Never more than 64 bits.
                if (Engine.toBase(Engine.parseInt64(next, base), base).replace(/[ ,]/g, "") !== next.replace(/^0+(?=.)/, "")) return
                pcurrent = next
            }
            function pop(o) {
                if (pdone) { ptokens = [presult]; pdone = false }
                else if (pcurrent !== "") { ptokens = ptokens.concat([Engine.parseInt64(pcurrent, base)]); pcurrent = "" }
                else if (pPending) ptokens = ptokens.slice(0, -1)
                if (!ptokens.length) ptokens = [[0, 0, 0, 0]]
                ptokens = ptokens.concat([o])
            }
            function pequals() {
                let t = ptokens
                if (pcurrent !== "") t = t.concat([Engine.parseInt64(pcurrent, base)])
                if (!t.length) return
                const r = Engine.pevaluate(t)
                perror = r === null
                presult = r || [0, 0, 0, 0]
                if (t.length > 1 && !perror) remember(Engine.pexpression(t, "", base), Engine.toBase(presult, base), presult)
                ptokens = t; pcurrent = ""; pdone = true
            }
            function punary(name) {
                const v = Engine.punary(name, pvalue)
                if (pdone) { ptokens = []; pdone = false }
                pcurrent = plain(v)
            }
            function setBase(b) {
                const v = pvalue
                base = b
                if (pcurrent !== "") pcurrent = plain(v)
            }
            function toggleBit(i) {
                const v = Engine.toggleBit(pvalue, i)
                if (pdone) { ptokens = []; pdone = false }
                pcurrent = plain(v)
            }
            function pclear() {
                if (pcurrent !== "" && !pdone) pcurrent = ""
                else { ptokens = []; pcurrent = ""; pdone = false; perror = false; presult = [0, 0, 0, 0] }
            }
            function pbackspace() { if (!pdone) pcurrent = pcurrent.slice(0, -1) }

            // ------------------------------------------------------ Conversion
            property string category: "Length"
            property string fromUnit: "Kilometers"
            property string toUnit: "Miles"
            readonly property real converted: Engine.convert(value(), category, fromUnit, toUnit)
            function setCategory(c) {
                category = c
                const u = Engine.units(c)
                fromUnit = u[0]; toUnit = u[Math.min(1, u.length - 1)]
            }
            function swapUnits() { const f = fromUnit; fromUnit = toUnit; toUnit = f }

            Keys.onPressed: (e) => {
                const t = e.text
                if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_C) {
                    Quickshell.clipboardText = mode === "programmer" ? plain(pvalue) : bigText.replace(/,/g, ""); return
                }
                if (mode === "programmer") {
                    if (/^[0-9a-fA-F]$/.test(t)) pdigit(t.toUpperCase())
                    else if ("+-*/".includes(t) && t !== "") pop(t)
                    else if (t === "&") pop("and")
                    else if (t === "|") pop("or")
                    else if (t === "^") pop("xor")
                    else if (t === "<") pop("shl")
                    else if (t === ">") pop("shr")
                    else if (t === "%") pop("mod")
                    else if (t === "=" || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pequals()
                    else if (e.key === Qt.Key_Backspace) pbackspace()
                    else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Delete) pclear()
                    else return
                } else {
                    if (/^[0-9]$/.test(t)) digit(t)
                    else if (t === "." || t === ",") dot()
                    else if ("+-*/".includes(t) && t !== "") op(t)
                    else if (t === "^" && mode === "scientific") op("^")
                    else if (t === "(" && mode === "scientific") open()
                    else if (t === ")" && mode === "scientific") close()
                    else if (t === "%") percent()
                    else if (t === "=" || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) equals()
                    else if (e.key === Qt.Key_Backspace) backspace()
                    else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Delete) clear()
                    else return
                }
                e.accepted = true
            }

            // ---------------------------------------------------- the display
            Column {
                id: display
                anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; top: parent.top; topMargin: 4 }
                spacing: -2
                Item {
                    width: parent.width; height: 22
                    Text {
                        visible: calc.mode === "scientific" && calc.rad
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Rad"
                        color: "#9a9c9d"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        text: calc.mode === "programmer" ? Engine.pexpression(calc.ptokens, calc.pcurrent, calc.base) : calc.exprText
                        color: "#9a9c9d"
                        elide: Text.ElideLeft
                        font { family: Theme.fontUi; pixelSize: Theme.fs(17) }
                    }
                }
                // The number, with its unit when converting.
                Item {
                    width: parent.width; height: 52
                    UnitButton {
                        id: fromButton
                        visible: calc.converting
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        popupParent: calc
                        units: Engine.units(calc.category)
                        unit: calc.fromUnit
                        onChosen: (u) => calc.fromUnit = u
                    }
                    Text {
                        objectName: "calcDisplay"
                        anchors { left: fromButton.visible ? fromButton.right : parent.left; right: parent.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        height: 48
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        text: calc.mode === "programmer" ? (calc.perror ? "Error" : Engine.toBase(calc.pvalue, calc.base)) : calc.bigText
                        color: "#ffffff"
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 14
                        font { family: Theme.fontUi; pixelSize: 40; weight: Font.Light }
                    }
                }
                // Converting: the same number in another unit.
                Item {
                    visible: calc.converting
                    width: parent.width; height: 52
                    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: "#33ffffff" }
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        UnitButton {
                            popupParent: calc
                            units: Engine.categories()
                            unit: calc.category
                            onChosen: (c) => calc.setCategory(c)
                            muted: true
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: swapTap.containsMouse ? "#33ffffff" : "#1fffffff"
                            Text { anchors.centerIn: parent; text: "⇅"; color: "#ffffff"; font.pixelSize: Theme.fs(13) }
                            MouseArea { id: swapTap; anchors.fill: parent; hoverEnabled: true; onClicked: calc.swapUnits() }
                        }
                        UnitButton {
                            id: toButton
                            popupParent: calc
                            units: Engine.units(calc.category)
                            unit: calc.toUnit
                            onChosen: (u) => calc.toUnit = u
                        }
                    }
                    Text {
                        objectName: "calcConverted"
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: parent.width * 0.42
                        horizontalAlignment: Text.AlignRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 12
                        text: calc.sep(Engine.format(calc.converted, calc.digits))
                        color: "#ffffff"
                        font { family: Theme.fontUi; pixelSize: 26; weight: Font.Light }
                    }
                }
                // Programmer: the base, and all 64 bits, each one a switch.
                Column {
                    visible: calc.mode === "programmer"
                    width: parent.width
                    spacing: 6
                    topPadding: 4
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Repeater {
                            model: [[8, "Octal"], [10, "Decimal"], [16, "Hex"], [2, "Binary"]]
                            Rectangle {
                                required property var modelData
                                width: 72; height: 22; radius: 11
                                color: calc.base === modelData[0] ? "#ff9500" : "#33ffffff"
                                Text { anchors.centerIn: parent; text: parent.modelData[1]; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium } }
                                MouseArea { anchors.fill: parent; onClicked: calc.setBase(parent.modelData[0]) }
                            }
                        }
                    }
                    Repeater {
                        model: 4
                        Row {
                            required property int index
                            readonly property int highBit: 63 - index * 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 0
                            Text { width: 22; text: parent.highBit; color: "#6d7174"; font { family: "SF Mono"; pixelSize: Theme.fs(9) } anchors.verticalCenter: parent.verticalCenter }
                            Repeater {
                                model: 16
                                Item {
                                    required property int index
                                    readonly property int n: parent.highBit - index
                                    width: (index % 4 === 3 ? 21 : 15); height: 14
                                    Text {
                                        x: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Engine.bit(calc.pvalue, parent.n)
                                        color: Engine.bit(calc.pvalue, parent.n) ? "#ffffff" : "#6d7174"
                                        font { family: "SF Mono"; pixelSize: Theme.fs(12) }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: calc.toggleBit(parent.n) }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------ the keys
            Item {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
                width: win.gridW; height: win.gridH

                // Basic, and the right of Scientific.
                Grid {
                    visible: calc.mode !== "programmer"
                    anchors.right: parent.right
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

                // Scientific's six columns, as on the Mac; 2nd turns them to their inverses.
                Grid {
                    visible: calc.mode === "scientific"
                    anchors.left: parent.left
                    columns: 6
                    columnSpacing: 6; rowSpacing: 7
                    Repeater {
                        model: [
                            { l: "(", f: () => calc.open() }, { l: ")", f: () => calc.close() },
                            { l: "mc", f: () => calc.memoryKey("mc") }, { l: "m+", f: () => calc.memoryKey("m+") },
                            { l: "m−", f: () => calc.memoryKey("m-") }, { l: "mr", f: () => calc.memoryKey("mr"), lit: calc.memory !== 0 },
                            { l: "2nd", f: () => calc.second = !calc.second, lit: calc.second },
                            { l: "x²", f: () => calc.fn("x2") }, { l: "x³", f: () => calc.fn("x3") },
                            { l: "xʸ", f: () => calc.op("^"), sel: "^" },
                            calc.second ? { l: "yˣ", f: () => calc.op("rpow"), sel: "rpow" } : { l: "eˣ", f: () => calc.fn("exp") },
                            calc.second ? { l: "2ˣ", f: () => calc.fn("exp2") } : { l: "10ˣ", f: () => calc.fn("exp10") },
                            { l: "¹/x", f: () => calc.fn("recip") }, { l: "²√x", f: () => calc.fn("sqrt") },
                            { l: "³√x", f: () => calc.fn("cbrt") }, { l: "ʸ√x", f: () => calc.op("root"), sel: "root" },
                            calc.second ? { l: "logᵧ", f: () => calc.op("logy"), sel: "logy" } : { l: "ln", f: () => calc.fn("ln") },
                            calc.second ? { l: "log₂", f: () => calc.fn("log2") } : { l: "log₁₀", f: () => calc.fn("log10") },
                            { l: "x!", f: () => calc.fn("fact") },
                            { l: calc.second ? "sin⁻¹" : "sin", f: () => calc.fn(calc.second ? "asin" : "sin") },
                            { l: calc.second ? "cos⁻¹" : "cos", f: () => calc.fn(calc.second ? "acos" : "cos") },
                            { l: calc.second ? "tan⁻¹" : "tan", f: () => calc.fn(calc.second ? "atan" : "tan") },
                            { l: "e", f: () => calc.constant(Math.E) }, { l: "EE", f: () => calc.op("EE"), sel: "EE" },
                            { l: calc.rad ? "Deg" : "Rad", f: () => calc.rad = !calc.rad },
                            { l: calc.second ? "sinh⁻¹" : "sinh", f: () => calc.fn(calc.second ? "asinh" : "sinh") },
                            { l: calc.second ? "cosh⁻¹" : "cosh", f: () => calc.fn(calc.second ? "acosh" : "cosh") },
                            { l: calc.second ? "tanh⁻¹" : "tanh", f: () => calc.fn(calc.second ? "atanh" : "tanh") },
                            { l: "π", f: () => calc.constant(Math.PI) }, { l: "Rand", f: () => calc.constant(Math.random()) }
                        ]
                        CalcKey {
                            required property var modelData
                            kind: "function"
                            compact: true
                            label: modelData.l
                            lit: !!modelData.lit || (!!modelData.sel && calc.pendingOp === modelData.sel)
                            onPressed: modelData.f()
                        }
                    }
                }

                // Programmer: bitwise operations, the hex and decimal digits, arithmetic.
                Grid {
                    visible: calc.mode === "programmer"
                    anchors.fill: parent
                    columns: 7
                    columnSpacing: 6; rowSpacing: 7
                    Repeater {
                        model: [
                            { l: "AND", o: "and" }, { l: "OR", o: "or" }, { d: "D" }, { d: "E" }, { d: "F" },
                            { l: calc.pcurrent !== "" && !calc.pdone ? "C" : "AC", f: () => calc.pclear() }, { del: true },
                            { l: "NOR", o: "nor" }, { l: "XOR", o: "xor" }, { d: "A" }, { d: "B" }, { d: "C" },
                            { l: "RoL", u: "rol" }, { l: "RoR", u: "ror" },
                            { l: "<<", u: "shl1" }, { l: ">>", u: "shr1" }, { d: "7" }, { d: "8" }, { d: "9" },
                            { l: "2's", u: "twos" }, { l: "1's", u: "ones" },
                            { l: "X<<Y", o: "shl" }, { l: "X>>Y", o: "shr" }, { d: "4" }, { d: "5" }, { d: "6" },
                            { l: "÷", o: "/", op: true }, { l: "×", o: "*", op: true },
                            { l: "flip₈", u: "flipb" }, { l: "flip₁₆", u: "flipw" }, { d: "1" }, { d: "2" }, { d: "3" },
                            { l: "−", o: "-", op: true }, { l: "+", o: "+", op: true },
                            { l: "FF", d: "FF" }, { l: "00", d: "00" }, { d: "0" }, { l: "mod", o: "mod" },
                            { l: "", spacer: true }, { l: "", spacer: true }, { l: "=", eq: true, op: true }
                        ]
                        CalcKey {
                            required property var modelData
                            // A Grid skips hidden items: blanks are see-through instead.
                            opacity: modelData.spacer ? 0 : (enabled ? 1 : 0.35)
                            kind: modelData.op ? "operator" : modelData.d !== undefined ? "digit" : "function"
                            compact: !modelData.op && modelData.d === undefined
                            label: modelData.l !== undefined ? modelData.l : (modelData.d ?? "")
                            deleteGlyph: !!modelData.del
                            selected: !!modelData.o && calc.pPending === modelData.o
                            enabled: modelData.spacer ? false : modelData.d === undefined ? true
                                : modelData.d === "FF" ? calc.base === 16
                                : "0123456789ABCDEF".indexOf(modelData.d.charAt(0)) < calc.base
                            onPressed: {
                                const m = modelData
                                if (m.del) calc.pbackspace()
                                else if (m.f) m.f()
                                else if (m.eq) calc.pequals()
                                else if (m.o) calc.pop(m.o)
                                else if (m.u) calc.punary(m.u)
                                else if (m.d !== undefined) calc.pdigit(m.d)
                            }
                        }
                    }
                }
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
                            { t: "Basic", on: calc.mode === "basic", act: () => calc.mode = "basic" },
                            { t: "Scientific", on: calc.mode === "scientific", act: () => calc.mode = "scientific" },
                            { t: "Programmer", on: calc.mode === "programmer", act: () => calc.mode = "programmer" },
                            { t: "-" },
                            { t: "Convert", on: calc.convert, off: calc.mode === "programmer", act: () => calc.convert = !calc.convert },
                            { t: "Thousands Separators", on: calc.separators, act: () => calc.separators = !calc.separators },
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
                                visible: modelData.t !== "-" && !modelData.off && rowHover.hovered
                                color: Theme.accent
                            }
                            Text {
                                visible: modelData.t !== "-" && !!modelData.on
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                text: "✓"; color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                            }
                            Text {
                                visible: modelData.t !== "-"
                                x: 24; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.t
                                color: modelData.off ? "#66ffffff" : "#ffffff"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                            }
                            HoverHandler { id: rowHover }
                            TapHandler {
                                enabled: modelData.t !== "-" && !modelData.off
                                onTapped: { modelData.act(); modeMenu.visible = false }
                            }
                        }
                    }
                }
            }
        }
    }

    // A unit (or category) with a menu of the others: tap to choose.
    component UnitButton: Rectangle {
        id: ub
        property Item popupParent: null       // where the menu opens, above the keys
        property var units: []
        property string unit: ""
        property bool muted: false
        signal chosen(string unit)
        width: Math.min(ubText.implicitWidth + 22, 120)
        height: 24; radius: 7
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: ubTap.containsMouse || list.visible ? "#33ffffff" : muted ? "#14ffffff" : "#24ffffff"
        Text {
            id: ubText
            anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: ub.unit
            elide: Text.ElideRight
            color: ub.muted ? "#b0b3b5" : "#ffffff"
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium }
        }
        Text { anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter } text: "⌄"; color: "#9a9c9d"; font.pixelSize: Theme.fs(10) }
        MouseArea {
            id: ubTap; anchors.fill: parent; hoverEnabled: true
            onClicked: {
                if (!list.visible && ub.popupParent) {
                    const p = ub.mapToItem(ub.popupParent, 0, ub.height + 4)
                    list.x = Math.min(p.x, ub.popupParent.width - list.width - 6); list.y = p.y
                }
                list.visible = !list.visible
            }
        }
        // The choices, in a dark menu below.
        Rectangle {
            id: list
            visible: false
            parent: ub.popupParent ?? ub
            z: 100
            width: 170; height: Math.min(260, col.implicitHeight + 10)
            radius: 10
            color: "#fa2c2f33"
            border { width: 0.5; color: "#33ffffff" }
            Flickable {
                anchors { fill: parent; margins: 5 }
                contentHeight: col.implicitHeight
                clip: true
                Column {
                    id: col
                    width: parent.width
                    Repeater {
                        model: ub.units
                        Rectangle {
                            required property string modelData
                            width: col.width; height: 22; radius: 6
                            color: rowTap.containsMouse ? Theme.accent : "transparent"
                            Text {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                text: (parent.modelData === ub.unit ? "✓ " : "   ") + parent.modelData
                                color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                            MouseArea { id: rowTap; anchors.fill: parent; hoverEnabled: true; onClicked: { ub.chosen(parent.modelData); list.visible = false } }
                        }
                    }
                }
            }
        }
    }
}
