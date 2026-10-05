import QtQuick
import qs.Commons
import qs.Ui

// Persistent player strip. `wide` sits under the wide layout's pages,
// `compact` under the compact layout's Library/Search pages and `popup` is the
// whole Mini popup (cover, details, controls, expand button).
Item {
  id: root

  required property var panel
  property string mode: "compact"
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property bool isWide: mode === "wide"
  readonly property bool isPopup: mode === "popup"
  readonly property real fraction: Math.min(1,
    panel.displayPosition / Math.max(1, Number(panel.data.duration || 1)))
  readonly property real coverSize: isPopup ? Style.space(64) : (isWide ? Style.space(44) : Style.space(36))

  implicitHeight: isPopup ? Style.space(101) : (isWide ? Style.space(72) : Style.space(56))

  Rectangle {
    visible: !root.isPopup
    anchors.fill: parent
    color: Style.normalFillFor(root.fg, Color.accent)
  }
  Rectangle {
    visible: !root.isPopup
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
  }
  // thin progress line (compact: top, popup: bottom)
  Rectangle {
    visible: root.mode === "compact" || root.isPopup
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: root.isPopup ? undefined : parent.top
    anchors.bottom: root.isPopup ? parent.bottom : undefined
    height: root.isPopup ? Style.space(3) : Style.space(2)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .12)
    Rectangle { width: parent.width * root.fraction; height: parent.height; color: Color.accent }
  }

  CatalogImage {
    id: cover
    anchors.left: parent.left
    anchors.leftMargin: root.isPopup ? Style.space(12) : (root.isWide ? Style.space(20) : Style.space(12))
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.isPopup ? -Style.space(1) : 0
    width: root.coverSize; height: width
    requestedSource: String(panel.data.artUrl || "")
    foreground: root.fg; fontFamily: root.ff
    fillMode: Image.PreserveAspectCrop
  }

  Column {
    id: meta
    anchors.left: cover.right; anchors.leftMargin: Style.space(root.isPopup ? 12 : (root.isWide ? 16 : 10))
    anchors.verticalCenter: cover.verticalCenter
    anchors.verticalCenterOffset: root.isPopup ? -Style.space(18) : 0
    width: root.isPopup ? parent.width - cover.width - Style.space(36)
      : (root.isWide ? Style.space(200) : parent.width - cover.width - Style.space(150))
    spacing: Style.space(2)
    Text {
      textFormat: Text.PlainText
      width: parent.width; elide: Text.ElideRight
      text: panel.hasTrack ? String(panel.data.title) : "Яндекс Музыка"
      color: root.fg; font.family: root.ff
      font.pixelSize: root.isWide ? Style.font.body : Style.font.bodySmall; font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width; elide: Text.ElideRight
      text: String(panel.data.artist || "")
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
    }
  }
  MouseArea {
    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
    anchors.right: meta.right
    cursorShape: Qt.PointingHandCursor
    onClicked: root.isPopup ? panel.setPopupLayout("compact") : panel.selectPage(0)
  }

  // ── compact / popup controls ──────────────────────────────────────────
  Row {
    visible: !root.isWide
    anchors.right: parent.right; anchors.rightMargin: Style.space(root.isPopup ? 12 : 12)
    anchors.verticalCenter: root.isPopup ? undefined : parent.verticalCenter
    anchors.bottom: root.isPopup ? parent.bottom : undefined
    anchors.bottomMargin: Style.space(14)
    spacing: Style.space(root.isPopup ? 2 : 10)
    IconButton {
      visible: root.isPopup
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: panel.data.liked ? "󰋑" : "󰋕"
      foreground: panel.data.liked ? Color.accent : root.fg
      enabled: panel.hasTrack
      onClicked: panel.transport("toggleLike")
    }
    IconButton {
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰒮"; foreground: root.fg; tooltipText: "Предыдущий (P)"
      enabled: panel.hasTrack
      onClicked: panel.transport("previousTrack")
    }
    IconButton {
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: panel.playing ? "󰏤" : "󰐊"
      foreground: root.fg; tooltipText: panel.playing ? "Пауза (Space)" : "Продолжить (Space)"
      enabled: panel.hasTrack
      onClicked: panel.transport("togglePlayback")
    }
    IconButton {
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰒭"; foreground: root.fg; tooltipText: "Следующий (N)"
      enabled: panel.hasTrack
      onClicked: panel.transport("nextTrack")
    }
    IconButton {
      visible: root.isPopup
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰊓"; bordered: true; foreground: root.dim
      tooltipText: "Компактный вид (W)"
      onClicked: panel.setPopupLayout("compact")
    }
  }

  // ── wide controls ─────────────────────────────────────────────────────
  Row {
    id: wideControls
    visible: root.isWide
    anchors.left: meta.right; anchors.leftMargin: Style.space(40)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(12)
    IconButton {
      width: Style.space(32); height: Style.space(32); anchors.verticalCenter: parent.verticalCenter
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: panel.data.liked ? "󰋑" : "󰋕"
      foreground: panel.data.liked ? Color.accent : root.fg
      enabled: panel.hasTrack
      onClicked: panel.transport("toggleLike")
    }
    IconButton {
      width: Style.space(32); height: Style.space(32); anchors.verticalCenter: parent.verticalCenter
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰒮"; foreground: root.fg; tooltipText: "Предыдущий (P)"
      enabled: panel.hasTrack
      onClicked: panel.transport("previousTrack")
    }
    PlayButton { size: Style.space(38); panel: root.panel }
    IconButton {
      width: Style.space(32); height: Style.space(32); anchors.verticalCenter: parent.verticalCenter
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰒭"; foreground: root.fg; tooltipText: "Следующий (N)"
      enabled: panel.hasTrack
      onClicked: panel.transport("nextTrack")
    }
  }
  Item {
    visible: root.isWide
    anchors.left: wideControls.right; anchors.leftMargin: Style.space(20)
    anchors.right: wideTail.left; anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(20)
    Text {
      id: posText
      textFormat: Text.PlainText
      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
      text: panel.formatTime(panel.playbackPosition)
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: durText
      textFormat: Text.PlainText
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      text: panel.formatTime(panel.data.duration)
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
    SeekBar {
      anchors.left: posText.right; anchors.right: durText.left
      anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -Style.space(2)
      panel: root.panel; showTimes: false
    }
  }
  Row {
    id: wideTail
    visible: root.isWide
    anchors.right: parent.right; anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
    IconButton {
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: panel.data.muted === true ? "󰖁" : "󰕾"
      foreground: root.dim; tooltipText: panel.data.muted === true ? "Включить звук" : "Выключить звук"
      onClicked: panel.transport("toggleMute")
    }
    IconButton {
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(16)
      iconText: "󰲸"; foreground: root.dim; tooltipText: "Очередь"
      onClicked: panel.selectPage(0)
    }
  }
}
