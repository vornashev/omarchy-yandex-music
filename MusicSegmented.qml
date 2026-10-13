import QtQuick
import qs.Commons
import qs.Ui

// Row of mutually exclusive options. `equalWidth` stretches cells to the full
// width (language filter); otherwise cells hug their text (popup layout).
Item {
  id: root

  property var options: []
  property string value: ""
  property bool equalWidth: false
  property bool busy: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  property int cellHeight: Style.space(30)
  property int fontSize: Style.font.bodySmall

  signal changed(string value)

  implicitWidth: row.implicitWidth
  implicitHeight: cellHeight

  Row {
    id: row
    anchors.fill: parent
    spacing: 0
    Repeater {
      model: root.options
      BorderSurface {
        id: cell
        required property var modelData
        required property int index
        readonly property bool selected: String(modelData.value) === root.value
        width: root.equalWidth ? root.width / root.options.length : label.implicitWidth + Style.space(22)
        height: root.cellHeight
        color: selected ? Style.selectedFillFor(root.foreground, Color.accent)
          : (cellMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
        borderSpec: Border.controlSpec(selected ? "selected" : "normal", root.foreground, Color.accent)
        Row {
          id: label
          anchors.centerIn: parent
          spacing: Style.space(7)
          // Optional Lucide `icon` or cover `shape` swatch before the label.
          LucideIcon {
            visible: String(cell.modelData.icon || "") !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: String(cell.modelData.icon || "")
            color: cell.selected ? Color.accent : root.dim
            size: Style.space(13)
          }
          Rectangle {
            readonly property string shape: String(cell.modelData.shape || "")
            visible: shape !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(10); height: width
            radius: shape === "circle" ? width / 2 : (shape === "rounded" ? Style.space(3) : 0)
            color: "transparent"
            border.width: Math.max(1, Style.space(1.5))
            border.color: cell.selected ? root.foreground : root.dim
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(cell.modelData.label)
            color: cell.selected ? root.foreground : root.dim
            font.family: root.fontFamily; font.pixelSize: root.fontSize
            font.bold: cell.selected
          }
        }
        MouseArea {
          id: cellMouse
          anchors.fill: parent; hoverEnabled: true
          enabled: !root.busy
          cursorShape: Qt.PointingHandCursor
          onClicked: if (!cell.selected) root.changed(String(cell.modelData.value))
        }
      }
    }
  }
}
