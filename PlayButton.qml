import QtQuick
import qs.Commons
import qs.Ui

// Round accent play/pause button with a soft accent fill.
IconButton {
  id: root

  required property var panel
  property real size: Style.space(48)

  width: size; height: size; radius: size / 2
  horizontalPadding: 0; verticalPadding: 0
  iconSize: Math.round(size * .42)
  tooltipText: panel.playing ? "Пауза (Space)" : "Продолжить (Space)"
  foreground: Color.accent; bordered: true
  background: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .16)
  enabled: panel.hasTrack
  opacity: enabled ? 1 : .4
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  onClicked: panel.transport("togglePlayback")

  LucideIcon {
    z: 2; anchors.centerIn: parent
    anchors.horizontalCenterOffset: panel.playing ? 0 : Style.space(2)
    glyph: panel.playing ? "󰏤" : "󰐊"
    color: root.foreground; fontFamily: panel.fontFamily
    size: root.iconSize
  }
}
