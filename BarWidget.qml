import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "vornashev.yandex-music"

  readonly property var logic: logicLoader.item
  readonly property bool hasTrack: logic ? logic.hasTrack : false
  readonly property bool playing: logic ? logic.playing : false
  readonly property bool opened: logic ? logic.opened : false
  readonly property bool popoutSwitchClosing: logic ? logic.popoutSwitchClosing : false

  function injectLogic() {
    if (!logic) return
    logic.bar = root.bar
    logic.settings = root.settings
    logic.anchorItem = playerLoader.item
    logic.hostWidget = root
  }
  function open() { if (logic) logic.open() }
  function close() { if (logic) logic.close() }
  function closeForPopoutSwitch() { if (logic) logic.closeForPopoutSwitch() }

  implicitWidth: playerLoader.item ? playerLoader.item.implicitWidth : 0
  implicitHeight: playerLoader.item ? playerLoader.item.implicitHeight : barSize
  onBarChanged: injectLogic()
  onSettingsChanged: injectLogic()

  Loader {
    id: logicLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("WidgetLogic.qml")
    onLoaded: {
      root.injectLogic()
      Qt.callLater(root.injectLogic)
    }
  }

  Loader {
    id: playerLoader
    anchors.fill: parent
    active: true
    source: Qt.resolvedUrl("BarPlayer.qml")
    onLoaded: {
      item.bar = root.bar
      item.logic = root.logic
      item.hostWidget = root
      root.injectLogic()
    }
  }

  Connections {
    target: root
    function onBarChanged() { if (playerLoader.item) playerLoader.item.bar = root.bar }
    function onLogicChanged() {
      if (playerLoader.item) playerLoader.item.logic = root.logic
      root.injectLogic()
    }
  }
}
