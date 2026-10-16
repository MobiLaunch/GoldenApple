// The App Designer's catalog: every Kit component it can place, with its
// default properties, the inspector fields it shows, what it can bind to a
// variable and which events it can act on; and the Library's ready-made
// pieces. lcode_design.py reads the same data (the JSON between the markers)
// to generate an app's QML, so the designer and the build always agree.
.pragma library

var CATALOG = /* CATALOG-JSON-BEGIN */ {
  "components": {
    "VStack": {
      "title": "Vertical Stack", "symbol": "stack-vertical", "container": true,
      "detail": "Arranges its contents in a column.",
      "defaults": { "spacing": 12, "alignment": "center" },
      "fields": [
        { "key": "spacing", "label": "Spacing", "kind": "number", "min": 0, "max": 200 },
        { "key": "alignment", "label": "Alignment", "kind": "segmented", "options": ["leading", "center", "trailing"], "symbols": ["text-align-left", "text-align-center", "text-align-right"] },
        { "key": "justify", "label": "Distribution", "kind": "enum", "options": ["start", "center", "end"], "titles": ["Top", "Center", "Bottom"] }
      ]
    },
    "HStack": {
      "title": "Horizontal Stack", "symbol": "stack-horizontal", "container": true,
      "detail": "Arranges its contents in a row.",
      "defaults": { "spacing": 10, "alignment": "center" },
      "fields": [
        { "key": "spacing", "label": "Spacing", "kind": "number", "min": 0, "max": 200 },
        { "key": "alignment", "label": "Alignment", "kind": "enum", "options": ["top", "center", "bottom"], "titles": ["Top", "Center", "Bottom"] },
        { "key": "justify", "label": "Distribution", "kind": "enum", "options": ["start", "center", "end"], "titles": ["Leading", "Center", "Trailing"] }
      ]
    },
    "ZStack": {
      "title": "Overlay Stack", "symbol": "stack-depth", "container": true,
      "detail": "Layers its contents on top of each other, the last one in front.",
      "defaults": { "alignment": "center" },
      "fields": [
        { "key": "alignment", "label": "Alignment", "kind": "enum",
          "options": ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"],
          "titles": ["Top Leading", "Top", "Top Trailing", "Leading", "Center", "Trailing", "Bottom Leading", "Bottom", "Bottom Trailing"] }
      ]
    },
    "Grid": {
      "title": "Grid", "symbol": "grid", "container": true,
      "detail": "Arranges its contents in rows of equal columns.",
      "defaults": { "columns": 2, "spacing": 12, "frameWidth": "fill" },
      "fields": [
        { "key": "columns", "label": "Columns", "kind": "number", "min": 1, "max": 12 },
        { "key": "spacing", "label": "Spacing", "kind": "number", "min": 0, "max": 200 }
      ]
    },
    "ScrollView": {
      "title": "Scroll View", "symbol": "scroll", "container": true,
      "detail": "Scrolls content that's taller (or wider) than its space.",
      "defaults": { "frameWidth": "fill", "frameHeight": "fill" },
      "fields": [
        { "key": "horizontal", "label": "Scrolls Sideways", "kind": "bool" },
        { "key": "showsIndicators", "label": "Scroll Bar", "kind": "bool" }
      ]
    },
    "Spacer": {
      "title": "Spacer", "symbol": "spacer", "container": false, "plain": true,
      "detail": "Flexible space that pushes its neighbours apart.",
      "defaults": {},
      "fields": [ { "key": "minLength", "label": "Minimum Length", "kind": "number", "min": 0, "max": 400 } ]
    },
    "Divider": {
      "title": "Divider", "symbol": "divider", "container": false, "plain": true,
      "detail": "A hairline that separates content.",
      "defaults": {},
      "fields": [
        { "key": "color", "label": "Color", "kind": "color" },
        { "key": "thickness", "label": "Thickness", "kind": "number", "min": 0.5, "max": 20, "step": 0.5 },
        { "key": "inset", "label": "Inset", "kind": "number", "min": 0, "max": 200 }
      ]
    },
    "Text": {
      "title": "Text", "symbol": "textformat", "container": false, "font": true,
      "detail": "Text, in a style or your own font. Write {name} to show a variable.",
      "defaults": { "text": "Text", "textStyle": "body" },
      "templates": ["text"],
      "fields": [
        { "key": "text", "label": "Text", "kind": "multiline" },
        { "key": "textAlign", "label": "Alignment", "kind": "segmented", "options": ["leading", "center", "trailing"], "symbols": ["text-align-left", "text-align-center", "text-align-right"] },
        { "key": "maxLines", "label": "Lines", "kind": "number", "min": 0, "max": 50, "placeholder": "No Limit" },
        { "key": "markdown", "label": "Markdown", "kind": "bool" }
      ]
    },
    "Button": {
      "title": "Button", "symbol": "button", "container": false,
      "detail": "Does something when clicked: add actions in the Actions inspector.",
      "defaults": { "title": "Button", "buttonStyle": "bordered" },
      "templates": ["title"],
      "events": { "tap": "tapped" },
      "fields": [
        { "key": "title", "label": "Title", "kind": "text" },
        { "key": "symbol", "label": "Symbol", "kind": "symbol" },
        { "key": "buttonStyle", "label": "Style", "kind": "enum", "options": ["prominent", "bordered", "glass", "plain", "link", "destructive"], "titles": ["Prominent", "Bordered", "Glass", "Plain", "Link", "Destructive"] },
        { "key": "size", "label": "Size", "kind": "segmented", "options": ["small", "regular", "large"], "titles": ["Small", "Regular", "Large"] },
        { "key": "tint", "label": "Tint", "kind": "color" },
        { "key": "buttonRadius", "label": "Corner Radius", "kind": "number", "min": -1, "max": 100, "placeholder": "Capsule" }
      ]
    },
    "Toggle": {
      "title": "Toggle", "symbol": "toggle", "container": false,
      "detail": "On or off: a switch or a checkbox, bound to a true/false variable.",
      "defaults": { "label": "Toggle", "toggleStyle": "switch" },
      "templates": ["label"],
      "bind": { "prop": "value", "signal": "edited", "type": "bool" },
      "events": { "change": "edited" },
      "fields": [
        { "key": "label", "label": "Label", "kind": "text" },
        { "key": "toggleStyle", "label": "Style", "kind": "segmented", "options": ["switch", "checkbox"], "titles": ["Switch", "Checkbox"] },
        { "key": "tint", "label": "Tint", "kind": "color" },
        { "key": "value", "label": "On", "kind": "bool" }
      ]
    },
    "Slider": {
      "title": "Slider", "symbol": "slider", "container": false,
      "detail": "Picks a number between a minimum and a maximum.",
      "defaults": { "minimum": 0, "maximum": 1, "value": 0.5, "frameWidth": 200 },
      "bind": { "prop": "value", "signal": "edited", "type": "number" },
      "events": { "change": "edited" },
      "fields": [
        { "key": "minimum", "label": "Minimum", "kind": "number", "min": -100000, "max": 100000 },
        { "key": "maximum", "label": "Maximum", "kind": "number", "min": -100000, "max": 100000 },
        { "key": "step", "label": "Step", "kind": "number", "min": 0, "max": 10000, "placeholder": "Continuous" },
        { "key": "value", "label": "Value", "kind": "number", "min": -100000, "max": 100000 },
        { "key": "showValue", "label": "Show Value", "kind": "bool" },
        { "key": "tint", "label": "Tint", "kind": "color" }
      ]
    },
    "Segmented": {
      "title": "Segmented Control", "symbol": "segmented", "container": false,
      "detail": "A choice of a few options side by side; its variable is the chosen option's number (0, 1, 2…).",
      "defaults": { "options": ["First", "Second", "Third"], "value": 0 },
      "bind": { "prop": "value", "signal": "edited", "type": "number" },
      "events": { "change": "edited" },
      "fields": [
        { "key": "options", "label": "Options", "kind": "options" },
        { "key": "value", "label": "Selected", "kind": "number", "min": 0, "max": 50 },
        { "key": "tint", "label": "Tint", "kind": "color" }
      ]
    },
    "Picker": {
      "title": "Pop-Up Menu", "symbol": "chevron-updown", "container": false,
      "detail": "A menu of options; its variable is the chosen option's number.",
      "defaults": { "label": "", "options": ["First", "Second", "Third"], "value": 0 },
      "templates": ["label"],
      "bind": { "prop": "value", "signal": "edited", "type": "number" },
      "events": { "change": "edited" },
      "fields": [
        { "key": "label", "label": "Label", "kind": "text" },
        { "key": "options", "label": "Options", "kind": "options" },
        { "key": "value", "label": "Selected", "kind": "number", "min": 0, "max": 50 }
      ]
    },
    "TextField": {
      "title": "Text Field", "symbol": "textfield", "container": false,
      "detail": "A line of text the user types, kept in a text variable.",
      "defaults": { "placeholder": "Text", "frameWidth": "fill" },
      "templates": ["placeholder"],
      "bind": { "prop": "value", "signal": "edited", "type": "text" },
      "events": { "change": "edited", "submit": "submitted" },
      "fields": [
        { "key": "placeholder", "label": "Placeholder", "kind": "text" },
        { "key": "fieldStyle", "label": "Style", "kind": "segmented", "options": ["rounded", "plain", "search"], "titles": ["Rounded", "Plain", "Search"] },
        { "key": "secure", "label": "Password", "kind": "bool" }
      ]
    },
    "TextArea": {
      "title": "Text Editor", "symbol": "doc", "container": false,
      "detail": "Several lines of text the user types.",
      "defaults": { "placeholder": "Type here…", "frameWidth": "fill", "frameHeight": 120 },
      "templates": ["placeholder"],
      "bind": { "prop": "value", "signal": "edited", "type": "text" },
      "events": { "change": "edited" },
      "fields": [ { "key": "placeholder", "label": "Placeholder", "kind": "text" } ]
    },
    "ProgressBar": {
      "title": "Progress Bar", "symbol": "progress", "container": false,
      "detail": "Shows progress from 0 to 1 (bind a number variable), or that something is busy.",
      "defaults": { "value": 0.4, "frameWidth": 200 },
      "bind": { "prop": "value", "type": "number" },
      "fields": [
        { "key": "value", "label": "Value", "kind": "number", "min": 0, "max": 1, "step": 0.05 },
        { "key": "indeterminate", "label": "Busy", "kind": "bool" },
        { "key": "tint", "label": "Tint", "kind": "color" }
      ]
    },
    "Image": {
      "title": "Image", "symbol": "photo", "container": false,
      "detail": "A picture from your app's Assets folder.",
      "defaults": { "frameWidth": 200, "frameHeight": 140, "cornerRadius": 12 },
      "templates": ["source"],
      "fields": [
        { "key": "source", "label": "Image", "kind": "image" },
        { "key": "fit", "label": "Content Mode", "kind": "segmented", "options": ["fill", "fit"], "titles": ["Fill", "Fit"] }
      ]
    },
    "Symbol": {
      "title": "Symbol", "symbol": "star", "container": false,
      "detail": "One of CitronOS's symbols, in any colour.",
      "defaults": { "name": "star", "size": 28 },
      "fields": [
        { "key": "name", "label": "Symbol", "kind": "symbol" },
        { "key": "size", "label": "Size", "kind": "number", "min": 8, "max": 400 }
      ]
    },
    "Shape": {
      "title": "Shape", "symbol": "shapes", "container": false,
      "detail": "A rectangle, circle or capsule, filled with a colour, gradient, glass or image.",
      "defaults": { "shape": "roundedRectangle", "frameWidth": 80, "frameHeight": 80 },
      "fields": [
        { "key": "shape", "label": "Shape", "kind": "enum", "options": ["rectangle", "roundedRectangle", "circle", "capsule"], "titles": ["Rectangle", "Rounded Rectangle", "Circle", "Capsule"] }
      ]
    },
    "List": {
      "title": "List", "symbol": "list", "container": false,
      "detail": "Rows from a list variable: tick them off, delete them, tap them.",
      "defaults": { "items": ["First item", "Second item", "Third item"], "listStyle": "inset" },
      "bind": { "prop": "items", "type": "list" },
      "events": { "itemTap": "itemTapped" },
      "fields": [
        { "key": "items", "label": "Rows", "kind": "options" },
        { "key": "listStyle", "label": "Style", "kind": "segmented", "options": ["inset", "plain"], "titles": ["Inset", "Plain"] },
        { "key": "checkable", "label": "Check Marks", "kind": "bool" },
        { "key": "deletable", "label": "Delete Buttons", "kind": "bool" },
        { "key": "rowSymbol", "label": "Row Symbol", "kind": "symbol" },
        { "key": "emptyText", "label": "When Empty", "kind": "text" }
      ]
    },
    "Link": {
      "title": "Link", "symbol": "link", "container": false,
      "detail": "Text that opens a web page.",
      "defaults": { "title": "Learn More", "url": "https://" },
      "templates": ["title", "url"],
      "events": { "tap": "tapped" },
      "fields": [
        { "key": "title", "label": "Title", "kind": "text" },
        { "key": "url", "label": "Address", "kind": "text" }
      ]
    }
  },

  "library": [
    { "section": "Layout" },
    { "type": "VStack", "title": "Vertical Stack" },
    { "type": "HStack", "title": "Horizontal Stack" },
    { "type": "ZStack", "title": "Overlay Stack" },
    { "type": "Grid", "title": "Grid" },
    { "type": "ScrollView", "title": "Scroll View" },
    { "type": "Spacer", "title": "Spacer" },
    { "type": "Divider", "title": "Divider" },
    { "type": "VStack", "title": "Card", "symbol": "card", "detail": "A rounded glass panel that groups content.",
      "props": { "spacing": 8, "alignment": "leading", "padding": 18, "cornerRadius": 18, "frameWidth": "fill",
                 "background": { "type": "material", "material": "regular" }, "shadowRadius": 12, "shadowOpacity": 0.12 },
      "children": [ { "type": "Text", "props": { "text": "Title", "textStyle": "headline" } },
                    { "type": "Text", "props": { "text": "Something worth reading.", "foreground": "secondaryLabel" } } ] },
    { "section": "Text" },
    { "type": "Text", "title": "Text" },
    { "type": "Text", "title": "Large Title", "detail": "A screen's big title.", "props": { "text": "Title", "textStyle": "largeTitle" } },
    { "type": "Text", "title": "Badge", "symbol": "tag", "detail": "A short label in a coloured capsule.",
      "props": { "text": "New", "textStyle": "caption", "fontWeight": 700, "foreground": "white", "padding": [3, 9, 3, 9], "cornerRadius": 99,
                 "background": { "type": "color", "color": "accent" } } },
    { "type": "Link", "title": "Link" },
    { "section": "Controls" },
    { "type": "Button", "title": "Button" },
    { "type": "Button", "title": "Prominent Button", "props": { "title": "Continue", "buttonStyle": "prominent", "size": "large" } },
    { "type": "Toggle", "title": "Toggle" },
    { "type": "Slider", "title": "Slider" },
    { "type": "Segmented", "title": "Segmented Control" },
    { "type": "Picker", "title": "Pop-Up Menu" },
    { "type": "TextField", "title": "Text Field" },
    { "type": "TextField", "title": "Search Field", "symbol": "search", "props": { "placeholder": "Search", "fieldStyle": "search" } },
    { "type": "TextArea", "title": "Text Editor" },
    { "type": "ProgressBar", "title": "Progress Bar" },
    { "section": "Collections" },
    { "type": "List", "title": "List" },
    { "type": "List", "title": "Checklist", "symbol": "checkmark-square", "detail": "A to-do list: tick rows off and delete them.",
      "props": { "checkable": true, "deletable": true, "items": [ { "title": "Try LCode", "done": true }, { "title": "Design an app", "done": false } ] } },
    { "section": "Media" },
    { "type": "Image", "title": "Image" },
    { "type": "Symbol", "title": "Symbol" },
    { "type": "Shape", "title": "Shape" },
    { "type": "Shape", "title": "Circle", "symbol": "circle", "props": { "shape": "circle", "frameWidth": 64, "frameHeight": 64 } },
    { "type": "Shape", "title": "Gradient", "symbol": "gradient", "detail": "A shape filled with a gradient.",
      "props": { "shape": "roundedRectangle", "frameWidth": "fill", "frameHeight": 120, "cornerRadius": 20,
                 "background": { "type": "gradient", "colors": ["accent", "purple"], "angle": 135 } } }
  ],

  "events": {
    "tap": "When Clicked", "change": "When Changed", "submit": "When Return Is Pressed", "itemTap": "When a Row Is Clicked"
  },

  "actions": [
    { "do": "set", "title": "Set Variable", "symbol": "curlybraces", "fields": ["var", "value"] },
    { "do": "increment", "title": "Add to Number", "symbol": "plus", "fields": ["var", "by"] },
    { "do": "toggle", "title": "Toggle On/Off", "symbol": "toggle", "fields": ["var"] },
    { "do": "append", "title": "Add to List", "symbol": "list", "fields": ["var", "value"] },
    { "do": "removeItem", "title": "Remove This Row", "symbol": "trash", "fields": ["var"] },
    { "do": "clear", "title": "Clear Variable", "symbol": "xmark-circle", "fields": ["var"] },
    { "do": "navigate", "title": "Go to Screen", "symbol": "forward", "fields": ["screen"] },
    { "do": "back", "title": "Go Back", "symbol": "backward", "fields": [] },
    { "do": "alert", "title": "Show Alert", "symbol": "warning", "fields": ["title", "message"] },
    { "do": "notify", "title": "Send Notification", "symbol": "bell", "fields": ["title", "message"] },
    { "do": "openUrl", "title": "Open Web Page", "symbol": "globe", "fields": ["url"] },
    { "do": "copy", "title": "Copy Text", "symbol": "copy", "fields": ["text"] },
    { "do": "run", "title": "Run Command", "symbol": "terminal", "fields": ["command", "var"] },
    { "do": "script", "title": "Call Logic.js", "symbol": "code", "fields": ["call"] },
    { "do": "quit", "title": "Quit App", "symbol": "power", "fields": [] }
  ]
} /* CATALOG-JSON-END */;

function component(type) { return CATALOG.components[type] || null; }
function isContainer(type) { const c = component(type); return !!(c && c.container); }
function title(type) { const c = component(type); return c ? c.title : type; }
function symbolFor(type) { const c = component(type); return c ? c.symbol : "square-dashed"; }
function action(name) { return CATALOG.actions.find((a) => a.do === name) || null; }
