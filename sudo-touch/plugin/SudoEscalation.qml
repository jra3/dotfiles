import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "SudoModel.js" as Model

// Sudo escalation dialog. The root PAM hook (sudo-escalation-notify) writes a
// JSON record per sudo into /run/sudo-escalation/ before pam_u2f starts
// waiting for a touch, and an .approved marker beside it once the touch has
// landed. This service watches the directory and keeps a centred dialog up
// until the sudo resolves: approved, denied from here, or gone on its own.
// Root starts nothing in the session; the dialog is the user's own process
// reading root's files.
//
// The habit this is built for: the key blinks, the dialog says why. A blink
// with no dialog is the alarm.
Item {
  id: root

  readonly property string recordDir: "/run/sudo-escalation"
  // The hook's unprivileged dry run writes here. Anything from this
  // directory is drawn with a warning: the user, and so an agent, can write it.
  readonly property string testDir: Quickshell.env("XDG_RUNTIME_DIR") + "/sudo-escalation-test"

  // libfido2's wait for a touch, measured at 29s on pam_u2f 1.3 / YubiKey 5.
  property int touchTimeout: 30
  // Records older than this when first seen are history, not a live sudo.
  property int staleAfter: 300
  property int approvedLinger: 1500
  property int endedLinger: 3000

  property string fontFamily: Style.font.family
  property color accent: Color.polkit.accent
  property color background: Color.polkit.background
  property color foreground: Color.polkit.text
  property color urgent: Color.polkit.textError
  property color border: Color.polkit.border
  property color scrim: Color.polkit.scrim
  property var borderSpec: Border.surfaceSpec("polkit", "border", border, Math.max(1, Style.space(2)), "border-alpha")
  property color muted: Util.alpha(foreground, 0.55)
  property color blockFill: Util.alpha(foreground, 0.06)

  property var pending: []
  property var seen: ({})
  property int approvedToday: 0
  property string approvedDay: ""
  property real now: Date.now() / 1000
  property bool recordDirReady: false
  property bool testDirReady: false

  readonly property var current: pending.length ? pending[0] : null
  readonly property var desc: current ? current.desc : null
  readonly property bool dialogVisible: current !== null
  readonly property int waiting: Math.max(0, pending.length - 1)
  readonly property real remaining: current ? touchTimeout - (now - current.record.time) : 0
  // While the key blinks the dialog is modal. Once the window closes sudo
  // may be asking for a password in another window (an askpass dialog under
  // sudo -A): the scrim goes and clicks outside the card pass through to it.
  readonly property bool touchWindowOpen: !!current && !current.outcome && remaining > 0

  function readFile(path) {
    reader.path = path
    return reader.text()
  }

  function ingest(model, dirPath, isTest) {
    var approved = {}
    var records = []
    var present = {}
    for (var i = 0; i < model.count; i++) {
      var name = String(model.get(i, "fileName"))
      var key = dirPath + "/" + name
      present[key] = true
      if (name.slice(-9) === ".approved") approved[name.slice(0, -9)] = true
      else if (name.slice(-5) === ".json") records.push({ name: name, key: key, base: name.slice(0, -5), mtime: model.get(i, "fileModified") })
    }

    var nextSeen = {}
    for (var k in seen) if (present[k]) nextSeen[k] = true
    var added = []
    for (var r = 0; r < records.length; r++) {
      var rec = records[r]
      if (nextSeen[rec.key]) continue
      nextSeen[rec.key] = true
      var mtime = rec.mtime ? rec.mtime.getTime() / 1000 : 0
      if (Date.now() / 1000 - mtime > staleAfter) continue
      if (approved[rec.base]) continue
      var parsed = Model.parseRecord(readFile(rec.key))
      if (!parsed) { console.warn("sudo-escalation: unreadable record " + rec.key); continue }
      var entry = {
        key: rec.key, base: rec.base, dir: dirPath, test: isTest,
        record: parsed, desc: Model.describe(parsed),
        outcome: "", settledAt: 0, denying: false, watcher: null, ingestedAt: Date.now()
      }
      entry.watcher = watcherComponent.createObject(root, { key: rec.key, pid: parsed.pid })
      console.log("sudo-escalation: pending pid " + parsed.pid + " (" + entry.desc.headline + ")")
      added.push(entry)
    }
    seen = nextSeen
    if (added.length) pending = pending.concat(added)

    for (var p = 0; p < pending.length; p++) {
      var e = pending[p]
      if (e.dir === dirPath && !e.outcome && approved[e.base]) settle(e, "approved")
    }
  }

  function settle(entry, outcome) {
    if (entry.outcome) return
    console.log("sudo-escalation: pid " + entry.record.pid + " " + outcome)
    entry.outcome = outcome
    entry.settledAt = Date.now()
    if (entry.watcher) entry.watcher.running = false
    if (outcome === "approved") {
      rollDay()
      approvedToday++
    }
    pending = pending.slice()
  }

  function gone(key) {
    for (var i = 0; i < pending.length; i++) {
      var e = pending[i]
      if (e.key === key) settle(e, e.denying ? "denied" : "ended")
    }
  }

  // The user may signal their own sudo (real uid), and SIGTERM ends the
  // touch wait within a few seconds; SIGINT is deferred until it times out.
  // A sudo -A waiting on its askpass helper sits on SIGTERM until the helper
  // exits, so the helper and its children go too, and whatever is still
  // alive after 3s gets SIGKILL. Descendants that are already root (the
  // command itself, if the touch beat the click) refuse the signal.
  readonly property string denyScript: `
    tree() { for c in $(pgrep -P "$1"); do tree "$c"; done; echo "$1"; }
    pids=$(tree "$1")
    kill -TERM $pids 2>/dev/null
    for _ in 1 2 3 4 5 6; do kill -0 "$1" 2>/dev/null || exit 0; sleep 0.5; done
    kill -KILL $(tree "$1") 2>/dev/null
  `
  function deny(entry) {
    if (!entry || entry.outcome || entry.denying) return
    entry.denying = true
    Quickshell.execDetached(["sh", "-c", denyScript, "sudo-escalation-deny", String(entry.record.pid)])
    // The click is the answer: close now and let the kill finish behind it.
    settle(entry, "denied")
  }

  function lingerFor(entry) {
    // A sudo already gone when its record was first seen (a shell restart
    // picking up recent history) was never a live request: no receipt.
    if (entry.outcome === "ended" && entry.settledAt - entry.ingestedAt < 2000) return 0
    if (entry.outcome === "denied") return 0
    return entry.outcome === "approved" ? approvedLinger : endedLinger
  }

  function prune() {
    var keep = []
    var changed = false
    for (var i = 0; i < pending.length; i++) {
      var e = pending[i]
      if (e.outcome && Date.now() - e.settledAt >= lingerFor(e)) {
        if (e.watcher) e.watcher.destroy()
        changed = true
      } else keep.push(e)
    }
    if (changed) pending = keep
  }

  function rollDay() {
    var today = new Date().toDateString()
    if (approvedDay !== today) { approvedDay = today; approvedToday = 0 }
  }

  function statusText(entry) {
    if (!entry) return ""
    if (entry.outcome === "approved") return "approved: the touch landed"
    if (entry.outcome === "denied") return "denied"
    if (entry.outcome === "ended") return "sudo ended with no touch"
    if (entry.denying) return "denying…"
    if (entry.test) return "test record: no sudo is waiting and no key is blinking"
    var left = Math.ceil(remaining)
    if (left > 0) return "the key is blinking · " + left + "s"
    return "touch window closed · sudo may be asking for a password"
  }

  function statusColor(entry) {
    if (!entry) return foreground
    if (entry.outcome === "approved") return accent
    if (entry.outcome === "denied" || entry.outcome === "ended" || entry.denying) return urgent
    return remaining > 0 ? foreground : urgent
  }

  // blockAllReads, not just blockLoading: without it text() after a path
  // change hands back the previous file's contents.
  FileView {
    id: reader
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  Component {
    id: watcherComponent
    // Polls the sudo front end's pid. kill -0 works because sudo keeps the
    // caller's real uid; a pid the user cannot signal reads as gone.
    // Only scalars cross into this object: an entry passed through
    // createObject's property map arrives as a copy, and settling the copy
    // leaves the dialog up forever.
    Process {
      property string key
      property int pid
      Component.onCompleted: {
        command = ["sh", "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.5; done", "sudo-escalation-watch", String(pid)]
        running = true
      }
      onExited: function(code, status) { root.gone(key) }
    }
  }

  // omarchy-shell jra3.sudo-escalation status
  IpcHandler {
    target: "jra3.sudo-escalation"
    function status(): string {
      var out = []
      for (var i = 0; i < root.pending.length; i++) {
        var e = root.pending[i]
        out.push({ pid: e.record.pid, headline: e.desc.headline, outcome: e.outcome, denying: e.denying, test: e.test, watcherRunning: e.watcher ? e.watcher.running : null })
      }
      return JSON.stringify({ pending: out, approvedToday: root.approvedToday, recordDirReady: root.recordDirReady, testDirReady: root.testDirReady })
    }
  }

  // The directories may not exist yet: /run/sudo-escalation is created by
  // the first sudo after boot unless tmpfiles.d made it, and the test dir by
  // the first dry run. A folder model on a missing directory never wakes, so
  // probe until each exists before pointing a model at it.
  Process {
    id: recordDirProbe
    command: ["test", "-d", root.recordDir]
    onExited: function(code) { if (code === 0) root.recordDirReady = true }
  }
  Process {
    id: testDirProbe
    command: ["test", "-d", root.testDir]
    onExited: function(code) { if (code === 0) root.testDirReady = true }
  }
  Timer {
    interval: 10000
    repeat: true
    triggeredOnStart: true
    running: !root.recordDirReady || !root.testDirReady
    onTriggered: {
      if (!root.recordDirReady && !recordDirProbe.running) recordDirProbe.running = true
      if (!root.testDirReady && !testDirProbe.running) testDirProbe.running = true
    }
  }

  FolderListModel {
    id: recordModel
    folder: root.recordDirReady ? "file://" + root.recordDir : ""
    nameFilters: ["*.json", "*.approved"]
    showDirs: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    onStatusChanged: if (status === FolderListModel.Ready && root.recordDirReady) root.ingest(recordModel, root.recordDir, false)
  }

  FolderListModel {
    id: testModel
    folder: root.testDirReady ? "file://" + root.testDir : ""
    nameFilters: ["*.json", "*.approved"]
    showDirs: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    onStatusChanged: if (status === FolderListModel.Ready && root.testDirReady) root.ingest(testModel, root.testDir, true)
  }

  Timer {
    interval: 250
    repeat: true
    running: root.pending.length > 0
    onTriggered: {
      root.now = Date.now() / 1000
      root.prune()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.dialogVisible
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "sudo-escalation"
      WlrLayershell.layer: WlrLayer.Overlay
      // The terminal keeps the keyboard: after the touch window closes sudo
      // may fall back to a password prompt there.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: root.touchWindowOpen ? fullRegion : cardRegion

      property Region fullRegion: Region { width: panel.width; height: panel.height }
      property Region cardRegion: Region { item: card }

      Rectangle {
        anchors.fill: parent
        color: root.scrim
        opacity: root.touchWindowOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
      }

      MouseArea { anchors.fill: parent; enabled: root.touchWindowOpen }

      BorderSurface {
        id: card
        width: Math.min(Style.space(760), panel.width - Style.gapsOut * 4)
        height: content.implicitHeight + contentTopInset + contentBottomInset
        radius: Style.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        ColumnLayout {
          id: content
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: card.contentTopInset
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          spacing: Style.spacing.lg

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            // Who asked is the title; the command block below says for what.
            Text {
              textFormat: Text.PlainText
              text: root.desc ? "sudo request from " + root.desc.origin : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.desc ? "as " + root.desc.target : ""
              color: root.desc && root.desc.target === "root" ? root.muted : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              textFormat: Text.PlainText
              visible: root.waiting > 0
              text: "+" + root.waiting + " waiting"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              text: root.approvedToday + " touched today"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: commandText.implicitHeight + Style.spacing.lg * 2
            radius: Math.max(0, Style.cornerRadius - 4)
            color: root.blockFill

            Text {
              id: commandText
              textFormat: Text.PlainText
              anchors.fill: parent
              anchors.margins: Style.spacing.lg
              text: root.desc ? root.desc.lines.join("\n") : ""
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              wrapMode: Text.WrapAnywhere
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Style.spacing.lg
            rowSpacing: Style.spacing.xs

            Text { textFormat: Text.PlainText; text: "from"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text {
              textFormat: Text.PlainText
              text: root.desc ? root.desc.from + "  ·  " + root.desc.tty : ""
              color: root.desc && root.current.record.tty ? root.foreground : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              Layout.fillWidth: true
            }

            Text { textFormat: Text.PlainText; text: "in"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text {
              textFormat: Text.PlainText
              text: root.desc ? root.desc.cwd : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              Layout.fillWidth: true
            }

            Text { textFormat: Text.PlainText; text: "typed"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text {
              textFormat: Text.PlainText
              text: root.desc ? root.desc.typed : ""
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              Layout.fillWidth: true
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !!root.desc && root.desc.warnings.length > 0
            text: root.desc ? root.desc.warnings.join("\n") : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              text: root.statusText(root.current)
              color: root.statusColor(root.current)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Button {
              text: "Deny"
              bordered: true
              visible: !!root.current && !root.current.outcome
              enabled: !!root.current && !root.current.denying
              foreground: root.urgent
              accent: root.urgent
              fontFamily: root.fontFamily
              onClicked: root.deny(root.current)
            }
          }

          Text {
            textFormat: Text.PlainText
            text: !root.current ? ""
              : root.current.test
                ? "TEST RECORD from " + root.testDir + ", which the user can write"
                : "record written by root from sudo's own argv · pid " + root.current.record.pid + " · " + Model.clock(root.current.record.time)
            color: root.current && root.current.test ? root.urgent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
