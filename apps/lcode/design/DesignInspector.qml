// The App Designer's inspectors, in the window's trailing sidebar as in Xcode:
// for a component, Attributes (what it shows, its font, colours, fill,
// corners, border, shadow and effects), Layout (frame, alignment, padding,
// offset) and Actions (what happens when it's clicked or changed); for the
// app, a screen, a variable or a named colour, their settings.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/catalog.js" as Catalog
import "../../lib/kit/kit.js" as K
import "../design.js" as Design

Flickable {
    id: insp
    property var designer: null
    property Item overlay: null
    property var backend: null
    property var symbolNames: []
    property int tab: 0
    clip: true
    contentHeight: column.height + 30
    boundsBehavior: Flickable.StopAtBounds

    readonly property var doc: designer ? designer.doc : null
    readonly property var sel: designer ? designer.selection : ({ kind: "app", id: "" })
    readonly property var hit: doc && sel.kind === "node" ? Design.find(doc, sel.id) : null
    readonly property var node: hit ? hit.node : null
    readonly property var info: node ? Catalog.component(node.type) : null
    readonly property var props: node ? (node.props || {}) : ({})
    readonly property var parentNode: hit ? hit.parent : null
    readonly property var screen: doc && sel.kind === "screen" ? Design.screenById(doc, sel.id) : null
    readonly property var variable: doc && sel.kind === "variable" ? Design.variable(doc, sel.id) : null
    readonly property var namedColor: doc && sel.kind === "color" ? (doc.colors.find((c) => c.name === sel.id) || null) : null
    readonly property bool plain: !!(info && info.plain)
    // Switching from a three-tab component to one with only Attributes and
    // Layout must not leave the inspector on a hidden Actions page.
    onPlainChanged: if (plain && tab > 1) tab = 1
    // A new selection or inspector tab should start at its heading, not at
    // the previous selection's scroll offset (which can look like a blank pane).
    onSelChanged: contentY = 0
    onTabChanged: contentY = 0

    Component.onCompleted: if (backend) backend.call("symbols", {}, (r) => { if (r.ok) insp.symbolNames = r.symbols })

    function val(key, fallback) {
        if (props[key] !== undefined) return props[key]
        if (info && info.defaults && info.defaults[key] !== undefined) return info.defaults[key]
        return fallback
    }
    function set(key, value) { if (node) designer.setProps(node.id, { [key]: value }) }
    function variablesOf(type) { return doc ? doc.state.filter((v) => !type || v.type === type) : [] }

    // Shared pickers, opened from any field.
    property var colorCallback: null
    property var symbolCallback: null
    property var imageCallback: null
    function pickColor(from, current, cb, customOnly) {
        colorCallback = cb
        colorPicker.parent = overlay
        colorPicker.customOnly = !!customOnly
        colorPicker.show(from, 0, from.height + 4, current)
    }
    function pickSymbol(from, current, cb) {
        symbolCallback = cb
        symbolPicker.parent = overlay
        symbolPicker.show(from, 0, from.height + 4, current)
    }
    function pickImage(from, current, cb) {
        imageCallback = cb
        imagePicker.parent = overlay
        imagePicker.root = designer.path.substring(0, designer.path.lastIndexOf("/"))
        imagePicker.show(from, 0, from.height + 4, current)
    }
    function colorPickerEnv() { return colorPicker.env }
    ColorPicker { id: colorPicker; doc: insp.doc; onPicked: (v) => { if (insp.colorCallback) insp.colorCallback(v) } }
    SymbolPicker { id: symbolPicker; names: insp.symbolNames; onPicked: (v) => { if (insp.symbolCallback) insp.symbolCallback(v) } }
    ImagePicker { id: imagePicker; backend: insp.backend; onPicked: (v) => { if (insp.imageCallback) insp.imageCallback(v) } }

    // ------------------------------------------------------------ pieces
    component Section: Column {
        property string title
        default property alias items: body.data
        width: parent ? parent.width : 0
        spacing: 6
        Rectangle { width: parent.width; height: 1; color: Theme.separator }
        Text {
            topPadding: 4
            text: parent.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
        }
        Column { id: body; width: parent.width; spacing: 7 }
    }

    component FieldRow: Item {
        property string label
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(24, slot.childrenRect.height)
        Text {
            width: 82
            height: 24
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: parent.label
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        Item { id: slot; x: 90; width: parent.width - 90; height: childrenRect.height }
    }

    // Text, committed on Return or when you leave the field. Variables can be
    // put in with the { } menu.
    component TextValue: Item {
        id: tv
        property string value
        property bool templates: false
        property string placeholder: ""
        signal commit(string text)
        width: parent ? parent.width : 0
        height: 24
        TextField {
            id: field
            width: parent.width - (tv.templates ? 26 : 0)
            height: 24
            text: tv.value
            placeholder: tv.placeholder
            onAccepted: if (text !== tv.value) tv.commit(text)
            input.onActiveFocusChanged: if (!input.activeFocus && text !== tv.value) tv.commit(text)
        }
        ToolbarButton {
            id: varButton
            visible: tv.templates
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            height: 22
            text: "{ }"
            Accessible.name: "Insert a variable"
            onClicked: insp.designer.menu.popup(varButton, 0, varButton.height + 4,
                [{ header: "Insert Variable" }].concat(insp.variablesOf("").length
                    ? insp.variablesOf("").map((v) => ({ text: v.name, action: () => {
                        const pos = field.input.cursorPosition
                        const t = field.text.slice(0, pos) + "{" + v.name + "}" + field.text.slice(pos)
                        field.text = t
                        tv.commit(t) } }))
                    : [{ text: "No Variables Yet", enabled: false }]))
        }
    }

    component NumberValue: Row {
        id: nv
        property real value: 0
        property real minimum: -100000
        property real maximum: 100000
        property real step: 1
        property string placeholder: ""
        property bool empty: false            // show the placeholder instead of the value
        signal commit(real value)
        signal clear()
        width: parent ? parent.width : 0
        spacing: 2
        function fmt(v) { return K.str(v) }
        function push(v) { nv.commit(Math.max(minimum, Math.min(maximum, Math.round(v * 1000) / 1000))) }
        TextField {
            id: numField
            width: parent.width - 18
            height: 24
            text: nv.empty ? "" : nv.fmt(nv.value)
            placeholder: nv.placeholder
            onAccepted: apply()
            input.onActiveFocusChanged: if (!input.activeFocus) apply()
            function apply() {
                const t = text.trim()
                if (t === "") { if (!nv.empty) nv.clear(); return }
                const n = parseFloat(t)
                if (!isNaN(n) && (nv.empty || n !== nv.value)) nv.push(n)
            }
        }
        Column {
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: [1, -1]
                delegate: Rectangle {
                    required property int modelData
                    width: 16; height: 12; radius: 3
                    color: stepHover.hovered ? Theme.fill : "transparent"
                    Text { anchors.centerIn: parent; text: parent.modelData > 0 ? "▴" : "▾"; color: Theme.secondaryLabel; font.pixelSize: Theme.fs(10) }
                    HoverHandler { id: stepHover }
                    TapHandler { onTapped: nv.push((nv.empty ? 0 : nv.value) + parent.modelData * nv.step) }
                }
            }
        }
    }

    component ColorValue: Rectangle {
        id: cv
        property string value
        property bool customOnly: false
        property string placeholder: "Default"
        signal commit(string value)
        width: parent ? parent.width : 0
        height: 24
        radius: 6
        color: Theme.dark ? "#1affffff" : "#ffffff"
        border { width: 0.5; color: Theme.separator }
        Rectangle {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 16; radius: 4
            color: cv.value ? K.color(cv.value, colorPicker.env) : "transparent"
            border { width: 0.5; color: "#33000000" }
        }
        Text {
            x: 40
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 46
            elide: Text.ElideRight
            text: cv.value || cv.placeholder
            color: cv.value ? Theme.label : Theme.tertiaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        TapHandler { onTapped: insp.pickColor(cv, cv.value, (v) => cv.commit(v), cv.customOnly) }
    }

    component SymbolValue: Rectangle {
        id: sv
        property string value
        signal commit(string value)
        width: parent ? parent.width : 0
        height: 24
        radius: 6
        color: Theme.dark ? "#1affffff" : "#ffffff"
        border { width: 0.5; color: Theme.separator }
        Symbol { visible: !!sv.value; x: 6; anchors.verticalCenter: parent.verticalCenter; name: sv.value; size: 14; tone: "accent" }
        Text {
            x: 26
            anchors.verticalCenter: parent.verticalCenter
            text: sv.value || "None"
            color: sv.value ? Theme.label : Theme.tertiaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        TapHandler { onTapped: insp.pickSymbol(sv, sv.value, (v) => sv.commit(v)) }
    }

    component Choice: PopUpButton {
        property var values: []
        property var titles: []
        property var value
        signal commit(var value)
        options: titles.length ? titles : values.map((v) => String(v))
        current: Math.max(0, values.indexOf(value))
        menuParent: insp.overlay
        onPicked: (i) => commit(values[i])
    }

    component VarChoice: Choice {
        property string type: ""
        property string noneTitle: "None"
        property bool offerNew: true
        readonly property var vars: insp.variablesOf(type)
        values: [""].concat(vars.map((v) => v.name), offerNew ? ["@new"] : [])
        titles: [noneTitle].concat(vars.map((v) => v.name), offerNew ? ["New " + ({ text: "Text", number: "Number", bool: "On/Off", list: "List" }[type] || "") + " Variable…"] : [])
    }

    // A frame dimension: Auto (its content), Fill (all the space) or a number.
    component FrameValue: Row {
        id: fv
        property var value: "auto"
        signal commit(var value)
        width: parent ? parent.width : 0
        spacing: 6
        Choice {
            id: modeChoice
            width: 72
            values: ["auto", "fill", "fixed"]
            titles: ["Auto", "Fill", "Fixed"]
            value: typeof fv.value === "number" ? "fixed" : (fv.value || "auto")
            onCommit: (v) => fv.commit(v === "fixed" ? 200 : v)
        }
        NumberValue {
            visible: typeof fv.value === "number"
            width: parent.width - 78
            value: typeof fv.value === "number" ? fv.value : 0
            minimum: 0
            maximum: 4000
            onCommit: (v) => fv.commit(v)
        }
    }

    // ---------------------------------------------------------- the column
    Column {
        id: column
        x: 6
        width: parent.width - 12
        spacing: 10

        // Title.
        Row {
            spacing: 8
            topPadding: 2
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                tone: "accent"
                name: insp.node ? Catalog.symbolFor(insp.node.type) : insp.sel.kind === "screen" ? (insp.screen ? insp.screen.symbol || "doc" : "doc")
                    : insp.sel.kind === "variable" ? "curlybraces" : insp.sel.kind === "color" ? "palette" : "appicon"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: insp.node ? Catalog.title(insp.node.type) : insp.sel.kind === "screen" ? "Screen" : insp.sel.kind === "variable" ? "Variable"
                    : insp.sel.kind === "color" ? "Color" : "App"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.Bold }
            }
        }
        Text {
            visible: !!insp.info
            width: parent.width
            wrapMode: Text.Wrap
            text: insp.info ? insp.info.detail : ""
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }

        // Attributes / Layout / Actions.
        Segmented {
            visible: !!insp.node
            anchors.horizontalCenter: parent.horizontalCenter
            options: insp.plain ? ["Attributes", "Layout"] : ["Attributes", "Layout", "Actions"]
            current: Math.min(insp.tab, options.length - 1)
            onPicked: (i) => insp.tab = i
        }

        // ================================================= Attributes
        Column {
            visible: !!insp.node && insp.tab === 0
            width: parent.width
            spacing: 10

            Section {
                title: insp.info ? insp.info.title : ""
                FieldRow {
                    label: "Name"
                    TextValue {
                        value: String(insp.props.nodeName || "")
                        placeholder: insp.node ? Design.label(Object.assign({}, insp.node, { props: Object.assign({}, insp.props, { nodeName: "" }) })) : ""
                        onCommit: (t) => insp.set("nodeName", t || null)
                    }
                }
                Repeater {
                    model: insp.info ? insp.info.fields : []
                    delegate: FieldRow {
                        id: fr
                        required property var modelData
                        readonly property var f: modelData
                        readonly property var current: insp.val(f.key, f.kind === "bool" ? false : f.kind === "number" ? 0 : "")
                        // A bound property comes from its variable.
                        visible: !(insp.info.bind && insp.info.bind.prop === f.key && insp.props.binding)
                        label: f.label
                        Loader {
                            width: parent.width
                            sourceComponent: ({ text: textC, multiline: multiC, number: numberC, bool: boolC, enum: enumC, segmented: enumC,
                                                color: colorC, symbol: symbolC, image: imageC, options: optionsC })[fr.f.kind] || textC
                            Component {
                                id: textC
                                TextValue {
                                    value: String(fr.current === undefined ? "" : fr.current)
                                    templates: (insp.info.templates || []).indexOf(fr.f.key) >= 0
                                    placeholder: fr.f.placeholder || ""
                                    onCommit: (t) => insp.set(fr.f.key, t)
                                }
                            }
                            Component {
                                id: multiC
                                Rectangle {
                                    width: parent ? parent.width : 0
                                    height: Math.max(48, area.contentHeight + 12)
                                    radius: 6
                                    color: Theme.dark ? "#1affffff" : "#ffffff"
                                    border { width: area.activeFocus ? 2 : 0.5; color: area.activeFocus ? Theme.accent : Theme.separator }
                                    TextArea {
                                        id: area
                                        x: 6; y: 6
                                        width: parent.width - 12
                                        text: String(fr.current || "")
                                        wrapMode: TextEdit.Wrap
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                        onActiveFocusChanged: if (!activeFocus && text !== String(fr.current || "")) insp.set(fr.f.key, text)
                                    }
                                }
                            }
                            Component {
                                id: numberC
                                NumberValue {
                                    value: +fr.current || 0
                                    empty: !!fr.f.placeholder && (fr.current === undefined || fr.current === "" || ((fr.current === 0 || fr.current === -1) && !insp.props[fr.f.key]))
                                    minimum: fr.f.min !== undefined ? fr.f.min : -100000
                                    maximum: fr.f.max !== undefined ? fr.f.max : 100000
                                    step: fr.f.step || 1
                                    placeholder: fr.f.placeholder || ""
                                    onCommit: (v) => insp.set(fr.f.key, v)
                                    onClear: insp.set(fr.f.key, null)
                                }
                            }
                            Component { id: boolC; Item { width: 40; height: 24; Switch { anchors.verticalCenter: parent.verticalCenter; checked: !!fr.current; onToggled: (c) => insp.set(fr.f.key, c) } } }
                            Component {
                                id: enumC
                                Choice {
                                    values: fr.f.options
                                    titles: fr.f.titles || fr.f.options.map((o) => o.charAt(0).toUpperCase() + o.slice(1))
                                    value: fr.current
                                    onCommit: (v) => insp.set(fr.f.key, v)
                                }
                            }
                            Component { id: colorC; ColorValue { value: String(fr.current || ""); onCommit: (v) => insp.set(fr.f.key, v || null) } }
                            Component { id: symbolC; SymbolValue { value: String(fr.current || ""); onCommit: (v) => insp.set(fr.f.key, v || null) } }
                            Component {
                                id: imageC
                                Rectangle {
                                    id: iw
                                    width: parent ? parent.width : 0
                                    height: 24
                                    radius: 6
                                    color: Theme.dark ? "#1affffff" : "#ffffff"
                                    border { width: 0.5; color: Theme.separator }
                                    Text {
                                        x: 8; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 16
                                        elide: Text.ElideMiddle
                                        text: fr.current ? String(fr.current) : "Choose…"
                                        color: fr.current ? Theme.label : Theme.tertiaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                    }
                                    TapHandler { onTapped: insp.pickImage(iw, String(fr.current || ""), (v) => insp.set(fr.f.key, v || null)) }
                                }
                            }
                            Component {
                                id: optionsC
                                OptionsEditor {
                                    values: Array.isArray(fr.current) ? fr.current : []
                                    checkable: fr.f.key === "items" && !!insp.val("checkable", false)
                                    onCommit: (list) => insp.set(fr.f.key, list)
                                }
                            }
                        }
                    }
                }
            }

            // Bound to a variable.
            Section {
                visible: !!(insp.info && insp.info.bind)
                title: "Variable"
                FieldRow {
                    label: insp.info && insp.info.bind ? ({ value: "Value", items: "Rows" })[insp.info.bind.prop] || "Value" : ""
                    VarChoice {
                        width: parent.width
                        type: insp.info && insp.info.bind ? insp.info.bind.type : ""
                        value: insp.props.binding || ""
                        onCommit: (v) => {
                            if (v === "@new") {
                                const r = Design.addVariable(insp.doc, type)
                                insp.designer.commit(Design.update(r.doc, insp.node.id, { binding: r.name }))
                            } else insp.set("binding", v || null)
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: insp.props.binding ? "Shows and changes “" + insp.props.binding + "”." : "Bind it to a variable to use its value elsewhere, with {name} in text or in actions."
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                }
            }

            // Font.
            Section {
                visible: !!(insp.info && (insp.info.font || insp.node.type === "Button"))
                title: "Font"
                FieldRow {
                    visible: insp.node && insp.node.type !== "Button"
                    label: "Style"
                    Choice {
                        width: parent.width
                        values: K.TEXT_STYLE_NAMES
                        titles: K.TEXT_STYLE_NAMES.map((n) => K.TEXT_STYLE_TITLES[n])
                        value: insp.val("textStyle", "body")
                        onCommit: (v) => insp.set("textStyle", v)
                    }
                }
                FieldRow {
                    label: "Family"
                    Choice {
                        width: parent.width
                        readonly property var installed: Qt.fontFamilies().filter((f) => !/^(Noto Sans [A-Z][a-z]+ |Noto Serif [A-Z])/.test(f)).slice(0, 120)
                        values: ["", "display", "rounded", "serif", "mono"].concat(installed)
                        titles: ["System", "Display", "Rounded", "Serif", "Monospaced"].concat(installed)
                        value: insp.val("fontFamily", "")
                        onCommit: (v) => insp.set("fontFamily", v || null)
                    }
                }
                FieldRow {
                    visible: insp.node && insp.node.type !== "Button"
                    label: "Size"
                    NumberValue {
                        value: +insp.val("fontSize", 0)
                        empty: !insp.props.fontSize
                        placeholder: String(K.fontSize(insp.val("textStyle", "body"), 0)) + " (style)"
                        minimum: 6; maximum: 400
                        onCommit: (v) => insp.set("fontSize", v)
                        onClear: insp.set("fontSize", null)
                    }
                }
                FieldRow {
                    label: "Weight"
                    Choice {
                        width: parent.width
                        values: [0, 100, 200, 300, 400, 500, 600, 700, 800, 900]
                        titles: ["Style Default", "Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
                        value: +insp.val("fontWeight", 0)
                        onCommit: (v) => insp.set("fontWeight", v || null)
                    }
                }
                FieldRow {
                    visible: insp.node && insp.node.type === "Text"
                    label: "Emphasis"
                    Row {
                        spacing: 4
                        Repeater {
                            model: [{ key: "italic", t: "I" }, { key: "underline", t: "U" }, { key: "strikethrough", t: "S" }]
                            delegate: ToolbarButton {
                                required property var modelData
                                text: modelData.t
                                checked: !!insp.val(modelData.key, false)
                                onClicked: insp.set(modelData.key, !checked || null)
                            }
                        }
                    }
                }
                FieldRow {
                    visible: insp.node && insp.node.type === "Text"
                    label: "Case"
                    Choice {
                        width: parent.width
                        values: ["none", "upper", "lower", "title"]
                        titles: ["As Typed", "UPPERCASE", "lowercase", "Title Case"]
                        value: insp.val("textCase", "none")
                        onCommit: (v) => insp.set("textCase", v === "none" ? null : v)
                    }
                }
                FieldRow {
                    visible: insp.node && insp.node.type === "Text"
                    label: "Line Height"
                    NumberValue { value: +insp.val("lineHeight", 1); minimum: 0.5; maximum: 4; step: 0.1; onCommit: (v) => insp.set("lineHeight", v === 1 ? null : v) }
                }
                FieldRow {
                    visible: insp.node && insp.node.type === "Text"
                    label: "Tracking"
                    NumberValue { value: +insp.val("letterSpacing", 0); minimum: -10; maximum: 40; step: 0.5; onCommit: (v) => insp.set("letterSpacing", v || null) }
                }
            }

            // Colours and fill.
            Section {
                visible: !insp.plain
                title: "Appearance"
                FieldRow {
                    label: insp.node && insp.node.type === "Symbol" ? "Tint" : "Foreground"
                    ColorValue { value: String(insp.val("foreground", "")); onCommit: (v) => insp.set("foreground", v || null) }
                }
                FieldRow {
                    label: "Background"
                    FillEditor {
                        width: parent.width
                        inspector: insp
                        value: insp.val("background", null)
                        onCommit: (v) => insp.set("background", v)
                    }
                }
                FieldRow {
                    visible: !insp.node || insp.node.type !== "Shape" || insp.val("shape", "") === "roundedRectangle"
                    label: "Corners"
                    NumberValue { value: +insp.val("cornerRadius", 0); minimum: 0; maximum: 999; onCommit: (v) => insp.set("cornerRadius", v || null) }
                }
                FieldRow {
                    label: "Border"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: 62; value: +insp.val("borderWidth", 0); minimum: 0; maximum: 40; step: 0.5; onCommit: (v) => insp.set("borderWidth", v || null) }
                        ColorValue { width: parent.width - 68; value: String(insp.props.borderColor || ""); placeholder: "Separator"; onCommit: (v) => insp.set("borderColor", v || null) }
                    }
                }
                FieldRow {
                    label: "Opacity"
                    NumberValue { value: +insp.val("opacity", 1); minimum: 0; maximum: 1; step: 0.05; onCommit: (v) => insp.set("opacity", v === 1 ? null : v) }
                }
            }

            Section {
                visible: !insp.plain
                title: "Shadow"
                FieldRow {
                    label: "Blur"
                    NumberValue { value: +insp.val("shadowRadius", 0); minimum: 0; maximum: 100; onCommit: (v) => insp.set("shadowRadius", v || null) }
                }
                FieldRow {
                    visible: +insp.val("shadowRadius", 0) > 0
                    label: "Offset"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("shadowX", 0); onCommit: (v) => insp.set("shadowX", v || null) }
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("shadowY", 4); onCommit: (v) => insp.set("shadowY", v) }
                    }
                }
                FieldRow {
                    visible: +insp.val("shadowRadius", 0) > 0
                    label: "Color"
                    Row {
                        width: parent.width
                        spacing: 6
                        ColorValue { width: parent.width - 68; value: String(insp.props.shadowColor || ""); placeholder: "Black"; onCommit: (v) => insp.set("shadowColor", v || null) }
                        NumberValue { width: 62; value: +insp.val("shadowOpacity", 0.2); minimum: 0; maximum: 1; step: 0.05; onCommit: (v) => insp.set("shadowOpacity", v) }
                    }
                }
            }

            Section {
                visible: !insp.plain
                title: "Effects"
                FieldRow {
                    label: "On Hover"
                    Choice {
                        width: parent.width
                        values: ["none", "highlight", "lift", "scale"]
                        titles: ["Nothing", "Highlight", "Lift", "Grow"]
                        value: insp.val("hoverEffect", "none")
                        onCommit: (v) => insp.set("hoverEffect", v === "none" ? null : v)
                    }
                }
                FieldRow {
                    label: "Appear"
                    Choice {
                        width: parent.width
                        values: ["fade", "scale", "slide", "none"]
                        titles: ["Fade", "Zoom", "Slide Up", "Instantly"]
                        value: insp.val("transition", "fade")
                        onCommit: (v) => insp.set("transition", v === "fade" ? null : v)
                    }
                }
                FieldRow {
                    label: "Rotation"
                    NumberValue { value: +insp.val("rotation", 0); minimum: -360; maximum: 360; step: 5; onCommit: (v) => insp.set("rotation", v || null) }
                }
                FieldRow {
                    label: "Scale"
                    NumberValue { value: +insp.val("scale", 1); minimum: 0.1; maximum: 5; step: 0.05; onCommit: (v) => insp.set("scale", v === 1 ? null : v) }
                }
            }

            Section {
                title: "Visibility"
                FieldRow {
                    label: "Show When"
                    VarChoice {
                        width: parent.width
                        type: "bool"
                        noneTitle: "Always"
                        value: insp.props.visibleWhen || ""
                        onCommit: (v) => {
                            if (v === "@new") {
                                const r = Design.addVariable(insp.doc, "bool", "showDetails")
                                insp.designer.commit(Design.update(r.doc, insp.node.id, { visibleWhen: r.name }))
                            } else insp.set("visibleWhen", v || null)
                        }
                    }
                }
                FieldRow {
                    visible: !!insp.props.visibleWhen
                    label: ""
                    Checkbox {
                        width: parent.width
                        text: "When it's off instead"
                        checked: !!insp.props.visibleWhenNot
                        onToggled: (c) => insp.set("visibleWhenNot", c || null)
                    }
                }
                FieldRow {
                    visible: !insp.plain
                    label: "Description"
                    TextValue {
                        value: String(insp.props.accessibilityLabel || "")
                        placeholder: "For screen readers"
                        onCommit: (t) => insp.set("accessibilityLabel", t || null)
                    }
                }
            }
        }

        // ===================================================== Layout
        Column {
            visible: !!insp.node && insp.tab === 1
            width: parent.width
            spacing: 10
            Section {
                visible: !insp.plain
                title: "Frame"
                FieldRow { label: "Width"; FrameValue { value: insp.val("frameWidth", "auto"); onCommit: (v) => insp.set("frameWidth", v === "auto" ? null : v) } }
                FieldRow { label: "Height"; FrameValue { value: insp.val("frameHeight", "auto"); onCommit: (v) => insp.set("frameHeight", v === "auto" ? null : v) } }
                FieldRow {
                    label: "Min Size"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("minWidth", 0); empty: !insp.props.minWidth; placeholder: "W"; minimum: 0; maximum: 4000; onCommit: (v) => insp.set("minWidth", v || null); onClear: insp.set("minWidth", null) }
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("minHeight", 0); empty: !insp.props.minHeight; placeholder: "H"; minimum: 0; maximum: 4000; onCommit: (v) => insp.set("minHeight", v || null); onClear: insp.set("minHeight", null) }
                    }
                }
                FieldRow {
                    label: "Max Size"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("maxWidth", 0); empty: !insp.props.maxWidth; placeholder: "W"; minimum: 0; maximum: 4000; onCommit: (v) => insp.set("maxWidth", v || null); onClear: insp.set("maxWidth", null) }
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("maxHeight", 0); empty: !insp.props.maxHeight; placeholder: "H"; minimum: 0; maximum: 4000; onCommit: (v) => insp.set("maxHeight", v || null); onClear: insp.set("maxHeight", null) }
                    }
                }
            }
            Section {
                visible: !insp.plain && !!insp.parentNode
                title: "Position"
                FieldRow {
                    label: "Alignment"
                    Choice {
                        width: parent.width
                        readonly property string parentType: insp.parentNode ? insp.parentNode.type : ""
                        values: parentType === "HStack" ? ["", "top", "center", "bottom"]
                              : parentType === "ZStack" ? ["", "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"]
                              : ["", "leading", "center", "trailing"]
                        titles: values.map((v) => v ? v.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase()) : "Like the Stack")
                        value: insp.val("align", "")
                        onCommit: (v) => insp.set("align", v || null)
                    }
                }
                FieldRow {
                    label: "Offset"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("offsetX", 0); onCommit: (v) => insp.set("offsetX", v || null) }
                        NumberValue { width: (parent.width - 6) / 2; value: +insp.val("offsetY", 0); onCommit: (v) => insp.set("offsetY", v || null) }
                    }
                }
            }
            Section {
                visible: !insp.plain
                title: "Padding"
                FieldRow {
                    label: "All Edges"
                    visible: !Array.isArray(insp.val("padding", 0))
                    NumberValue { value: +insp.val("padding", 0); minimum: 0; maximum: 400; onCommit: (v) => insp.set("padding", v || null) }
                }
                Repeater {
                    model: Array.isArray(insp.val("padding", 0)) ? ["Top", "Trailing", "Bottom", "Leading"] : []
                    delegate: FieldRow {
                        required property string modelData
                        required property int index
                        label: modelData
                        NumberValue {
                            value: +(insp.val("padding", [0, 0, 0, 0])[index] || 0)
                            minimum: 0; maximum: 400
                            onCommit: (v) => { const p = insp.val("padding", [0, 0, 0, 0]).slice(); p[index] = v; insp.set("padding", p) }
                        }
                    }
                }
                FieldRow {
                    label: ""
                    Checkbox {
                        width: parent.width
                        text: "Each edge separately"
                        checked: Array.isArray(insp.val("padding", 0))
                        onToggled: (c) => {
                            const p = insp.val("padding", 0)
                            insp.set("padding", c ? [+p || 0, +p || 0, +p || 0, +p || 0] : (Array.isArray(p) ? (+p[0] || null) : p))
                        }
                    }
                }
                FieldRow {
                    label: ""
                    Checkbox {
                        width: parent.width
                        text: "Clip content to the frame"
                        checked: !!insp.val("clipContent", false)
                        onToggled: (c) => insp.set("clipContent", c || null)
                    }
                }
            }
            Text {
                visible: insp.plain
                width: parent.width
                wrapMode: Text.Wrap
                text: insp.node && insp.node.type === "Spacer" ? "A spacer takes all the room its stack has left. Use Minimum Length in Attributes to keep some space even when there's none left."
                                                              : "A divider runs across its stack (down it, in a horizontal stack)."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            }
        }

        // ==================================================== Actions
        Column {
            visible: !!insp.node && insp.tab === 2 && !insp.plain
            width: parent.width
            spacing: 12
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Actions run in order. Use {name} to put a variable's value in text."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            }
            Repeater {
                model: {
                    if (!insp.info) return []
                    const evs = Object.keys(insp.info.events || {})
                    if (evs.indexOf("tap") < 0) evs.unshift("tap")
                    return evs
                }
                delegate: ActionList {
                    required property string modelData
                    width: column.width
                    inspector: insp
                    event: modelData
                    actions: insp.node && insp.node.actions ? (insp.node.actions[modelData] || []) : []
                    onCommit: (list) => insp.designer.setActions(insp.node.id, modelData, list)
                }
            }
        }

        // ======================================================== App
        Column {
            visible: insp.sel.kind === "app" && !!insp.doc
            width: parent.width
            spacing: 10
            Section {
                title: "Identity"
                FieldRow { label: "Name"; TextValue { value: insp.doc ? insp.doc.app.name || "" : ""; onCommit: (t) => insp.designer.setApp({ name: t }) } }
                FieldRow {
                    label: "Window"
                    Choice {
                        width: parent.width
                        values: ["sidebar", "window", "utility"]
                        titles: ["Sidebar", "Single Window", "Utility"]
                        value: insp.doc ? insp.doc.app.style : "window"
                        onCommit: (v) => insp.designer.setApp({ style: v, resizable: v !== "utility" })
                    }
                }
            }
            Section {
                title: "Look"
                FieldRow {
                    label: "Accent"
                    ColorValue { value: insp.doc ? insp.doc.app.accent || "" : ""; customOnly: true; placeholder: "CitronOS"; onCommit: (v) => insp.designer.setApp({ accent: v || null }) }
                }
                FieldRow {
                    label: "Appearance"
                    Choice {
                        width: parent.width
                        values: ["auto", "light", "dark"]
                        titles: ["Automatic", "Always Light", "Always Dark"]
                        value: insp.doc ? insp.doc.app.appearance || "auto" : "auto"
                        onCommit: (v) => insp.designer.setApp({ appearance: v })
                    }
                }
                FieldRow {
                    label: "Font"
                    Choice {
                        width: parent.width
                        readonly property var installed: Qt.fontFamilies().slice(0, 120)
                        values: ["", "display", "rounded", "serif", "mono"].concat(installed)
                        titles: ["System", "Display", "Rounded", "Serif", "Monospaced"].concat(installed)
                        value: insp.doc ? insp.doc.app.font || "" : ""
                        onCommit: (v) => insp.designer.setApp({ font: v || null })
                    }
                }
                FieldRow {
                    label: "Background"
                    ColorValue { value: insp.doc ? insp.doc.app.background || "" : ""; placeholder: "Window"; onCommit: (v) => insp.designer.setApp({ background: v || null }) }
                }
            }
            Section {
                title: "Window Size"
                FieldRow {
                    label: "Size"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: insp.doc ? insp.doc.app.width || 900 : 900; minimum: 240; maximum: 4000; step: 10; onCommit: (v) => insp.designer.setApp({ width: v }) }
                        NumberValue { width: (parent.width - 6) / 2; value: insp.doc ? insp.doc.app.height || 620 : 620; minimum: 200; maximum: 4000; step: 10; onCommit: (v) => insp.designer.setApp({ height: v }) }
                    }
                }
                FieldRow {
                    label: "Minimum"
                    Row {
                        width: parent.width
                        spacing: 6
                        NumberValue { width: (parent.width - 6) / 2; value: insp.doc ? insp.doc.app.minWidth || 320 : 320; minimum: 160; maximum: 4000; step: 10; onCommit: (v) => insp.designer.setApp({ minWidth: v }) }
                        NumberValue { width: (parent.width - 6) / 2; value: insp.doc ? insp.doc.app.minHeight || 240 : 240; minimum: 120; maximum: 4000; step: 10; onCommit: (v) => insp.designer.setApp({ minHeight: v }) }
                    }
                }
                FieldRow {
                    label: "Resizable"
                    Item { width: 40; height: 24; Switch { anchors.verticalCenter: parent.verticalCenter; checked: insp.doc ? insp.doc.app.resizable !== false : true; onToggled: (c) => insp.designer.setApp({ resizable: c }) } }
                }
                FieldRow {
                    visible: insp.doc && insp.doc.app.style === "sidebar"
                    label: "Sidebar"
                    NumberValue { value: insp.doc ? insp.doc.app.sidebarWidth || 220 : 220; minimum: 140; maximum: 480; step: 10; onCommit: (v) => insp.designer.setApp({ sidebarWidth: v }) }
                }
            }
        }

        // ===================================================== Screen
        Column {
            visible: !!insp.screen
            width: parent.width
            spacing: 10
            Section {
                title: "Screen"
                FieldRow { label: "Title"; TextValue { value: insp.screen ? insp.screen.title || "" : ""; onCommit: (t) => insp.designer.setScreen(insp.screen.id, { title: t }) } }
                FieldRow { label: "Symbol"; SymbolValue { value: insp.screen ? insp.screen.symbol || "" : ""; onCommit: (v) => insp.designer.setScreen(insp.screen.id, { symbol: v }) } }
                FieldRow {
                    label: "Identifier"
                    Text {
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        text: insp.screen ? insp.screen.id : ""
                        color: Theme.secondaryLabel
                        font { family: "monospace"; pixelSize: Theme.fs(11) }
                    }
                }
                Row {
                    spacing: 6
                    Button { text: "Move Up"; onClicked: insp.designer.commit(Design.moveScreen(insp.doc, insp.screen.id, -1)) }
                    Button { text: "Move Down"; onClicked: insp.designer.commit(Design.moveScreen(insp.doc, insp.screen.id, 1)) }
                }
                Button {
                    visible: insp.doc && insp.doc.screens.length > 1
                    text: "Delete Screen"
                    destructive: true
                    onClicked: insp.designer.removeSelected()
                }
            }
        }

        // =================================================== Variable
        Column {
            visible: !!insp.variable
            width: parent.width
            spacing: 10
            Section {
                title: "Variable"
                FieldRow {
                    label: "Name"
                    TextValue {
                        value: insp.variable ? insp.variable.name : ""
                        onCommit: (t) => {
                            const before = insp.variable.name
                            const next = Design.updateVariable(insp.doc, before, { name: t })
                            insp.designer.commit(next)
                            if (Design.variable(next, t.replace(/[^A-Za-z0-9_]/g, ""))) insp.designer.selection = { kind: "variable", id: t.replace(/[^A-Za-z0-9_]/g, "") }
                        }
                    }
                }
                FieldRow {
                    label: "Type"
                    Choice {
                        width: parent.width
                        values: ["text", "number", "bool", "list"]
                        titles: ["Text", "Number", "On/Off", "List"]
                        value: insp.variable ? insp.variable.type : "text"
                        onCommit: (v) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { type: v }))
                    }
                }
                FieldRow {
                    label: "Starts As"
                    Loader {
                        width: parent.width
                        sourceComponent: !insp.variable ? null : insp.variable.type === "number" ? startNumber
                            : insp.variable.type === "bool" ? startBool : insp.variable.type === "list" ? startList : startText
                        Component { id: startText; TextValue { value: String(insp.variable.value || ""); onCommit: (t) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { value: t })) } }
                        Component { id: startNumber; NumberValue { value: +insp.variable.value || 0; onCommit: (v) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { value: v })) } }
                        Component { id: startBool; Item { width: 40; height: 24; Switch { anchors.verticalCenter: parent.verticalCenter; checked: !!insp.variable.value; onToggled: (c) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { value: c })) } } }
                        Component { id: startList; OptionsEditor { values: Array.isArray(insp.variable.value) ? insp.variable.value : []; checkable: true; onCommit: (list) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { value: list })) } }
                    }
                }
                FieldRow {
                    label: "Saved"
                    Item { width: 40; height: 24; Switch { anchors.verticalCenter: parent.verticalCenter; checked: insp.variable ? !!insp.variable.persist : false; onToggled: (c) => insp.designer.commit(Design.updateVariable(insp.doc, insp.variable.name, { persist: c })) } }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: (insp.variable && insp.variable.persist ? "Kept when the app quits, and restored when it opens. " : "Starts fresh each time the app opens. ")
                        + (insp.variable ? "Used by " + Design.usesOf(insp.doc, insp.variable.name).length + " item(s)." : "")
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                }
                Button { text: "Delete Variable"; destructive: true; onClicked: insp.designer.removeSelected() }
            }
        }

        // ====================================================== Color
        Column {
            visible: !!insp.namedColor
            width: parent.width
            spacing: 10
            Section {
                title: "Color"
                FieldRow {
                    label: "Name"
                    TextValue {
                        value: insp.namedColor ? insp.namedColor.name : ""
                        onCommit: (t) => {
                            const name = t.replace(/[^A-Za-z0-9_ ]/g, "").trim()
                            if (!name || insp.doc.colors.some((c) => c.name === name)) return
                            insp.designer.commit(Design.updateColor(insp.doc, insp.namedColor.name, { name: name }))
                            insp.designer.selection = { kind: "color", id: name }
                        }
                    }
                }
                FieldRow { label: "Light"; ColorValue { value: insp.namedColor ? insp.namedColor.light : ""; customOnly: true; onCommit: (v) => insp.designer.commit(Design.updateColor(insp.doc, insp.namedColor.name, { light: v })) } }
                FieldRow { label: "Dark"; ColorValue { value: insp.namedColor ? insp.namedColor.dark : ""; customOnly: true; onCommit: (v) => insp.designer.commit(Design.updateColor(insp.doc, insp.namedColor.name, { dark: v })) } }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Use it by name anywhere a color is chosen (the App tab of the color picker). It changes with the appearance."
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                }
                Button { text: "Delete Color"; destructive: true; onClicked: insp.designer.removeSelected() }
            }
        }
    }
}
