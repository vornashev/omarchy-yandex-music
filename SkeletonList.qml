import QtQuick
import qs.Commons

Column {
  id: skeletonRoot
  property color foreground: Color.foreground
  property int rowCount: 5
  spacing: 0

  Repeater {
    model: skeletonRoot.rowCount
    Item {
      id: skeletonRow
      required property int index
      width: skeletonRoot.width
      height: Style.space(50)
      clip: true

      Row {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(18); height: width; radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(skeletonRoot.foreground.r, skeletonRoot.foreground.g,
            skeletonRoot.foreground.b, .09)
        }
        Column {
          width: parent.width - Style.space(72)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Rectangle {
            width: parent.width * (.58 + (skeletonRow.index % 3) * .09)
            height: Style.space(8); radius: height / 2
            color: Qt.rgba(skeletonRoot.foreground.r, skeletonRoot.foreground.g,
              skeletonRoot.foreground.b, .11)
          }
          Rectangle {
            width: parent.width * (.32 + (skeletonRow.index % 2) * .13)
            height: Style.space(6); radius: height / 2
            color: Qt.rgba(skeletonRoot.foreground.r, skeletonRoot.foreground.g,
              skeletonRoot.foreground.b, .07)
          }
        }
        Rectangle {
          width: Style.space(34); height: Style.space(6); radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(skeletonRoot.foreground.r, skeletonRoot.foreground.g,
            skeletonRoot.foreground.b, .07)
        }
      }

      Rectangle {
        id: shimmer
        width: parent.width * .18; height: parent.height
        color: Qt.rgba(skeletonRoot.foreground.r, skeletonRoot.foreground.g,
          skeletonRoot.foreground.b, .045)
        rotation: 8
        SequentialAnimation on x {
          loops: Animation.Infinite
          PauseAnimation { duration: skeletonRow.index * 55 }
          NumberAnimation {
            from: -shimmer.width; to: skeletonRow.width + shimmer.width
            duration: 1050; easing.type: Easing.InOutQuad
          }
          PauseAnimation { duration: 300 }
        }
      }
    }
  }
}
