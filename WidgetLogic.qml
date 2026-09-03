import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-yandex-music"
  property var data: ({ title: "", artist: "", playing: false })
  property string statusError: ""
  readonly property bool hasTrack: String(data.title || "") !== ""
  readonly property bool loading: data.loading === true || data.connecting === true || data.restoring === true
  readonly property string error: statusError || String(data.error || "")
  readonly property bool playing: data.playing === true
  readonly property string shortTitle: {
    var title = String(data.title || "")
    return title.length > 28 ? title.slice(0, 28) + "…" : title
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = root.anchorItem
    target.hostWidget = root.hostWidget
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function showArtist(artistId) {
    if (!artistId) return
    if (panelLoader.item) panelLoader.item.page = 0
    open()
    action("artist", artistId)
  }

  function refresh() {
    if (!statusProcess.running) {
      statusProcess.command = [cli, "status"]
      statusProcess.running = true
    }
  }
  function action(name, argument) {
    if (!actionProcess.running) {
      var args = [cli, name]
      if (argument !== undefined && argument !== null) args.push(String(argument))
      actionProcess.command = args
      actionProcess.running = true
    }
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onAnchorItemChanged: injectPanel()

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.statusError = "Фоновый музыкальный сервис недоступен"
        return
      }
      try {
        root.data = JSON.parse(statusOut.text || "{}")
        root.statusError = ""
      } catch (e) {
        root.statusError = "Музыкальный сервис вернул некорректный ответ"
      }
    }
  }
  Process {
    id: actionProcess
    command: []
    onExited: settle.restart()
  }
  Timer {
    interval: root.opened || root.playing ? 1000 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    id: settle
    interval: 300
    repeat: false
    onTriggered: root.refresh()
  }
  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
