import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var logic: null
  property var hostWidget: null
  readonly property bool hasTrack: logic ? logic.hasTrack : false
  readonly property bool playing: logic ? logic.playing : false
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string label: {
    if (!hasTrack) return "Я.Музыка"
    var artist = String(logic.data.artist || "")
    var title = String(logic.data.title || "")
    return artist ? artist + " — " + title : title
  }

  implicitWidth: controls.width + Style.space(12)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: controls
    anchors.centerIn: parent
    spacing: Style.space(5)

    Item {
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: "󰒮"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("previous")
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Предыдущий трек")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: root.playing ? "󰏤" : "󰐊"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("pause")
        onEntered: if (root.bar) root.bar.showTooltip(parent, root.playing ? "Пауза" : "Продолжить")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: "󰒭"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("next")
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Следующий трек")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    BorderSurface {
      id: cover
      width: Style.space(20); height: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(2)
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.none()
      Image {
        anchors.fill: parent; source: root.logic && root.logic.data.artUrl ? root.logic.data.artUrl : ""
        fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: source !== ""
      }
      Text {
        anchors.centerIn: parent; visible: !root.logic || !root.logic.data.artUrl
        text: "󰝚"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: labelSlot
      width: Style.space(230); height: root.implicitHeight
      clip: true

      Row {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(5)

        Text {
          id: artistLabel
          width: root.hasTrack ? Math.min(implicitWidth, Style.space(105)) : 0
          text: root.logic ? String(root.logic.data.artist || "") : ""
          color: root.foreground; font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
        }

        Text {
          visible: root.hasTrack; text: "—"; color: root.foreground
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: titleLabel
          width: Math.max(0, labelSlot.width - artistLabel.width
            - (root.hasTrack ? Style.space(20) : 0))
          text: root.hasTrack && root.logic ? String(root.logic.data.title || "") : "Я.Музыка"
          color: root.foreground; font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
        }
      }
    }
  }

  MouseArea {
    x: controls.x + cover.x
    y: 0
    width: labelSlot.x + labelSlot.width - cover.x
    height: root.height
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.logic) root.logic.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.label)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Rectangle {
    visible: root.hasTrack
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: Style.space(2); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
    Rectangle {
      width: parent.width * (root.logic
        ? Math.min(1, Number(root.logic.data.position || 0) / Math.max(1, Number(root.logic.data.duration || 1)))
        : 0)
      height: parent.height; color: Color.accent
    }
  }
}
