import QtQuick
import qs.Commons

// Seekable progress track. Seeking is previewed while dragging and committed
// by Panel on release; `showTimes` draws position/duration below the track.
Item {
  id: root

  required property var panel
  property bool showTimes: true
  property real trackHeight: Style.space(4)
  readonly property color fg: panel.foreground
  readonly property real fraction: Math.min(1,
    panel.displayPosition / Math.max(1, Number(panel.data.duration || 1)))

  implicitHeight: trackHeight + (showTimes ? Style.space(21) : Style.space(12))

  Rectangle {
    id: track
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: parent.top; anchors.topMargin: showTimes ? Style.space(4) : Style.space(6)
    height: root.trackHeight
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .12)
    Rectangle {
      width: parent.width * root.fraction
      height: parent.height
      color: Color.accent
    }
    MouseArea {
      id: seekDrag
      anchors.fill: parent
      anchors.topMargin: -Style.space(8); anchors.bottomMargin: -Style.space(8)
      enabled: panel.hasTrack
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      preventStealing: true
      onPressed: function(mouse) {
        panel.seeking = true
        panel.previewSeek(mouse, seekDrag)
      }
      onPositionChanged: function(mouse) {
        if (pressed) panel.previewSeek(mouse, seekDrag)
      }
      onReleased: function(mouse) {
        panel.previewSeek(mouse, seekDrag)
        panel.commitSeek()
      }
      onCanceled: panel.seeking = false
    }
  }
  Text {
    textFormat: Text.PlainText
    visible: root.showTimes
    anchors.left: parent.left; anchors.top: track.bottom; anchors.topMargin: Style.space(6)
    text: panel.formatTime(panel.playbackPosition)
      + (panel.seeking && panel.pendingSeek >= 0 ? "  (" + panel.formatTime(panel.pendingSeek) + ")" : "")
    color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall
  }
  Text {
    textFormat: Text.PlainText
    visible: root.showTimes
    anchors.right: parent.right; anchors.top: track.bottom; anchors.topMargin: Style.space(6)
    text: panel.formatTime(panel.data.duration)
    color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall
  }
}
