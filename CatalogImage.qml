import QtQuick

Image {
  id: root

  property string requestedSource: ""
  property color foreground: "white"
  property string fontFamily: ""
  property int maxRetryAttempts: 3
  property int retryAttempt: 0
  property int retryNonce: 0
  readonly property bool retrying: retryTimer.running

  source: requestedSource === "" ? "" : requestedSource
    + (requestedSource.indexOf("?") >= 0 ? "&" : "?")
    + "omarchyRetry=" + retryNonce
  asynchronous: true

  onRequestedSourceChanged: {
    retryTimer.stop()
    retryAttempt = 0
    retryNonce = 0
  }

  onStatusChanged: {
    if (status === Image.Ready) {
      retryTimer.stop()
      retryAttempt = 0
    } else if (status === Image.Error && requestedSource !== ""
               && retryAttempt < maxRetryAttempts) {
      retryAttempt += 1
      retryTimer.restart()
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.requestedSource !== "" && root.status === Image.Error
      && !root.retrying && root.retryAttempt >= root.maxRetryAttempts
    text: "󰋦"
    textFormat: Text.PlainText
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .45)
    font.family: root.fontFamily
    font.pixelSize: Math.min(root.width, root.height) * .38
  }

  Timer {
    id: retryTimer
    interval: Math.min(2400, 600 * Math.pow(2, Math.max(0, root.retryAttempt - 1)))
    repeat: false
    onTriggered: root.retryNonce += 1
  }
}
