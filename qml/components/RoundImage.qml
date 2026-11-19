import QtQuick

// CatalogImage clipped to a circle (artist avatars). Painted with Canvas so it
// works with every scene-graph backend.
Item {
  id: root

  property string requestedSource: ""
  property color foreground: "white"
  property string fontFamily: ""

  CatalogImage {
    id: probe
    visible: false
    width: 1; height: 1
    requestedSource: root.requestedSource
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    readonly property url loadedSource: probe.status === Image.Ready ? probe.source : ""
    onLoadedSourceChanged: {
      if (String(loadedSource) !== "") loadImage(loadedSource)
      else requestPaint()
    }
    onImageLoaded: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.save()
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, Math.PI * 2)
      ctx.clip()
      ctx.fillStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
      ctx.fillRect(0, 0, width, height)
      if (String(loadedSource) !== "" && isImageLoaded(loadedSource)) {
        var w = probe.implicitWidth, h = probe.implicitHeight
        var side = Math.min(w, h)
        if (side > 0)
          ctx.drawImage(loadedSource, (w - side) / 2, (h - side) / 2, side, side,
            0, 0, width, height)
      }
      ctx.restore()
    }
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .12)
  }
}
