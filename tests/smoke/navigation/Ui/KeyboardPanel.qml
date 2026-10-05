import QtQuick
import QtQuick.Window
import "../Reg.js" as Reg
import qs.Commons

Window {
  id: root
  visible: open
  color: "transparent"
  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property Item focusTarget: null
  onOpenChanged: if (open) Qt.callLater(function() {
    root.requestActivate()
    if (root.focusTarget) root.focusTarget.forceActiveFocus()
  })
  property alias grabItem: card
  default property alias contentItem: contentHolder.children
  readonly property real availableCardWidth: 1920
  readonly property real availableCardHeight: 1000
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)
  function fittedContentWidth(width, cap) {
    var d = Math.max(1, Number(width) || 1)
    var m = availableCardWidth
    if (cap !== undefined && Number(cap) > 0) m = Math.min(m, Number(cap))
    return Math.round(Math.min(d, m))
  }
  function fittedContentHeight(h, cap) {
    var d = Math.max(verticalContentInset, (Number(h) || 0) + verticalContentInset)
    var m = availableCardHeight
    if (cap !== undefined && Number(cap) > 0) m = Math.min(m, Number(cap))
    return Math.round(Math.min(d, m))
  }
  function cappedContentHeight(h) { return Math.round(Math.min(Math.max(padding * 2, Number(h) || 0), availableCardHeight)) }

  Component.onCompleted: Reg.panel = root
  width: contentWidth; height: contentHeight
  BorderSurface {
    id: card
    width: root.contentWidth; height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }
  }
}
