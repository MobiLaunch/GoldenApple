// A text field that saves when you press Return or leave it.
import QtQuick
import "../../lib"

TextField {
    id: field
    property string value: ""
    signal committed(string value)
    width: 300
    height: 28
    text: value
    onValueChanged: if (!input.activeFocus) text = value
    onAccepted: commit()
    input.onActiveFocusChanged: if (!input.activeFocus) commit()
    function commit() { if (text.trim() !== value) committed(text.trim()) }
}
