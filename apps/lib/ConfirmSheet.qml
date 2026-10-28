// "Are you sure?" with two buttons: the common case of Alert.
//   ConfirmSheet {
//       id: confirm
//       title: "Empty the Trash?"; message: "The 12 items in it will be gone for good."
//       confirmText: "Empty Trash"; destructive: true
//       onConfirmed: trash.empty()
//   }
//   confirm.open()
// Destructive, the confirm button is red and Return means Cancel; otherwise
// confirming is the default. Escape and clicking outside cancel.
import QtQuick

Alert {
    property string confirmText: "OK"
    property string cancelText: "Cancel"
    property bool destructive: false
    signal confirmed()
    signal cancelled()
    buttons: [{ text: confirmText, role: destructive ? "destructive" : "default" }, { text: cancelText, role: "cancel" }]
    onChosen: (role) => role === "cancel" ? cancelled() : confirmed()
}
