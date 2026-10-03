// Text, in a text style or your own font, with {variables} filled in by the app.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string text: "Text"
    property string textStyle: "body"         // largeTitle … caption2 (kit.js)
    property string fontFamily: ""            // "" (system), display, rounded, serif, mono, or a family name
    property real fontSize: 0                 // 0: the style's size
    property int fontWeight: 0                // 100…900; 0: the style's weight
    property bool italic: false
    property bool underline: false
    property bool strikethrough: false
    property string textAlign: "leading"      // leading | center | trailing
    property real lineHeight: 1
    property real letterSpacing: 0
    property int maxLines: 0                  // 0: as many as it needs
    property string textCase: "none"          // none | upper | lower | title
    property bool markdown: false
    contentWidth: label.implicitWidth
    contentHeight: label.implicitHeight

    Text {
        id: label
        width: root.innerWidth
        text: root.text
        textFormat: root.markdown ? Text.MarkdownText : Text.PlainText
        color: root.foregroundColor
        wrapMode: Text.Wrap
        maximumLineCount: root.maxLines > 0 ? root.maxLines : 100000
        elide: root.maxLines > 0 ? Text.ElideRight : Text.ElideNone
        lineHeight: root.lineHeight
        horizontalAlignment: root.textAlign === "center" ? Text.AlignHCenter : root.textAlign === "trailing" ? Text.AlignRight : Text.AlignLeft
        font {
            family: K.fontFamily(root.fontFamily, root.kenv, Theme.fontUi)
            pixelSize: K.fontSize(root.textStyle, root.fontSize)
            weight: K.qtWeight(K.fontWeight(root.textStyle, root.fontWeight))
            italic: root.italic
            underline: root.underline
            strikeout: root.strikethrough
            letterSpacing: root.letterSpacing
            capitalization: root.textCase === "upper" ? Font.AllUppercase : root.textCase === "lower" ? Font.AllLowercase
                          : root.textCase === "title" ? Font.Capitalize : Font.MixedCase
        }
    }
}
