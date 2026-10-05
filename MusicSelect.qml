import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Compact single-select used across the popup. Shows the current value in the
// accent colour when it differs from `defaultValue`, locks while `busy` and
// can show a local error with a retry link.
Item {
  id: root

  property var options: []
  property string value: ""
  property string defaultValue: ""
  property bool busy: false
  property string error: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  readonly property bool popupOpen: popup.opened
  readonly property bool changedFromDefault: defaultValue !== "" && value !== defaultValue

  signal changed(string value)
  signal retryRequested()

  function optionValue(option) {
    return (option && typeof option === "object") ? String(option.value) : String(option)
  }
  function optionLabel(option) {
    return (option && typeof option === "object") ? String(option.label) : String(option)
  }
  function indexOfValue(wanted) {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === wanted) return i
    return -1
  }
  function currentLabel() {
    var index = indexOfValue(value)
    return index >= 0 ? optionLabel(options[index]) : value
  }

  implicitWidth: Style.space(260)
  implicitHeight: trigger.height + (error !== "" ? Style.space(18) : 0)

  BorderSurface {
    id: trigger
    width: parent.width
    height: Style.space(32)
    radius: Style.cornerRadius
    opacity: root.enabled ? 1 : .45
    activeFocusOnTab: root.enabled
    color: triggerHover.hovered || trigger.activeFocus || popup.opened
      ? Style.hoverFillFor(root.foreground, Color.accent)
      : Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: root.error !== "" ? Border.controlSpec("normal", Color.urgent, Color.urgent)
      : Border.controlSpec(popup.opened || trigger.activeFocus ? "focus"
        : (triggerHover.hovered ? "hover-cursor" : "normal"), root.foreground, Color.accent)

    HoverHandler { id: triggerHover; enabled: root.enabled }

    Keys.onPressed: function(event) {
      if (!root.enabled || root.busy) return
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        popup.opened ? popup.close() : popup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && popup.opened) {
        popup.close()
        event.accepted = true
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left; anchors.right: stateGlyph.left
      anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: root.currentLabel()
      color: root.changedFromDefault ? Color.accent : root.foreground
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    LucideIcon {
      id: stateGlyph
      anchors.right: parent.right; anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      glyph: root.error !== "" ? "󰀦" : (root.busy ? "󰦖" : (popup.opened ? "󰅃" : "󰅀"))
      color: root.error !== "" ? Color.urgent : root.dim
      fontFamily: root.fontFamily; size: Style.space(15)
      RotationAnimator on rotation {
        running: root.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite
      }
    }
    MouseArea {
      anchors.fill: parent
      enabled: root.enabled && !root.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        popup.opened ? popup.close() : popup.open()
      }
    }

    Popup {
      id: popup
      x: 0
      y: trigger.height + Style.space(2)
      width: trigger.width
      padding: Style.space(1)
      focus: true
      implicitHeight: Math.min(root.options.length, 8) * Style.space(30) + Style.space(2)
      background: BorderSurface {
        color: Color.popups.background
        radius: Style.cornerRadius
        borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)
      }
      onOpened: {
        optionList.currentIndex = Math.max(0, root.indexOfValue(root.value))
        optionList.forceActiveFocus()
      }
      contentItem: ListView {
        id: optionList
        clip: true
        model: root.options
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down) {
            currentIndex = Math.min(root.options.length - 1, currentIndex + 1); event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            currentIndex = Math.max(0, currentIndex - 1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            optionList.choose(currentIndex); event.accepted = true
          }
        }
        function choose(index) {
          if (index < 0 || index >= root.options.length) return
          var next = root.optionValue(root.options[index])
          popup.close()
          if (next !== root.value) root.changed(next)
        }
        delegate: Rectangle {
          id: optionRow
          required property var modelData
          required property int index
          readonly property bool selected: root.optionValue(modelData) === root.value
          width: optionList.width
          height: Style.space(30)
          color: index === optionList.currentIndex
            ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
          Rectangle {
            visible: optionRow.index === optionList.currentIndex
            width: Style.space(2); height: parent.height; color: Color.accent
          }
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left; anchors.right: checkGlyph.left
            anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
            text: root.optionLabel(optionRow.modelData)
            color: optionRow.selected ? Color.accent : root.foreground
            font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            font.bold: optionRow.selected
            elide: Text.ElideRight
          }
          LucideIcon {
            id: checkGlyph
            visible: optionRow.selected
            anchors.right: parent.right; anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰄬"; color: Color.accent
            fontFamily: root.fontFamily; size: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: optionList.currentIndex = optionRow.index
            onClicked: optionList.choose(optionRow.index)
          }
        }
      }
    }
  }

  Row {
    visible: root.error !== ""
    anchors.top: trigger.bottom; anchors.topMargin: Style.space(4)
    spacing: Style.space(6)
    Text {
      textFormat: Text.PlainText
      text: root.error; color: Color.urgent
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
    Text {
      textFormat: Text.PlainText
      text: "Повторить"; color: Color.accent
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: root.retryRequested()
      }
    }
  }
}
