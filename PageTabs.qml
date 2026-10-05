import QtQuick
import qs.Commons
import qs.Ui

// Compact layout page strip: three pages plus the layout toggle cell.
Item {
  id: root

  required property var panel
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily

  implicitHeight: Style.space(40)

  Rectangle {
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
  }

  Row {
    anchors.fill: parent
    Repeater {
      model: [{ glyph: "󰪣", label: "Сейчас" }, { glyph: "󰊊", label: "Медиатека" },
        { glyph: "󰍉", label: "Поиск" }]
      Item {
        id: tab
        required property var modelData
        required property int index
        readonly property bool selected: !panel.settingsOpen && panel.page === index
        width: (root.width - toggle.width) / 3
        height: root.height
        Rectangle {
          anchors.fill: parent
          color: tab.selected ? Style.selectedFillFor(root.fg, Color.accent)
            : (tabMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
          opacity: tab.selected ? .5 : 1
        }
        Row {
          anchors.centerIn: parent
          spacing: Style.space(8)
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: tab.modelData.glyph
            color: tab.selected ? Color.accent : root.dim
            fontFamily: root.ff; size: Style.space(14)
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: tab.modelData.label
            color: tab.selected ? root.fg : root.dim
            font.family: root.ff; font.pixelSize: Style.font.bodySmall
            font.bold: tab.selected
          }
        }
        Rectangle {
          visible: tab.selected
          anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          height: Style.space(2); color: Color.accent
        }
        MouseArea {
          id: tabMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: panel.selectPage(tab.index)
        }
      }
    }
    Item {
      id: toggle
      width: Style.space(44); height: root.height
      Rectangle {
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
      }
      IconButton {
        anchors.centerIn: parent
        width: Style.space(40); height: Style.space(36)
        horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(14)
        iconText: "󰊓"; foreground: root.dim
        tooltipText: "Широкий вид (W)"
        onClicked: panel.setPopupLayout("wide")
      }
    }
  }
}
