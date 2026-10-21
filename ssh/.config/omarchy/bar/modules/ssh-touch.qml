import QtQuick
import Quickshell
import Quickshell.Io

// Bar indicator for a pending YubiKey touch. ssh-askpass-notify writes "1" to
// $XDG_RUNTIME_DIR/ssh-touch-pending while OpenSSH waits for a touch and "0"
// when it is done; this collapses to nothing otherwise.
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  property bool pending: false

  implicitWidth: pending ? 28 : 0
  implicitHeight: bar ? bar.barSize : 26
  visible: pending

  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ssh-touch-pending"
    watchChanges: true
    blockAllReads: true
    onFileChanged: reload()
    onLoaded: root.pending = text().trim() === "1"
    onLoadFailed: root.pending = false
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    text: "󰝁"
    color: bar ? bar.urgent : "red"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 14
    SequentialAnimation on opacity {
      running: root.pending
      loops: Animation.Infinite
      NumberAnimation { to: 0.3; duration: 500 }
      NumberAnimation { to: 1.0; duration: 500 }
    }
  }
}
