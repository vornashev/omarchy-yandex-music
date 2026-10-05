import QtQuick
import qs.Commons
import qs.Ui

// Selectable tile for My Wave settings: glyph above a label (`vertical`) or
// glyph beside a title and subtitle.
BorderSurface {
  id: root

  property string glyph: ""
  property string title: ""
  property string subtitle: ""
  property bool selected: false
  property bool vertical: true
  property bool stacked: false
  property bool busy: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  signal clicked()

  radius: Style.cornerRadius
  opacity: busy ? .6 : 1
  color: selected ? Style.selectedFillFor(foreground, Color.accent)
    : (area.containsMouse ? Style.hoverFillFor(foreground, Color.accent)
      : Style.normalFillFor(foreground, Color.accent))
  borderSpec: Border.controlSpec(selected ? "selected" : "normal", foreground, Color.accent)

  Column {
    visible: root.vertical && !root.stacked
    anchors.centerIn: parent
    spacing: Style.space(8)
    LucideIcon {
      anchors.horizontalCenter: parent.horizontalCenter
      glyph: root.glyph; color: root.selected ? Color.accent : root.dim
      fontFamily: root.fontFamily; size: Style.space(18)
    }
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.title; color: root.selected ? root.foreground : root.dim
      font.family: root.fontFamily; font.pixelSize: Style.font.caption + Style.space(1)
      font.bold: root.selected
    }
  }
  Item {
    visible: !root.vertical && !root.stacked
    anchors.fill: parent
    anchors.leftMargin: Style.space(14); anchors.rightMargin: Style.space(12)
    LucideIcon {
      id: sideGlyph
      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
      glyph: root.glyph; color: root.selected ? Color.accent : root.dim
      fontFamily: root.fontFamily; size: Style.space(16)
    }
    Column {
      anchors.left: sideGlyph.right; anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.title; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall + Style.space(1)
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.subtitle; color: root.dim
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }
  }
  Item {
    visible: root.stacked
    anchors.fill: parent
    anchors.margins: Style.space(12)
    LucideIcon {
      anchors.left: parent.left; anchors.top: parent.top
      glyph: root.glyph; color: root.selected ? Color.accent : root.dim
      fontFamily: root.fontFamily; size: Style.space(15)
    }
    Column {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      spacing: Style.space(3)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.title; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall + Style.space(1)
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.subtitle; color: root.dim
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }
  }
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: root.selected ? 1 : 0
    border.color: Color.accent
  }
  MouseArea {
    id: area
    anchors.fill: parent; hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (!root.busy) root.clicked()
  }
}
