import QtQuick
import qs.Commons

// 24 px wide, full-height hit zone with a centred 14 px icon. States: default, hover (fg 8 %
// fill), pressed (accent fill, 13 px accent icon, no animation), keyboard focus
// (1 px accent frame), disabled (35 %), plus a pending/flash/error treatment
// used by the like button.
Item {
  id: root

  property var bar: null
  property string name: ""
  property string glyph: ""
  property bool filled: false
  property color foreground: Color.foreground
  property color iconColor: foreground
  property string tooltip: ""
  property real iconOpacity: 1
  property bool flash: false
  property bool errorDot: false
  property alias containsMouse: mouse.containsMouse
  readonly property bool pressed: mouse.pressed

  signal clicked()
  signal wheel(var wheel)

  width: Style.space(24)
  height: parent ? parent.height : Style.space(24)
  activeFocusOnTab: enabled
  opacity: enabled ? 1 : .35

  Keys.onReturnPressed: if (enabled) root.clicked()
  Keys.onSpacePressed: if (enabled) root.clicked()

  Rectangle {
    anchors.fill: parent
    radius: root.flash ? width / 2 : Style.cornerRadius
    color: root.pressed || root.flash
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .2)
      : (mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
        : "transparent")
    border.width: root.activeFocus ? 1 : 0
    border.color: Color.accent
    Behavior on color {
      enabled: !root.pressed
      ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
    }
  }
  LucideIcon {
    anchors.centerIn: parent
    name: root.name; glyph: root.glyph; filled: root.filled
    size: root.pressed ? Style.space(13) : Style.space(14)
    color: root.pressed ? Color.accent : (mouse.containsMouse ? Qt.lighter(root.iconColor, 1.15) : root.iconColor)
    opacity: root.iconOpacity
  }
  Rectangle {
    visible: root.errorDot
    x: Style.space(3); y: Style.space(2)
    width: Style.space(6); height: width; radius: width / 2
    color: Color.urgent
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
    onWheel: function(wheel) { root.wheel(wheel) }
    onEntered: if (root.bar && root.tooltip !== "") root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
