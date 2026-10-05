import QtQuick
import qs.Commons
import qs.Ui

// One row of the wide layout's navigation rail.
BorderSurface {
  id: root

  property string glyph: ""
  property string label: ""
  property string keyHint: ""
  property bool selected: false
  property bool secondary: false
  property bool dense: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  signal clicked()

  height: dense ? Style.space(32) : Style.space(37)
  radius: Style.cornerRadius
  color: selected ? (secondary ? Style.normalFillFor(foreground, Color.accent)
    : Style.selectedFillFor(foreground, Color.accent))
    : (area.containsMouse ? Style.hoverFillFor(foreground, Color.accent) : "transparent")
  borderSpec: Border.none()

  Rectangle {
    visible: root.selected && !root.secondary
    width: Style.space(2); height: parent.height
    color: Color.accent
  }
  LucideIcon {
    id: glyphText
    anchors.left: parent.left; anchors.leftMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.glyph
    color: root.selected ? Color.accent : root.dim
    fontFamily: root.fontFamily; size: Style.space(15)
  }
  Text {
    textFormat: Text.PlainText
    anchors.left: glyphText.right; anchors.leftMargin: Style.space(12)
    anchors.right: hint.left; anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label; elide: Text.ElideRight
    color: root.selected ? root.foreground : root.dim
    font.family: root.fontFamily; font.pixelSize: root.dense ? Style.font.bodySmall : Style.font.body
    font.weight: root.selected ? (root.secondary ? Font.DemiBold : Font.Bold) : Font.Normal
  }
  Text {
    id: hint
    textFormat: Text.PlainText
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    text: root.keyHint; color: root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
  MouseArea {
    id: area
    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
