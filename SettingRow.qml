import QtQuick
import qs.Commons

// Label (+ optional description) on the left, any control on the right and a
// hairline divider below. Children are placed in the control slot.
Item {
  id: root

  property string label: ""
  property string description: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  property bool divider: true
  property real minHeight: Style.space(38)
  default property alias control: slot.data

  implicitHeight: Math.max(minHeight, texts.implicitHeight + Style.space(16))

  Column {
    id: texts
    anchors.left: parent.left
    anchors.right: slot.left; anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    Text {
      textFormat: Text.PlainText
      width: parent.width; elide: Text.ElideRight
      text: root.label; color: root.foreground
      font.family: root.fontFamily; font.pixelSize: Style.font.body
    }
    Text {
      textFormat: Text.PlainText
      visible: root.description !== ""
      width: parent.width; elide: Text.ElideRight
      text: root.description; color: root.dim
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
  }
  Item {
    id: slot
    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width; height: childrenRect.height
  }
  Rectangle {
    visible: root.divider
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
  }
}
