//@ pragma AppId org.goldengate.Installer
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
 AppWindow {
  id: win; title: "Install Golden Gate"; implicitWidth: 760; implicitHeight: 560; minimumSize: Qt.size(680,500); resizable: false
  Item {
   id: stage; anchors.fill: parent; property int step: 0; property var disks: []; property var disk: null; property string error: ""
   Process {
    id: scan; running: true; command: ["python3", Qt.resolvedUrl("installer/helper.py").toString().replace("file://",""), "disks"]
    stdout: StdioCollector { onStreamFinished: { try { stage.disks=JSON.parse(text) } catch(e){ stage.error="Storage devices could not be read." } } }
   }
   Column {
    anchors { fill: parent; margins: 42 }; spacing: 18
    Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: stage.step===0 ? "logo" : stage.step===1 ? "internaldrive" : "exclamationmark-triangle"; size: 64; tone: stage.step===2 ? "accent" : "auto" }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: stage.step===0 ? "Install Golden Gate" : stage.step===1 ? "Select the Disk Where Golden Gate Will Be Installed" : "Erase “" + (stage.disk?.model ?? "Disk") + " and Install Golden Gate?"; color: Theme.label; wrapMode: Text.WordWrap; font { family: Theme.fontUi; pixelSize: 25; weight: Font.DemiBold } }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 14 }; text: stage.step===0 ? "Golden Gate will guide you through installing this system on your computer." : stage.step===1 ? "Choose a destination. Removable live media is hidden to reduce the chance of selecting the installer USB." : "Everything currently on " + (stage.disk?.path ?? "this disk") + " will be permanently erased. This cannot be undone." }
    Item { width: 1; height: 8 }
    ListView {
     visible: stage.step===1; width: parent.width; height: 250; clip: true; model: stage.disks; spacing: 8
     delegate: Rectangle {
      required property var modelData; width: ListView.view.width; height: 62; radius: 13
      color: stage.disk?.path===modelData.path ? Qt.rgba(Theme.accent.r,Theme.accent.g,Theme.accent.b,.14) : (Theme.dark ? "#18ffffff" : "#0b000000")
      border { width: stage.disk?.path===modelData.path ? 2 : 0.5; color: stage.disk?.path===modelData.path ? Theme.accent : Theme.separator }
      Column { x:16; anchors.verticalCenter: parent.verticalCenter
       Text { text: modelData.model; color: Theme.label; font { family:Theme.fontUi; pixelSize:14; weight:Font.DemiBold } }
       Text { text: modelData.path + "  •  " + (modelData.size/1000000000).toFixed(1) + " GB"; color:Theme.secondaryLabel; font { family:Theme.fontUi; pixelSize:12 } }
      }
      TapHandler { onTapped: stage.disk=modelData }
     }
    }
    Text { visible: !!stage.error; width:parent.width; text:stage.error; color:"#ff453a"; horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
    Item { width:1; height:8 }
    Row {
     anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
     Button { visible: stage.step>0; text:"Back"; onClicked: stage.step-- }
     Button { text: stage.step===0 ? "Continue" : stage.step===1 ? "Continue" : "Erase and Continue"; prominent: stage.step<2; destructive: stage.step===2; enabled: stage.step!==1 || !!stage.disk
      onClicked: { if(stage.step<2) stage.step++; else handoff.running=true }
     }
    }
   }
   Process {
    id: handoff
    command: ["sh","-c","exec ghostty -e sudo archinstall"]
    onStarted: { stage.error="Opening the installation engine…"; win.visible=false }
    onExited: (code) => { win.visible=true; if(code!==0) stage.error="Installation did not complete. No success state was recorded; review the installer log before retrying." }
   }
  }
 }
}
