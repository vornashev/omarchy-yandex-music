import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The menu shares confirmed state with the underlying card.
Item {
  id: root
  objectName: "artistMenuOverlay"
  required property var controller
  property bool wide: false
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  property bool opened: false
  property bool confirming: false
  property point anchorPoint: Qt.point(0, 0)
  readonly property bool blocked: controller.status.blocked === true
  readonly property bool failed: controller.uncertain || !!controller.snapshot.error
  readonly property bool artist: controller.spec.type === "artist"
  readonly property bool needsStatus: artist ? controller.status.blockKnown !== true
    : controller.status.favoriteKnown !== true || controller.status.pinnedKnown !== true
  signal editRequested()
  signal dismissed()

  visible: opened
  enabled: visible

  function open(anchor) {
    anchorPoint = anchor.mapToItem(root, anchor.width, anchor.height)
    confirming = false
    opened = true
    Qt.callLater(function() {
      if (root.opened) (artist && blockButton.enabled ? blockButton : closeButton).forceActiveFocus()
    })
  }
  function close() {
    if (!opened) return
    opened = false
    confirming = false
    dismissed()
  }
  function confirm() {
    confirming = true
    Qt.callLater(function() { confirmButton.forceActiveFocus() })
  }
  onWideChanged: close()

  MouseArea {
    anchors.fill: parent
    onClicked: root.close()
  }
  Pane {
    id: menu
    objectName: "artistActionsMenu"
    width: Math.min(Style.space(280), parent.width - Style.space(16))
    height: content.implicitHeight + topPadding + bottomPadding
    x: Math.max(0, Math.min(parent.width - width, root.anchorPoint.x - width))
    y: Math.max(0, Math.min(parent.height - height, root.anchorPoint.y + Style.space(4)))
    padding: Style.space(12)
    Keys.onEscapePressed: root.close()
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Backspace || (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier))) {
        root.close()
        event.accepted = true
      }
    }
    background: BorderSurface {
      color: Commons.Color.popups.background
      borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
      radius: Style.cornerRadius
      // Consume clicks in padding as well as on the controls.
      MouseArea { anchors.fill: parent }
    }
    contentItem: Column {
      id: content
      spacing: Style.space(8)
      Item {
        width: parent.width; height: Style.space(28)
        Text {
          anchors.left: parent.left; anchors.right: closeButton.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.controller.spec.title
          color: root.dim; font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
        }
        IconButton {
          id: closeButton
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          width: Style.space(28); height: width; horizontalPadding: 0
          iconText: "󰅖"; iconSize: Style.space(14); focusable: true
          foreground: root.dim; tooltipText: "Закрыть"
          onClicked: root.close()
        }
      }
      component MenuAction: IconButton {
        width: parent.width; height: Style.space(32)
        leftAlign: true; focusable: true
        foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
        opacity: enabled ? 1 : .4
      }
      MenuAction {
        visible: root.controller.status.editable === true
        iconText: "󰒓"
        text: "Редактировать плейлист"
        enabled: !root.controller.busy
        onClicked: root.editRequested()
      }
      IconButton {
        id: blockButton
        objectName: "artistBlock"
        visible: root.artist && !root.confirming
        width: parent.width; height: Style.space(36)
        leftAlign: true; focusable: true
        enabled: !root.controller.busy && !root.failed && root.controller.status.blockKnown === true
        opacity: enabled ? 1 : .4
        iconText: root.blocked ? "󰄬" : "󰋔"
        text: root.blocked ? "Вернуть в рекомендации" : "Не рекомендовать"
        foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
        onClicked: root.confirm()
      }
      Text {
        visible: root.confirming
        width: parent.width
        textFormat: Text.PlainText
        text: root.blocked ? "Вернуть исполнителя в рекомендации?" : "Не рекомендовать этого исполнителя?"
        wrapMode: Text.WordWrap
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
      }
      Row {
        visible: root.confirming
        spacing: Style.space(8)
        IconButton {
          id: confirmButton
          objectName: "artistBlockConfirm"
          text: "Подтвердить"; bordered: true; focusable: true
          enabled: blockButton.enabled
          foreground: Commons.Color.accent; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
          onClicked: {
            root.confirming = false
            root.controller.send("block", !root.blocked, true)
            closeButton.forceActiveFocus()
          }
        }
        IconButton {
          objectName: "artistBlockCancel"
          text: "Отмена"; focusable: true
          foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
          onClicked: { root.confirming = false; blockButton.forceActiveFocus() }
        }
      }
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.controller.message || (root.controller.busy ? "Проверяем состояние…"
          : root.needsStatus ? "Не удалось проверить состояние" : "")
        wrapMode: Text.WordWrap
        color: root.failed ? Commons.Color.urgent : root.dim
        font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
      }
      IconButton {
        visible: root.failed || (!root.controller.busy && root.needsStatus)
        text: "Обновить состояние"; iconText: "󰑐"; focusable: true
        enabled: !root.controller.pending && root.controller.snapshot.busy !== true && root.controller.snapshot.loading !== true
        foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
        onClicked: { root.confirming = false; root.controller.reload() }
      }
    }
  }
}
