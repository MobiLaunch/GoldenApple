import QtQuick
QtObject {
    property string config; property string configDirectory; property string user; property bool active
    property string message; property bool messageIsError; property bool responseRequired; property bool responseVisible
    signal completed(int result); signal error(int error); signal pamMessage()
    function start() { return true } function abort() {} function respond(r) {}
}
