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
  property bool likePending: false
  property bool likeFlash: false
  property bool likeError: false
  property bool navSpinner: false
  property real wheelAccumulator: 0
  readonly property var preferences: logic && logic.snapshot.preferences ? logic.snapshot.preferences : ({})
  readonly property bool showControls: preferences.showControls === undefined ? true : Boolean(preferences.showControls)
  readonly property bool signedOut: logic ? logic.snapshot.authenticated === false : false
  readonly property bool errorState: hasError && !loading && !signedOut && !hasTrack
  readonly property bool showTime: preferences.showTime === undefined ? false : Boolean(preferences.showTime)
  readonly property bool showLike: preferences.showLike === undefined ? false : Boolean(preferences.showLike)
  readonly property bool dimmed: hasTrack && !playing && !loading
  readonly property bool showVolume: preferences.showVolume === undefined ? true : Boolean(preferences.showVolume)
  readonly property bool showArtist: preferences.showArtist === undefined ? true : Boolean(preferences.showArtist)
  readonly property bool showTitle: preferences.showTitle === undefined ? true : Boolean(preferences.showTitle)
  readonly property bool showCover: preferences.showCover === undefined ? true : Boolean(preferences.showCover)
  readonly property string coverShape: String(preferences.coverShape || "rounded")
  readonly property bool showProgress: preferences.showProgress === undefined ? true : Boolean(preferences.showProgress)
  readonly property string longTitleMode: String(preferences.longTitleMode || "truncate")
  readonly property bool showBarLyrics: Boolean(preferences.showBarLyrics)
  readonly property bool barMouseControls: Boolean(preferences.barMouseControls)
  // Pixel widths (10 px steps); legacy width modes cover older snapshots.
  function widthPreference(key, legacyKey, legacy, fallback) {
    var value = Number(preferences[key])
    if (!isFinite(value) || value <= 0) value = legacy[String(preferences[legacyKey] || "")] || fallback
    return Style.space(value)
  }
  readonly property real informationWidth: widthPreference("barInfoWidth", "barWidth",
    { compact: 170, normal: 230, wide: 310 }, 230)
  // The public bar facade has no free-space geometry, so the lyric slot always
  // takes its configured width instead of guessing a monitor center.
  readonly property real lyricsMaxWidth: widthPreference("barLyricsWidth", "lyricsWidthMode",
    { auto: 400, compact: 240, normal: 400, wide: 600, full: 1200 }, 400)
  readonly property real lyricsWidth: root.showBarLyrics ? root.lyricsMaxWidth : 0
  readonly property Item coverItem: cover.visible ? cover : (labelSlot.visible ? labelSlot : root)

  property double positionClockMs: Date.now()
  readonly property real displayPosition: {
    var pos = Number(logic && logic.snapshot ? logic.snapshot.position || 0 : 0)
    var observedAt = Number(logic && logic.snapshot ? logic.snapshot.positionObservedAt || 0 : 0)
    if (root.playing && observedAt > 0) {
      var elapsed = Math.max(0, positionClockMs / 1000 - observedAt)
      pos += Math.min(3, elapsed)
    }
    var dur = Number(logic && logic.snapshot ? logic.snapshot.duration || 0 : 0)
    return Math.max(0, dur > 0 ? Math.min(dur, pos) : pos)
  }

  Timer {
    id: positionTimer
    interval: lyricLabel.visible && lyricLabel.implicitWidth > lyricsSlot.width ? 16 : 80
    running: root.playing && root.hasTrack && lyricsSlot.visible
    repeat: true
    onTriggered: root.positionClockMs = Date.now()
  }

  readonly property var lyricsData: (logic && logic.snapshot && logic.snapshot.lyrics) ? logic.snapshot.lyrics : null
  readonly property var lyricsLines: (lyricsData && lyricsData.lines) ? lyricsData.lines : []
  readonly property bool lyricsAvailable: lyricsData && lyricsData.available === true && lyricsLines.length > 0 && String(lyricsData.trackId || "") === String(logic.snapshot.trackId || "")
  readonly property bool syncedLyricsAvailable: lyricsAvailable && lyricsData.synced === true

  function currentLyricsIndex() {
    if (!syncedLyricsAvailable) return -1
    var pos = root.displayPosition
    var current = -1
    for (var i = 0; i < lyricsLines.length; i++) {
      var t = Number(lyricsLines[i].time || 0)
      if (t <= pos) current = i
      else break
    }
    return current
  }

  readonly property int activeLyricIndex: currentLyricsIndex()
  readonly property real lyricScrollProgress: {
    if (!syncedLyricsAvailable || activeLyricIndex < 0) return 0
    var start = Number(lyricsLines[activeLyricIndex].time)
    var end = activeLyricIndex + 1 < lyricsLines.length
      ? Number(lyricsLines[activeLyricIndex + 1].time)
      : Number(logic && logic.snapshot ? logic.snapshot.duration || 0 : 0)
    var span = end - start
    if (!isFinite(span) || span <= 0) return 0
    // Reserve reading time at both ends, proportionally shorter for quick lines.
    var hold = Math.min(0.3, span * 0.1)
    return Math.max(0, Math.min(1, (displayPosition - start - hold) / (span - 2 * hold)))
  }
  readonly property string targetLyricText: {
    if (!syncedLyricsAvailable) return ""
    var idx = activeLyricIndex
    if (idx >= 0 && idx < lyricsLines.length) {
      return String(lyricsLines[idx].text || "").trim()
    }
    return ""
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string errorText: logic && logic.snapshot.version === undefined
    ? "Нет связи с сервисом" : "Ошибка Яндекс Музыки"
  readonly property string label: {
    if (signedOut) return "Войти в Яндекс Музыку"
    if (hasError) return "Ошибка Яндекс Музыки — нажмите, чтобы открыть"
    if (loading && !hasTrack) return "Яндекс Музыка загружается…"
    if (!hasTrack) return "Я.Музыка"
    var artist = String(logic.snapshot.artist || "")
    var title = String(logic.snapshot.title || "")
    return artist ? artist + " — " + title : title
  }

  function navigating() {
    navSpinner = true
    navSpinnerTimer.restart()
  }
  function toggleLike() {
    if (!logic || likePending) return
    likeError = false
    likePending = true
    likeTimeout.restart()
    logic.transport("toggleLike")
  }
  function formatTime(value) {
    var seconds = Math.max(0, Math.round(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
  }
  function queueVolume(value) { if (logic) logic.queueVolume(value) }
  function changeVolumeFromWheel(delta) {
    if (!logic || delta === 0) return false
    var wheel = Util.wheelSteps(wheelAccumulator, delta)
    wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return false
    queueVolume(Number(logic.snapshot.volume || 0) + wheel.steps * 5)
    return true
  }

  implicitWidth: controls.width + Style.space(12)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: controls
    // Keep real buttons above the shared information hit area.
    z: 1
    anchors.centerIn: parent
    height: root.height
    spacing: Style.space(5)

    Item {
      id: signedOutSlot
      visible: root.signedOut
      width: signedOutRow.width + Style.space(12); height: root.implicitHeight
      Row {
        id: signedOutRow
        anchors.centerIn: parent
        spacing: Style.space(8)
        LucideIcon {
          anchors.verticalCenter: parent.verticalCenter
          name: "log-in"; color: Color.accent; size: Style.space(14)
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Войти в Яндекс Музыку"; color: Color.accent
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: if (root.logic) root.logic.toggle()
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Открыть вход в Яндекс Музыку")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Item {
      id: errorSlot
      visible: root.errorState && !root.signedOut
      width: errorRow.width + Style.space(12); height: root.implicitHeight
      Row {
        id: errorRow
        anchors.centerIn: parent
        spacing: Style.space(8)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7); height: width; radius: width / 2; color: Color.urgent
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.errorText; color: Color.urgent
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: if (root.logic) root.logic.toggle()
        onEntered: if (root.bar) root.bar.showTooltip(parent, "Ошибка Яндекс Музыки — нажмите, чтобы открыть")
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }

    Row {
      id: transportRow
      visible: root.showControls && !root.signedOut && !root.errorState
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      spacing: Style.space(2)
      BarButton {
        bar: root.bar; foreground: root.foreground; filled: true
        name: "skip-back"; tooltip: "Предыдущий (P)"; enabled: root.hasTrack
        onClicked: { root.navigating(); root.logic.transport("previousTrack") }
      }
      BarButton {
        bar: root.bar; foreground: root.foreground; filled: true
        name: root.playing ? "pause" : "play"
        tooltip: root.playing ? "Пауза (Space)" : "Продолжить (Space)"; enabled: root.hasTrack
        onClicked: root.logic.transport("togglePlayback")
      }
      BarButton {
        bar: root.bar; foreground: root.foreground; filled: true
        name: "skip-forward"; tooltip: "Следующий (N)"; enabled: root.hasTrack
        onClicked: { root.navigating(); root.logic.transport("nextTrack") }
      }
      Item { width: Style.space(6); height: 1 }
    }

    BarButton {
      id: popupButton
      objectName: "barPopupButton"
      visible: !root.showCover && (root.barMouseControls || !labelSlot.visible)
        && !root.signedOut && !root.errorState
      bar: root.bar
      foreground: root.foreground
      name: "audio-lines"
      iconColor: Color.accent
      tooltip: "Открыть Яндекс Музыку"
      onClicked: if (root.logic) root.logic.toggle()
      onWheel: function(wheel) { infoArea.handleWheel(wheel, false) }
    }

    BorderSurface {
      id: cover
      objectName: "barCover"
      visible: root.showCover && !root.signedOut && !root.errorState
      width: Style.space(20); height: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      radius: root.coverShape === "circle" ? width / 2
        : (root.coverShape === "square" ? 0 : Style.space(2))
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.none()
      opacity: root.dimmed ? .5 : 1
      Rectangle {
        id: coverMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: cover.radius
        color: "white"
      }
      Image {
        anchors.fill: parent; source: root.logic && root.logic.snapshot.artUrl ? root.logic.snapshot.artUrl : ""
        fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: source !== ""
        layer.enabled: true; layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true; maskSource: coverMask
          maskThresholdMin: .3; maskSpreadAtMin: .3
        }
      }
      LucideIcon {
        anchors.centerIn: parent; visible: !root.logic || !root.logic.snapshot.artUrl
        glyph: "󰝚"; color: root.foreground; fontFamily: root.fontFamily; size: Style.font.caption
      }
      Rectangle {
        anchors.fill: parent
        visible: root.hasError && !root.loading
        radius: cover.radius
        color: Qt.rgba(0, 0, 0, .55)
      }
      Rectangle {
        anchors.fill: parent
        visible: root.loading || root.navSpinner
        radius: cover.radius
        color: Qt.rgba(0, 0, 0, .58)
      }
      Rectangle {
        anchors.centerIn: parent
        visible: root.loading || root.navSpinner
        width: Style.space(14); height: width; radius: width / 2
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .25)
      }
      Canvas {
        anchors.centerIn: parent
        visible: root.loading || root.navSpinner
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
      LucideIcon {
        anchors.centerIn: parent
        visible: root.hasError && !root.loading
        glyph: "󰀪"; color: Color.urgent
        fontFamily: root.fontFamily; size: Style.font.caption
      }
      MouseArea {
        id: coverMouse
        x: -Style.space(4)
        y: (cover.height - root.height) / 2
        width: cover.width + Style.space(8)
        height: root.height
        enabled: root.barMouseControls
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.logic) root.logic.toggle()
        onWheel: function(wheel) { infoArea.handleWheel(wheel, false) }
        onEntered: if (root.bar) root.bar.showTooltip(cover, "Открыть Яндекс Музыку")
        onExited: if (root.bar) root.bar.hideTooltip(cover)
      }
    }

    Item {
      id: labelSlot
      objectName: "barTrackInfo"
      visible: (root.showArtist || root.showTitle) && !root.signedOut && !root.errorState
      width: {
        return root.showTitle ? root.informationWidth : Math.min(root.informationWidth, Style.space(105))
      }
      height: root.implicitHeight
      clip: true
      opacity: root.dimmed ? .5 : 1

      Text {
        textFormat: Text.PlainText
        id: trackInfoLabel
        anchors.verticalCenter: parent.verticalCenter
        width: root.longTitleMode === "scroll" ? implicitWidth : parent.width
        text: {
          if (!root.hasTrack) return "Я.Музыка"
          if (root.loading) return "Подключение потока…"
          var parts = []
          var artist = root.logic ? String(root.logic.snapshot.artist || "") : ""
          var title = root.logic ? String(root.logic.snapshot.title || "") : ""
          if (root.showArtist && artist) parts.push(artist)
          if (root.showTitle && title) parts.push(title)
          return parts.join(" — ")
        }
        color: root.loading ? root.foreground : root.foreground; font.family: root.fontFamily
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

    BarButton {
      id: likeButton
      objectName: "barLike"
      visible: root.showLike && root.hasTrack && !root.signedOut && !root.errorState
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar; foreground: root.foreground
      readonly property bool liked: root.logic ? root.logic.snapshot.liked === true : false
      readonly property bool shownLiked: root.likePending ? !liked : liked
      name: "heart"
      filled: shownLiked
      iconColor: shownLiked ? Color.accent : root.foreground
      iconOpacity: root.likePending ? .5 : 1
      flash: root.likeFlash
      errorDot: root.likeError
      tooltip: shownLiked ? "Убрать из любимого (L)" : "Нравится (L)"
      onClicked: root.toggleLike()
    }

    Text {
      id: showTimeText
      textFormat: Text.PlainText
      visible: root.showTime && root.hasTrack && !root.signedOut && !root.errorState
      anchors.verticalCenter: parent.verticalCenter
      text: formatTime(Number(root.logic ? root.logic.snapshot.position || 0 : 0)) + " / "
        + formatTime(Number(root.logic ? root.logic.snapshot.duration || 0 : 0))
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .55)
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }

    Item {
      id: separatorItem
      visible: root.showBarLyrics && !root.signedOut && !root.errorState
      width: Style.space(8)
      height: root.implicitHeight

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "│"
        color: root.foreground
        opacity: 0.25
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      id: lyricsSlot
      objectName: "barLyrics"
      visible: root.showBarLyrics && !root.signedOut && !root.errorState
      width: root.lyricsWidth
      height: root.implicitHeight
      clip: true

      property string currentDisplayedText: ""
      property string pendingText: {
        var snapshot = root.logic ? root.logic.snapshot : null
        var lyrics = snapshot ? snapshot.lyrics : null
        if (!lyrics || lyrics.available !== true || lyrics.synced !== true
            || String(lyrics.trackId || "") !== String(snapshot.trackId || "")) return ""
        return root.targetLyricText
      }
      readonly property string displayTrackId: String(root.logic && root.logic.snapshot
        ? root.logic.snapshot.trackId || "" : "")
      onDisplayTrackIdChanged: {
        lyricTransition.stop()
        currentDisplayedText = ""
        // Snapshot-derived bindings settle after the track identity notification.
        Qt.callLater(function() {
          lyricTransition.stop()
          lyricsSlot.currentDisplayedText = lyricsSlot.pendingText
        })
        lyricLabel.opacity = 1
        lyricLabel.verticalOffset = 0
      }

      onPendingTextChanged: {
        if (pendingText === currentDisplayedText) return
        if (lyricTransition.running) lyricTransition.stop()
        if (currentDisplayedText === "") {
          currentDisplayedText = pendingText
          lyricLabel.opacity = 1
          lyricLabel.verticalOffset = 0
        } else {
          lyricTransition.restart()
        }
      }

      Item {
        id: waveHolder
        objectName: "barLyricWave"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: lyricsSlot.width
        height: Style.space(20)
        visible: !root.syncedLyricsAvailable || lyricsSlot.currentDisplayedText === ""
          || lyricsSlot.currentDisplayedText === "♪"

        Canvas {
          id: waveCanvas
          anchors.fill: parent
          antialiasing: true

          property real phase: 0
          readonly property real waveAmp: root.playing ? 1.0 : 0.15

          Timer {
            interval: 25
            running: root.playing && lyricsSlot.visible && waveHolder.visible
            repeat: true
            onTriggered: {
              waveCanvas.phase += 0.07
              waveCanvas.requestPaint()
            }
          }

          function topY(x, w, h) {
            var baseLine = h - Style.space(2)
            var taperRight = x > (w - Style.space(16)) ? Math.max(0, (w - x) / Style.space(16)) : 1.0
            var waveH = (
              Math.sin(x * 0.038 + waveCanvas.phase) * Style.space(4.5) +
              Math.sin(x * 0.082 + waveCanvas.phase * 1.5) * Style.space(2.8) +
              Math.sin(x * 0.016 - waveCanvas.phase * 0.7) * Style.space(2.0)
            ) * waveAmp * taperRight
            return Math.max(Style.space(2), baseLine - Style.space(3) - Math.max(-Style.space(1), waveH))
          }

          function waveFill(ctx, targetX, h, fillStyle) {
            var base = h - Style.space(2)
            var step = 4
            ctx.beginPath()
            ctx.moveTo(0, base)
            ctx.lineTo(0, topY(0, targetX, h))
            for (var x = step; x <= targetX; x += step) {
              ctx.lineTo(x, topY(x, targetX, h))
            }
            ctx.lineTo(targetX, base)
            ctx.closePath()
            ctx.fillStyle = fillStyle
            ctx.fill()
          }

          onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w <= 0 || h <= 0) return
            ctx.clearRect(0, 0, w, h)

            var col = Color.accent
            var r = Math.round(col.r * 255)
            var g = Math.round(col.g * 255)
            var b = Math.round(col.b * 255)
            var targetX = w - Style.space(2)

            // Solid filled wave silhouette exactly matching screenshot
            var waveStyle = "rgba(" + r + "," + g + "," + b + ", 0.70)"
            waveFill(ctx, targetX, h, waveStyle)

            // Crisp top crest line for sharpness
            ctx.beginPath()
            ctx.lineWidth = Style.space(1.5)
            ctx.strokeStyle = "rgba(" + r + "," + g + "," + b + ", 0.95)"
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            var step = 4
            for (var x2 = 0; x2 <= targetX; x2 += step) {
              var y2 = topY(x2, targetX, h)
              if (x2 === 0) ctx.moveTo(x2, y2)
              else ctx.lineTo(x2, y2)
            }
            ctx.stroke()
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        id: lyricLabel
        objectName: "barLyricText"
        property real verticalOffset: 0
        visible: root.syncedLyricsAvailable && lyricsSlot.currentDisplayedText !== ""
          && lyricsSlot.currentDisplayedText !== "♪"
        y: (parent.height - implicitHeight) / 2 + verticalOffset
        width: implicitWidth
        x: text === root.targetLyricText
          ? -Math.max(0, width - lyricsSlot.width) * root.lyricScrollProgress : 0
        text: lyricsSlot.currentDisplayedText
        color: Color.accent
        opacity: 1.0
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.Medium
        elide: Text.ElideNone
      }


      SequentialAnimation {
        id: lyricTransition
        ParallelAnimation {
          NumberAnimation {
            target: lyricLabel; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad
          }
          NumberAnimation {
            target: lyricLabel; property: "verticalOffset"
            to: -Style.space(6)
            duration: 120; easing.type: Easing.InQuad
          }
        }
        ScriptAction {
          script: {
            lyricsSlot.currentDisplayedText = lyricsSlot.pendingText
            lyricLabel.verticalOffset = Style.space(6)
          }
        }
        ParallelAnimation {
          NumberAnimation {
            target: lyricLabel; property: "opacity"
            to: lyricsSlot.currentDisplayedText !== "" ? 1.0 : 0.4
            duration: 220; easing.type: Easing.OutCubic
          }
          NumberAnimation {
            target: lyricLabel; property: "verticalOffset"
            to: 0
            duration: 220; easing.type: Easing.OutCubic
          }
        }
      }
    }

    Item {
      id: volumeSlot
      visible: root.showVolume && !root.signedOut && !root.errorState
      width: Style.space(24) + Style.space(6) + Style.space(64) + Style.space(8) + Style.space(30)
      height: root.height
      enabled: !root.hasError
      opacity: root.hasError ? .35 : 1

      readonly property real volumeValue: Math.max(0, Math.min(100,
        Number(root.logic ? root.logic.snapshot.volume || 0 : 0)))
      readonly property bool muted: root.logic ? root.logic.snapshot.muted === true : false
      readonly property bool zoneHot: zoneHover.hovered || volumeMouse.containsMouse || volumeButton.containsMouse
      property bool dragging: false
      property real dragValue: 0
      property bool flashing: false
      readonly property real shownValue: dragging ? dragValue : volumeValue

      HoverHandler { id: zoneHover }

      BarButton {
        id: volumeButton
        objectName: "barMute"
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        bar: root.bar; foreground: root.foreground
        iconColor: volumeSlot.muted ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .7)
        name: volumeSlot.muted ? "volume-x" : (volumeSlot.volumeValue < 34 ? "volume-1" : "volume-2")
        filled: false
        tooltip: volumeSlot.muted ? "Включить звук · ЛКМ" : "Выкл. звук · ЛКМ"
        onClicked: root.logic.transport("toggleMute")
        onWheel: function(wheel) { volumeSlot.handleWheel(wheel) }
      }

      function handleWheel(wheel) {
        if (!root.logic || wheel.angleDelta.y === 0) return
        root.changeVolumeFromWheel(wheel.angleDelta.y)
        flashing = true
        flashTimer.restart()
        wheel.accepted = true
      }

      Timer { id: flashTimer; interval: 600; onTriggered: volumeSlot.flashing = false }

      Item {
        id: volumeTrackArea
        objectName: "barVolumeTrack"
        anchors.left: volumeButton.right; anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(64); height: parent.height

        Rectangle {
          id: volumeTrack
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: volumeSlot.zoneHot || volumeSlot.dragging ? Style.space(4) : Style.space(3)
          radius: volumeSlot.zoneHot || volumeSlot.dragging ? height / 2 : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14)
          Rectangle {
            width: parent.width * volumeSlot.shownValue / 100
            height: parent.height; radius: parent.radius
            color: volumeSlot.dragging ? Color.accent
              : (volumeSlot.muted ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .4)
                : root.foreground)
          }
          Rectangle {
            visible: (volumeSlot.zoneHot || volumeSlot.dragging) && !volumeSlot.muted
            x: Math.max(0, Math.min(parent.width, parent.width * volumeSlot.shownValue / 100)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(10); height: width; radius: width / 2
            color: volumeSlot.dragging ? Color.accent : root.foreground
          }
        }

        MouseArea {
          id: volumeMouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          cursorShape: Qt.PointingHandCursor
          function ratio(x) { return Math.max(0, Math.min(100, Math.round(x / Math.max(1, width) * 100))) }
          // The bar host owns press/move, so a drag usually arrives as a plain
          // click; both paths apply the value when the button is released.
          onPressed: function(mouse) { volumeSlot.dragging = true; volumeSlot.dragValue = ratio(mouse.x) }
          onPositionChanged: function(mouse) { if (pressed) volumeSlot.dragValue = ratio(mouse.x) }
          onReleased: function(mouse) {
            if (volumeSlot.dragging) root.queueVolume(ratio(mouse.x))
            volumeSlot.dragging = false
          }
          onCanceled: volumeSlot.dragging = false
          onClicked: function(mouse) { root.queueVolume(ratio(mouse.x)) }
          onWheel: function(wheel) { volumeSlot.handleWheel(wheel) }
          onEntered: if (root.bar && !volumeSlot.dragging) root.bar.showTooltip(volumeTrackArea,
            "Громкость " + Math.round(volumeSlot.volumeValue) + "% — колесо ±5%, клик — в точку")
          onExited: if (root.bar) root.bar.hideTooltip(volumeTrackArea)
        }
      }

      Text {
        textFormat: Text.PlainText
        id: volumePercent
        anchors.left: volumeTrackArea.right; anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasError ? "—" : (volumeSlot.muted ? "mute"
          : Math.round(volumeSlot.shownValue) + "%")
        color: volumeSlot.dragging || volumeSlot.flashing || volumeSlot.muted ? Color.accent
          : (volumeSlot.zoneHot ? root.foreground
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .55))
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }
  }

  HoverHandler {
    id: informationHover
    blocking: false
  }
  Rectangle {
    objectName: "barInfoHover"
    readonly property real startX: cover.visible ? cover.x
      : (popupButton.visible ? popupButton.x
        : (labelSlot.visible ? labelSlot.x
          : (likeButton.visible ? likeButton.x
            : (showTimeText.visible ? showTimeText.x : lyricsSlot.x))))
    readonly property real endX: lyricsSlot.visible ? lyricsSlot.x + lyricsSlot.width
      : (showTimeText.visible ? showTimeText.x + showTimeText.width
        : (likeButton.visible ? likeButton.x + likeButton.width
          : (labelSlot.visible ? labelSlot.x + labelSlot.width
            : (cover.visible ? cover.x + cover.width : popupButton.x + popupButton.width))))
    x: controls.x + startX - Style.space(4)
    y: 0
    width: Math.max(0, endX - startX) + Style.space(8)
    height: root.height
    visible: !root.signedOut && !root.errorState
      && (cover.visible || popupButton.visible || labelSlot.visible || likeButton.visible
        || showTimeText.visible || lyricsSlot.visible)
      && informationHover.hovered
      && informationHover.point.position.x >= x
      && informationHover.point.position.x < x + width
    color: Style.hoverFillFor(root.foreground, Color.accent)
  }
  Rectangle {
    objectName: "barCoverHover"
    x: controls.x + cover.x - Style.space(4)
    y: 0
    width: cover.width + Style.space(8)
    height: root.height
    radius: Style.cornerRadius
    visible: cover.visible
    readonly property bool hovered: informationHover.hovered
      && informationHover.point.position.x >= x
      && informationHover.point.position.x < x + width
    readonly property bool pressed: hovered
      && (root.barMouseControls ? coverMouse.pressed : infoArea.pressed)
    color: pressed ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .2)
      : (hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
        : "transparent")
    Behavior on color {
      enabled: !(root.barMouseControls ? coverMouse.pressed : infoArea.pressed)
      ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
    }
  }
  MouseArea {
    id: infoArea
    readonly property bool includesCover: cover.visible && !root.barMouseControls
    visible: (includesCover || labelSlot.visible || showTimeText.visible || lyricsSlot.visible)
      && !root.signedOut && !root.errorState
    readonly property real startX: includesCover ? cover.x
      : (labelSlot.visible ? labelSlot.x : (showTimeText.visible ? showTimeText.x : lyricsSlot.x))
    x: controls.x + startX - Style.space(4)
    y: 0
    width: {
      var endX = lyricsSlot.visible ? (lyricsSlot.x + lyricsSlot.width)
        : (showTimeText.visible ? (showTimeText.x + showTimeText.width)
          : (likeButton.visible ? (likeButton.x + likeButton.width)
            : (labelSlot.visible ? (labelSlot.x + labelSlot.width) : (cover.x + cover.width))))
      return Math.max(0, endX - startX) + Style.space(8)
    }
    height: root.height
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (!root.logic) return
      if (root.barMouseControls) {
        if (mouse.button === Qt.LeftButton) {
          if (root.hasTrack) root.logic.transport("togglePlayback")
        } else if (mouse.button === Qt.RightButton) {
          if (root.hasTrack) { root.navigating(); root.logic.transport("nextTrack") }
        } else if (mouse.button === Qt.MiddleButton) {
          if (root.hasTrack) { root.navigating(); root.logic.transport("previousTrack") }
        }
      } else {
        if (mouse.button === Qt.RightButton) {
          if (root.hasTrack) root.logic.transport("togglePlayback")
        } else {
          root.logic.toggle()
        }
      }
    }
    function isOverLyrics(xPos) {
      if (!lyricsSlot.visible || !root.syncedLyricsAvailable) return false
      var lyricsStartX = controls.x + lyricsSlot.x
      var currentX = infoArea.x + xPos
      return currentX >= lyricsStartX
    }

    onWheel: function(wheel) { handleWheel(wheel, isOverLyrics(wheel.x)) }
    function handleWheel(wheel, overLyrics) {
      if (!root.logic || wheel.angleDelta.y === 0) return
      wheel.accepted = true
      if (root.barMouseControls) {
        if (!root.hasTrack) return
        var pos = root.displayPosition
        var dur = Number(root.logic.snapshot.duration || 0)

        if (wheel.angleDelta.y > 0) {
          // Scroll Up:
          // If over synced lyrics -> seek to next lyric line
          if (overLyrics && root.lyricsLines.length > 0) {
            var nextTime = -1
            for (var i = 0; i < root.lyricsLines.length; i++) {
              var t = Number(root.lyricsLines[i].time || 0)
              if (t > pos) { nextTime = t; break }
            }
            if (nextTime >= 0) {
              root.logic.transport("seek", nextTime)
              return
            }
          }
          // Otherwise (over title, cover, or rest of bar) -> seek +5s
          var targetForward = Math.min(dur > 0 ? dur : pos + 5, pos + 5)
          root.logic.transport("seek", targetForward)
        } else {
          // Scroll Down:
          // If over synced lyrics -> seek to previous lyric line
          if (overLyrics && root.lyricsLines.length > 0) {
            var prevTime = -1
            for (var j = root.lyricsLines.length - 1; j >= 0; j--) {
              var pt = Number(root.lyricsLines[j].time || 0)
              if (pt < pos) { prevTime = pt; break }
            }
            if (prevTime >= 0) {
              root.logic.transport("seek", prevTime)
              return
            }
          }
          // Otherwise (over title, cover, or rest of bar) -> seek -5s
          var targetBack = Math.max(0, pos - 5)
          root.logic.transport("seek", targetBack)
        }
      } else {
        root.changeVolumeFromWheel(wheel.angleDelta.y)
      }
    }
    onEntered: if (root.bar) {
      if (root.barMouseControls && root.hasTrack) {
        var tip = root.label
        if (root.targetLyricText !== "") tip += "\n[Текст] " + root.targetLyricText
        tip += "\nЛКМ: пауза · ПКМ: след. · СКМ: пред. · колесо: ±5 сек (над текстом: по строкам)"
        root.bar.showTooltip(root, tip)
      } else {
        root.bar.showTooltip(root,
          root.hasTrack ? "ЛКМ — плеер · ПКМ — пауза · колесо — громкость" : root.label)
      }
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Timer { id: navSpinnerTimer; interval: 1200; onTriggered: root.navSpinner = false }
  Timer { id: likeFlashTimer; interval: 200; onTriggered: root.likeFlash = false }
  Timer { id: likeErrorTimer; interval: 3000; onTriggered: root.likeError = false }
  Timer {
    id: likeTimeout
    interval: 4000
    onTriggered: if (root.likePending) { root.likePending = false; root.likeError = true; likeErrorTimer.restart() }
  }
  readonly property bool likedState: logic ? logic.snapshot.liked === true : false
  onLikedStateChanged: if (likePending) {
    likePending = false
    likeTimeout.stop()
    likeFlash = true
    likeFlashTimer.restart()
  }
  onLoadingChanged: if (!loading) navSpinner = false
  onHasErrorChanged: if (hasError && likePending) {
    likePending = false
    likeTimeout.stop()
    likeError = true
    likeErrorTimer.restart()
  }

  Timer {
    interval: 16
    repeat: true
    running: root.loading || root.navSpinner
    onTriggered: root.loaderAngle = (root.loaderAngle + 7.2) % 360
  }

  Rectangle {
    id: progressBarContainer
    visible: root.hasTrack && root.showProgress
    x: controls.x + (cover.visible ? cover.x : labelSlot.x)
    anchors.bottom: parent.bottom
    width: {
      var startX = cover.visible ? cover.x : labelSlot.x
      var endX = separatorItem.visible
        ? separatorItem.x
        : (showTimeText.visible ? (showTimeText.x + showTimeText.width)
          : (likeButton.visible ? (likeButton.x + likeButton.width) : (labelSlot.x + labelSlot.width)))
      return Math.max(Style.space(40), endX - startX)
    }
    height: Style.space(2)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
    opacity: root.dimmed ? .5 : 1

    Rectangle {
      width: parent.width * (root.logic
        ? Math.min(1, root.displayPosition / Math.max(1, Number(root.logic.snapshot.duration || 1)))
        : 0)
      height: parent.height
      color: Color.accent
    }
  }
}
