import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var logic: null
  property var hostWidget: null
  readonly property bool hasTrack: logic ? logic.hasTrack : false
  readonly property bool playing: logic ? logic.playing : false
  readonly property bool loading: logic ? logic.loading : false
  readonly property bool hasError: logic ? logic.error !== "" : false
  property real loaderAngle: 0
  readonly property var preferences: logic && logic.data.preferences ? logic.data.preferences : ({})
  readonly property bool showControls: preferences.showControls === undefined ? true : Boolean(preferences.showControls)
  readonly property bool showArtist: preferences.showArtist === undefined ? true : Boolean(preferences.showArtist)
  readonly property bool showTitle: preferences.showTitle === undefined ? true : Boolean(preferences.showTitle)
  readonly property bool showCover: preferences.showCover === undefined ? true : Boolean(preferences.showCover)
  readonly property string coverShape: String(preferences.coverShape || "rounded")
  readonly property bool showProgress: preferences.showProgress === undefined ? true : Boolean(preferences.showProgress)
  readonly property string longTitleMode: String(preferences.longTitleMode || "truncate")
  readonly property real informationWidth: {
    var mode = String(preferences.barWidth || "normal")
    if (mode === "compact") return Style.space(170)
    if (mode === "wide") return Style.space(310)
    return Style.space(230)
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string label: {
    if (hasError) return "Ошибка Яндекс Музыки — нажмите, чтобы открыть"
    if (loading && !hasTrack) return "Яндекс Музыка загружается…"
    if (!hasTrack) return "Я.Музыка"
    var artist = String(logic.data.artist || "")
    var title = String(logic.data.title || "")
    return artist ? artist + " — " + title : title
  }

  implicitWidth: controls.width + Style.space(12)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: controls
    anchors.centerIn: parent
    spacing: Style.space(5)

    Item {
      visible: root.showControls
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: "󰒮"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("previous")
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Предыдущий трек")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      visible: root.showControls
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: root.playing ? "󰏤" : "󰐊"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("pause")
        onEntered: if (root.bar) root.bar.showTooltip(parent, root.playing ? "Пауза" : "Продолжить")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      visible: root.showControls
      width: Style.space(34); height: root.implicitHeight
      opacity: root.hasTrack ? 1 : .35
      Text {
        anchors.centerIn: parent; text: "󰒭"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 20
      }
      MouseArea {
        anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.action("next")
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Следующий трек")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      visible: !root.showCover && !labelSlot.visible
      width: Style.space(24); height: root.implicitHeight
      Text {
        anchors.centerIn: parent
        text: "󰝚"; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Style.font.icon
      }
      MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: if (root.logic) root.logic.toggle()
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Открыть Яндекс Музыку")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    BorderSurface {
      id: cover
      visible: root.showCover
      width: Style.space(20); height: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      radius: root.coverShape === "circle" ? width / 2
        : (root.coverShape === "square" ? 0 : Style.space(2))
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.none()
      Rectangle {
        id: coverMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: cover.radius
        color: "white"
      }
      Image {
        anchors.fill: parent; source: root.logic && root.logic.data.artUrl ? root.logic.data.artUrl : ""
        fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: source !== ""
        layer.enabled: true; layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true; maskSource: coverMask
          maskThresholdMin: .3; maskSpreadAtMin: .3
        }
      }
      Text {
        anchors.centerIn: parent; visible: !root.logic || !root.logic.data.artUrl
        text: "󰝚"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
      Rectangle {
        anchors.fill: parent
        visible: root.hasError && !root.loading
        radius: cover.radius
        color: Qt.rgba(0, 0, 0, .55)
      }
      Rectangle {
        anchors.fill: parent
        visible: root.loading
        radius: cover.radius
        color: Qt.rgba(0, 0, 0, .58)
      }
      Rectangle {
        anchors.centerIn: parent
        visible: root.loading
        width: Style.space(14); height: width; radius: width / 2
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .25)
      }
      Canvas {
        anchors.centerIn: parent
        visible: root.loading
        width: Style.space(14); height: width
        antialiasing: true
        rotation: root.loaderAngle
        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          context.beginPath()
          context.arc(width / 2, height / 2, width / 2 - Style.space(1.3),
            -Math.PI / 2, Math.PI * .85, false)
          context.lineWidth = Style.space(1.7)
          context.lineCap = "round"
          context.strokeStyle = Color.accent
          context.stroke()
        }
      }
      Text {
        anchors.centerIn: parent
        visible: root.hasError && !root.loading
        text: "󰀪"; color: Color.urgent
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: labelSlot
      visible: root.showArtist || root.showTitle
      width: root.showTitle ? root.informationWidth : Math.min(root.informationWidth, Style.space(105))
      height: root.implicitHeight
      clip: true

      Text {
        id: trackInfoLabel
        anchors.verticalCenter: parent.verticalCenter
        width: root.longTitleMode === "scroll" ? implicitWidth : parent.width
        text: {
          if (!root.hasTrack) return "Я.Музыка"
          var parts = []
          var artist = root.logic ? String(root.logic.data.artist || "") : ""
          var title = root.logic ? String(root.logic.data.title || "") : ""
          if (root.showArtist && artist) parts.push(artist)
          if (root.showTitle && title) parts.push(title)
          return parts.join(" — ")
        }
        color: root.foreground; font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: root.longTitleMode === "scroll" ? Text.ElideNone : Text.ElideRight
      }

      SequentialAnimation {
        id: trackInfoMarquee
        running: root.longTitleMode === "scroll" && root.hasTrack
          && trackInfoLabel.implicitWidth > labelSlot.width
        loops: Animation.Infinite
        PauseAnimation { duration: 1000 }
        NumberAnimation {
          target: trackInfoLabel; property: "x"
          from: 0; to: Math.min(0, labelSlot.width - trackInfoLabel.implicitWidth)
          duration: Math.max(1200, (trackInfoLabel.implicitWidth - labelSlot.width) * 22)
          easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 700 }
        NumberAnimation {
          target: trackInfoLabel; property: "x"; to: 0
          duration: 350; easing.type: Easing.OutCubic
        }
      }
      Connections {
        target: trackInfoMarquee
        function onRunningChanged() { if (!trackInfoMarquee.running) trackInfoLabel.x = 0 }
      }
    }
  }

  MouseArea {
    visible: cover.visible || labelSlot.visible
    x: controls.x + (cover.visible ? cover.x : labelSlot.x)
    y: 0
    width: cover.visible && labelSlot.visible
      ? labelSlot.x + labelSlot.width - cover.x
      : (cover.visible ? cover.width : labelSlot.width)
    height: root.height
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.logic) root.logic.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.label)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Timer {
    interval: 16
    repeat: true
    running: root.loading
    onTriggered: root.loaderAngle = (root.loaderAngle + 7.2) % 360
  }

  Rectangle {
    visible: root.hasTrack && root.showProgress
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: Style.space(2); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
    Rectangle {
      width: parent.width * (root.logic
        ? Math.min(1, Number(root.logic.data.position || 0) / Math.max(1, Number(root.logic.data.duration || 1)))
        : 0)
      height: parent.height; color: Color.accent
    }
  }
}
