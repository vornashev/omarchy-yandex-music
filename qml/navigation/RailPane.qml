import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../components"

// Wide layout navigation: pages, library shortcuts, settings and layout footer.
Item {
  id: root
  objectName: "wideRail"

  required property var panel
  property string selectedShortcut: ""
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property var pins: (panel.railPinsDisplay.rows || []).filter(function(row) {
    return row.available !== false
  })
  readonly property var pinGlyphs: ({
    album: "󰀥", artist: "󰠃", playlist: "󰲸", action: "󰐷"
  })

  component SectionHeading: Item {
    property alias label: heading.text
    width: parent.width; height: visible ? Style.space(36) : 0
    Text {
      id: heading
      textFormat: Text.PlainText
      anchors.left: parent.left; anchors.leftMargin: Style.space(14)
      anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(6)
      color: root.dim
      font.family: root.ff; font.pixelSize: Style.font.caption
      font.bold: true; font.letterSpacing: 1; font.capitalization: Font.AllUppercase
    }
  }

  Rectangle {
    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
    width: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
  }

  Flickable {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: parent.top; anchors.topMargin: Style.space(20)
    anchors.bottom: railFooter.top; anchors.bottomMargin: Style.space(8)
    anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
    clip: true
    contentWidth: width
    contentHeight: shortcutsColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: shortcutsColumn
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [{ glyph: "󰪣", label: "Сейчас" }, { glyph: "󰊊", label: "Медиатека" },
          { glyph: "󰍉", label: "Поиск" }]
        RailItem {
          required property var modelData
          required property int index
          width: parent.width
          glyph: modelData.glyph; label: modelData.label; keyHint: String(index + 1)
          selected: !panel.settingsOpen && panel.page === index
          foreground: root.fg; dim: root.dim; fontFamily: root.ff
          onClicked: panel.selectPage(index)
        }
      }

      SectionHeading { label: "Ваша музыка" }

      Repeater {
        model: [{ glyph: "󰐷", label: "Моя волна", command: "wave" },
          { glyph: "󰋕", label: "Мне нравится", command: "likes" }]
        RailItem {
          required property var modelData
          width: parent.width; dense: true
          glyph: modelData.glyph; label: modelData.label
          selected: root.selectedShortcut === modelData.command
          secondary: true
          foreground: root.fg; dim: root.dim; fontFamily: root.ff
          onClicked: panel.openRailShortcut(modelData.command)
        }
      }
      SectionHeading {
        label: "Закреплённые"
        visible: root.pins.length > 0
      }
      Repeater {
        model: root.pins
        RailItem {
          required property var modelData
          readonly property var route: panel.railPinRoute(modelData)
          objectName: "railPin"
          width: parent.width; dense: true; secondary: true
          glyph: root.pinGlyphs[modelData.entityType]; label: modelData.title
          selected: !panel.settingsOpen && !modelData.action && panel.page === 1
            && panel.navigation.identity(panel.activeRoute) === panel.navigation.identity(route)
          enabled: !modelData.action || !panel.busy
          foreground: root.fg; dim: root.dim; fontFamily: root.ff
          onClicked: panel.openRailPin(modelData)
        }
      }
    }
  }

  Item {
    id: railFooter
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
    anchors.bottomMargin: Style.space(20)
    height: Style.space(37)

    RailItem {
      anchors.left: parent.left; anchors.right: layoutButton.left
      anchors.rightMargin: Style.space(4); anchors.verticalCenter: parent.verticalCenter
      glyph: "󰒓"; label: "Настройки"
      keyHint: ""
      selected: panel.settingsOpen
      foreground: root.fg; dim: root.dim; fontFamily: root.ff
      onClicked: panel.settingsOpen ? panel.closeSettings() : panel.openSettings()
    }
    AbstractButton {
      id: layoutButton
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: Style.space(37); height: Style.space(37)
      hoverEnabled: true
      focusPolicy: Qt.StrongFocus
      readonly property bool keyboardFocus: activeFocus
        && (focusReason === Qt.TabFocusReason || focusReason === Qt.BacktabFocusReason
          || focusReason === Qt.ShortcutFocusReason)
      readonly property bool showingPress: down || layoutCommit.running
      Accessible.name: "Компактный вид"
      Keys.onReturnPressed: layoutButton.clicked()
      Keys.onEnterPressed: layoutButton.clicked()
      onClicked: if (!layoutCommit.running) layoutCommit.start()

      background: Item {
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(37); height: Style.space(37); radius: 0
          color: layoutButton.showingPress ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, .18)
            : layoutButton.hovered ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"
          border.width: layoutButton.showingPress || layoutButton.keyboardFocus || layoutButton.hovered ? 1 : 0
          border.color: layoutButton.showingPress || layoutButton.keyboardFocus ? Commons.Color.accent
            : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
        }
      }
      contentItem: Item {
        LucideIcon {
          anchors.centerIn: parent
          glyph: "󰊔"; size: Style.space(14); fontFamily: root.ff
          color: layoutButton.showingPress ? Commons.Color.accent
            : layoutButton.hovered || layoutButton.keyboardFocus ? root.fg : root.dim
        }
      }
      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        onPressedChanged: if (pressed) {
          // A focused Control keeps its old focusReason until focus changes.
          layoutButton.focus = false
          layoutButton.forceActiveFocus(Qt.MouseFocusReason)
        }
      }
      ToolTip {
        visible: !layoutButton.showingPress && (layoutButton.hovered || layoutButton.keyboardFocus)
        delay: layoutButton.keyboardFocus ? 0 : 500
        padding: 0
        background: Rectangle {
          radius: Style.space(4)
          color: Qt.tint(Commons.Color.background, Style.hoverFillFor(root.fg, Commons.Color.accent))
          border.width: 1; border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
        }
        contentItem: Row {
          spacing: Style.space(8)
          leftPadding: Style.space(8); rightPadding: Style.space(8)
          topPadding: Style.space(5); bottomPadding: Style.space(5)
          Text {
            textFormat: Text.PlainText
            text: "Компактный вид"; color: root.fg
            font.family: root.ff; font.pixelSize: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
          }
          Rectangle {
            width: keyLabel.implicitWidth + Style.space(10)
            height: keyLabel.implicitHeight + Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            color: "transparent"; radius: Style.space(3)
            border.width: 1; border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
            Text {
              id: keyLabel
              anchors.centerIn: parent; textFormat: Text.PlainText
              text: "W"; color: root.dim
              font.family: root.ff; font.pixelSize: Style.space(9); font.bold: true
            }
          }
        }
      }
      Timer {
        id: layoutCommit
        interval: 120
        onTriggered: panel.setPopupLayout("compact")
      }
    }
  }
}
