import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property real volume: 0
  property bool muted: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  readonly property real fillFraction: Number(volume || 0) / 100
  readonly property string displayText: muted ? "MUTE" : Math.round(Number(volume || 0)) + "%"
  readonly property real trackWidth: volumeDrag.width
  readonly property bool pressed: volumeDrag.pressed
  signal muteRequested()
  signal volumeChangeRequested(real value)

  width: parent ? parent.width : 0
  height: Style.space(28)

  function requestMute() { muteRequested() }
  function requestVolumeAt(x) {
    volumeChangeRequested(x / Math.max(1, volumeDrag.width) * 100)
  }

  Button {
    id: muteButton
    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
    width: Style.space(30); height: Style.space(28)
    horizontalPadding: 0; verticalPadding: 0
    iconText: root.muted ? "󰖁" : "󰕾"
    tooltipText: root.muted ? "Включить звук" : "Выключить звук"
    foreground: root.muted ? root.dim : root.foreground
    onClicked: root.requestMute()
  }
  Rectangle {
    id: volumeTrack
    anchors.left: muteButton.right
    anchors.right: volumePercent.left
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(6); radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
    Rectangle {
      width: parent.width * root.fillFraction
      height: parent.height; radius: parent.radius
      color: root.muted ? root.dim : root.foreground
    }
    MouseArea {
      id: volumeDrag
      anchors.fill: parent
      anchors.topMargin: -Style.space(10); anchors.bottomMargin: -Style.space(10)
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      preventStealing: true
      onPressed: function(mouse) { root.requestVolumeAt(mouse.x) }
      onPositionChanged: function(mouse) {
        if (pressed) root.requestVolumeAt(mouse.x)
      }
      onReleased: function(mouse) { root.requestVolumeAt(mouse.x) }
    }
  }
  Text {
    textFormat: Text.PlainText
    id: volumePercent
    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
    width: Style.space(34)
    horizontalAlignment: Text.AlignRight
    text: root.displayText
    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
}
