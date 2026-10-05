import QtQuick
import "LucideIcons.js" as Icons

// Lucide icon tinted with `color`. Give either a Lucide `name` or an old
// Material Design glyph in `glyph`; unknown glyphs fall back to text.
Item {
  id: root

  property string name: ""
  property string glyph: ""
  property color color: "white"
  property real size: 16
  property bool filled: false
  property real strokeWidth: 2
  property string fontFamily: ""
  readonly property var mapped: Icons.glyphs[glyph]
  readonly property string iconName: name !== "" ? name : (mapped ? mapped[0] : "")
  readonly property bool isFilled: filled || (name === "" && mapped !== undefined && mapped[1] === 1)
  readonly property string body: iconName !== "" ? (Icons.bodies[iconName] || "") : ""
  readonly property string tint: "rgb(" + Math.round(color.r * 255) + ","
    + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + ")"

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Image {
    anchors.fill: parent
    visible: root.body !== ""
    opacity: root.color.a
    smooth: true
    asynchronous: false
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.ceil(root.size * 2)
    sourceSize.height: Math.ceil(root.size * 2)
    source: root.body === "" ? "" : "data:image/svg+xml;utf8," + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="'
      + (root.isFilled ? root.tint : "none") + '" stroke="' + root.tint + '" stroke-width="'
      + root.strokeWidth + '" stroke-linecap="round" stroke-linejoin="round">' + root.body + '</svg>')
  }
  Text {
    textFormat: Text.PlainText
    visible: root.body === "" && root.glyph !== ""
    anchors.centerIn: parent
    text: root.glyph
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.size
  }
}
