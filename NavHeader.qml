import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root

  property var breadcrumbs: []
  property bool wide: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  property string contextIcon: ""
  readonly property int firstDepth: wide ? 0 : Math.max(0, breadcrumbs.length - 2)
  readonly property var shownCrumbs: breadcrumbs.slice(firstDepth)

  signal backRequested()
  signal depthRequested(int depth)
  signal contextRequested()

  implicitHeight: Style.space(wide ? 26 : 36)
  function displayTitle(route) {
    var title = String((route || {}).title || "")
    return !wide && route.kind === "search" ? title.replace(/^Поиск /, "") : title
  }
  TextMetrics {
    id: parentMetrics
    font.family: root.fontFamily; font.pixelSize: Style.space(11)
    text: root.shownCrumbs.length ? root.displayTitle(root.shownCrumbs[0]) : ""
  }

  function revealCurrent() {
    Qt.callLater(function() { crumbScroll.contentX = Math.max(0, crumbScroll.contentWidth - crumbScroll.width) })
  }
  onBreadcrumbsChanged: revealCurrent()
  onWidthChanged: revealCurrent()
  onWideChanged: revealCurrent()

  Rectangle {
    visible: !root.wide
    anchors.fill: parent
    color: Style.normalFillFor(root.foreground, Color.accent)
  }
  Rectangle {
    visible: !root.wide
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
  }

  IconButton {
    id: backButton
    objectName: "navBack"
    anchors.left: parent.left; anchors.leftMargin: root.wide ? 0 : Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26); height: width
    horizontalPadding: 0; verticalPadding: 0
    iconSize: Style.space(14); iconText: "󰁍"
    foreground: root.foreground; fontFamily: root.fontFamily
    bordered: root.wide; focusable: true
    enabled: root.breadcrumbs.length > 1
    opacity: enabled ? 1 : .35
    tooltipText: "Назад"
    onClicked: root.backRequested()
  }

  Flickable {
    id: crumbScroll
    objectName: "navCrumbs"
    anchors.left: backButton.right; anchors.leftMargin: root.wide ? Style.space(10) : 0
    anchors.right: contextButton.visible ? contextButton.left : parent.right
    anchors.rightMargin: root.wide ? 0 : Style.space(12)
    height: parent.height
    clip: true
    contentWidth: crumbRow.width; contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    onContentWidthChanged: root.revealCurrent()

    Row {
      id: crumbRow
      height: parent.height
      spacing: Style.space(8)
      Repeater {
        model: root.shownCrumbs
        Row {
          id: crumb
          required property var modelData
          required property int index
          readonly property int depth: root.firstDepth + index
          readonly property bool current: depth === root.breadcrumbs.length - 1
          height: crumbScroll.height
          spacing: Style.space(8)
          Text {
            visible: crumb.index > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "/"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(11)
          }
          Item {
            id: crumbTarget
            objectName: "navDepth" + crumb.depth
            width: Math.min(crumbText.implicitWidth, root.wide ? Style.space(220)
              : crumb.current ? Math.max(0, crumbScroll.width - (root.shownCrumbs.length > 1
                ? Math.min(parentMetrics.advanceWidth, Style.space(140)) + Style.space(23) : 0))
              : Style.space(140))
            height: parent.height
            activeFocusOnTab: !crumb.current
            onActiveFocusChanged: {
              if (!activeFocus) return
              var left = crumb.x + x
              if (left < crumbScroll.contentX) crumbScroll.contentX = left
              else if (left + width > crumbScroll.contentX + crumbScroll.width)
                crumbScroll.contentX = left + width - crumbScroll.width
            }
            Keys.onReturnPressed: if (!crumb.current) root.depthRequested(crumb.depth)
            Keys.onSpacePressed: if (!crumb.current) root.depthRequested(crumb.depth)
            Text {
              id: crumbText
              anchors.fill: parent
              textFormat: Text.PlainText
              text: root.displayTitle(crumb.modelData)
              color: crumb.current ? root.foreground : root.dim
              font.family: root.fontFamily; font.pixelSize: Style.space(11)
              font.weight: crumb.current ? Font.DemiBold : Font.Normal
              font.underline: !crumb.current && (crumbMouse.containsMouse || crumbTarget.activeFocus)
              verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
            MouseArea {
              id: crumbMouse
              anchors.fill: parent
              enabled: !crumb.current; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: root.depthRequested(crumb.depth)
            }
          }
        }
      }
    }
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(wheel) {
        var delta = wheel.pixelDelta.x || wheel.pixelDelta.y || wheel.angleDelta.x || wheel.angleDelta.y
        crumbScroll.contentX = Math.max(0, Math.min(crumbScroll.contentWidth - crumbScroll.width,
          crumbScroll.contentX - delta))
        wheel.accepted = true
      }
    }
  }

  IconButton {
    id: contextButton
    objectName: "navContext"
    visible: !root.wide && root.contextIcon !== ""
    anchors.right: parent.right; anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26); height: width
    horizontalPadding: 0; verticalPadding: 0
    iconSize: Style.space(14); iconText: root.contextIcon === "refresh-cw" ? "󰑐" : "󰇘"
    foreground: root.dim; fontFamily: root.fontFamily; focusable: true
    tooltipText: root.contextIcon === "refresh-cw" ? "Обновить" : "Действия"
    onClicked: root.contextRequested()
  }
}
