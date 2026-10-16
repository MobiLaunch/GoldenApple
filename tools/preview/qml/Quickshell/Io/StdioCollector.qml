import QtQuick
QtObject {
    property string text
    property bool waitForEnd: true
    signal streamFinished()
    function __feed(t) { text = t; streamFinished() }
}
