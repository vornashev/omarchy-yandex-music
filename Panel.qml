import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "vornashev.yandex-music"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int page: 0
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-yandex-music"
  property var data: ({ authenticated: false, playlists: [], searchResults: [] })
  property string lastError: ""
  property bool refreshing: false
  property int pendingVolume: -1
  property int sentVolume: -1
  property int pendingSeek: -1
  property int sentSeek: -1
  property bool seeking: false
  readonly property real displayPosition: (seeking || seekProcess.running) && pendingSeek >= 0
    ? pendingSeek : Number(data.position || 0)
  readonly property bool authenticated: data.authenticated === true
  readonly property bool playing: data.playing === true
  readonly property bool hasTrack: String(data.title || "") !== ""
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var queueDisplay: data.queueTracks || []
  property int previousQueueIndex: 0

  function formatTime(value) {
    var seconds = Math.max(0, Math.round(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
  }
  function refresh() {
    if (statusProcess.running) return
    refreshing = true; statusProcess.command = [cli, "details"]; statusProcess.running = true
  }
  function action(command, argument) {
    if (actionProcess.running) return
    var args = [cli, command]
    if (argument !== undefined && argument !== null) args.push(String(argument))
    actionProcess.command = args; actionProcess.running = true
  }
  function queueVolume(value) {
    var next = Math.max(0, Math.min(100, Math.round(Number(value))))
    pendingVolume = next
    var copy = {}
    for (var key in data) copy[key] = data[key]
    copy.volume = next
    copy.muted = false
    data = copy
    volumeDebounce.restart()
  }
  function volumeFromPointer(mouse, area) {
    queueVolume(mouse.x / Math.max(1, area.width) * 100)
  }
  function previewSeek(mouse, area) {
    var ratio = Math.max(0, Math.min(1, mouse.x / Math.max(1, area.width)))
    pendingSeek = Math.round(ratio * Number(data.duration || 0))
  }
  function commitSeek() {
    seeking = false
    if (pendingSeek < 0 || Number(data.duration || 0) <= 0) return
    seekCommitTimer.restart()
  }
  function applyStatus(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      var queueChanged = Number(parsed.queueIndex || 0) !== previousQueueIndex
      if (pendingVolume >= 0 && (volumeDrag.pressed || volumeProcess.running || volumeDebounce.running)) {
        parsed.volume = pendingVolume
        parsed.muted = false
      }
      data = parsed
      lastError = String(parsed.error || "")
      previousQueueIndex = Number(parsed.queueIndex || 0)
      if (queueChanged && page === 0) queueScrollTimer.restart()
    } catch (e) { lastError = "Некорректный ответ музыкального сервиса" }
  }
  function scrollToCurrentTrack() {
    if (page !== 0 || !queueRepeater || !queueList) return
    var index = Number(data.queueIndex || 0) - 1
    var item = queueRepeater.itemAt(index)
    if (!item) return
    var point = item.mapToItem(queueList.contentItem, 0, 0)
    var maximum = Math.max(0, queueList.contentHeight - queueList.height)
    queueList.contentY = Math.min(maximum, Math.max(0, point.y))
  }
  function selectPage(index) {
    page = Math.max(0, Math.min(2, index))
    if (page === 0) queueScrollTimer.restart()
    if (page === 2) Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    queueScrollTimer.restart()
  }

  Process {
    id: statusProcess; command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root.lastError = String(statusErr.text || "Сервис недоступен")
    }
  }
  Process {
    id: actionProcess; command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = String(actionErr.text || actionOut.text || "Команда не выполнена")
      settleTimer.restart()
    }
  }
  Process {
    id: volumeProcess
    command: []
    onExited: {
      if (root.pendingVolume !== root.sentVolume) volumeDebounce.restart()
      else settleTimer.restart()
    }
  }
  Process {
    id: seekProcess
    command: []
    onExited: {
      if (root.pendingSeek !== root.sentSeek) seekCommitTimer.restart()
      else {
        root.pendingSeek = -1
        settleTimer.restart()
      }
    }
  }
  Timer {
    id: volumeDebounce
    interval: 45
    repeat: false
    onTriggered: {
      if (volumeProcess.running || root.pendingVolume < 0) return
      root.sentVolume = root.pendingVolume
      volumeProcess.command = [root.cli, "volume", String(root.sentVolume)]
      volumeProcess.running = true
    }
  }
  Timer {
    id: seekCommitTimer
    interval: 0
    repeat: false
    onTriggered: {
      if (seekProcess.running || root.pendingSeek < 0) return
      root.sentSeek = root.pendingSeek
      seekProcess.command = [root.cli, "seek", String(root.sentSeek)]
      seekProcess.running = true
    }
  }
  Timer {
    interval: root.opened || root.playing || root.data.authPending ? 1000 : 5000
    running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh()
  }
  Timer { id: settleTimer; interval: 350; repeat: false; onTriggered: root.refresh() }
  Timer { id: queueScrollTimer; interval: 120; repeat: false; onTriggered: root.scrollToCurrentTrack() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.selectPage(root.page + dx) }
      onTextKey: function(t) {
        if (t === "1") root.selectPage(0)
        else if (t === "2") root.selectPage(1)
        else if (t === "3" || t === "/") root.selectPage(2)
        else if (t === " " && root.hasTrack) root.action("pause")
        else if ((t === "l" || t === "д") && root.hasTrack) root.action("like")
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Row {
            id: hero
            width: parent.width
            height: Style.space(68)
            spacing: Style.space(14)

            BorderSurface {
              width: Style.space(68); height: Style.space(68)
              radius: Style.spacing.labelGap
              color: Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Image {
                anchors.fill: parent; anchors.margins: Style.space(2)
                source: root.data.artUrl || ""; fillMode: Image.PreserveAspectCrop
                asynchronous: true; visible: source !== ""
              }
              Text {
                anchors.centerIn: parent; visible: !root.data.artUrl
                text: "󰝚"; color: root.foreground; font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: parent.width - Style.space(82)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: root.hasTrack ? String(root.data.title) : "Яндекс Музыка"
                color: root.foreground; font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle; font.bold: true; elide: Text.ElideRight
              }

              Item {
                visible: root.hasTrack
                width: parent.width
                height: visible ? Style.space(16) : 0
                clip: true

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Repeater {
                    model: root.data.artists || []
                    Text {
                      id: heroArtistLink
                      required property var modelData
                      required property int index
                      text: modelData.name + (index < (root.data.artists || []).length - 1 ? ", " : "")
                      color: heroArtistMouse.containsMouse ? Color.accent : root.dim
                      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                      font.bold: heroArtistMouse.containsMouse
                      MouseArea {
                        id: heroArtistMouse; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.action("artist", heroArtistLink.modelData.id)
                      }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: root.hasTrack
                  ? String(root.data.album || root.data.queueName || "")
                  : (root.authenticated ? "Выберите музыку" : "Автономный плеер")
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.lastError !== ""; width: parent.width; wrapMode: Text.WordWrap
            text: root.lastError; color: Color.urgent; font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            visible: !root.authenticated; width: parent.width; spacing: Style.space(10)
            Text {
              visible: root.data.connecting === true
              text: "Проверяем сохранённую сессию…"; color: root.foreground
              font.family: root.fontFamily; font.pixelSize: Style.font.body
            }
            Text {
              visible: root.data.authPending === true && String(root.data.authCode || "") !== ""
              width: parent.width; horizontalAlignment: Text.AlignHCenter
              text: "Код: " + root.data.authCode; color: root.foreground
              font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true
            }
            BorderSurface {
              width: parent.width; height: Style.space(44); radius: Style.cornerRadius
              color: authMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Text {
                anchors.centerIn: parent
                text: root.data.authUrl ? "Открыть страницу авторизации" : "Войти через Яндекс"
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
              }
              MouseArea {
                id: authMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: if (root.data.authUrl) Quickshell.execDetached(["xdg-open", String(root.data.authUrl)]); else root.action("auth")
              }
            }
          }

          Column {
            visible: root.authenticated; width: parent.width; spacing: Style.space(12)

            Row {
              width: parent.width; spacing: Style.space(4)
              Repeater {
                model: ["СЕЙЧАС", "МЕДИАТЕКА", "ПОИСК"]
                BorderSurface {
                  required property string modelData
                  required property int index
                  width: (content.width - Style.space(8)) / 3; height: Style.space(34)
                  radius: Style.cornerRadius
                  color: root.page === index ? Style.selectedFillFor(root.foreground, Color.accent)
                    : (tabMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  borderSpec: root.page === index ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none()
                  Text {
                    anchors.centerIn: parent; text: modelData; color: root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.caption
                    font.bold: root.page === index; font.letterSpacing: .5
                  }
                  MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPage(index) }
                }
              }
            }

            Column {
              visible: root.page === 0; width: parent.width; spacing: Style.space(14)

              Item {
                visible: root.hasTrack; width: parent.width; height: Style.space(28)
                Rectangle {
                  id: progressTrack; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6); radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
                  Rectangle {
                    width: parent.width * Math.min(1, root.displayPosition / Math.max(1, Number(root.data.duration || 1)))
                    height: parent.height; radius: parent.radius; color: Color.accent
                  }
                  MouseArea {
                    id: seekDrag
                    anchors.fill: parent
                    anchors.topMargin: -Style.space(8); anchors.bottomMargin: -Style.space(8)
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) {
                      root.seeking = true
                      root.previewSeek(mouse, seekDrag)
                    }
                    onPositionChanged: function(mouse) {
                      if (pressed) root.previewSeek(mouse, seekDrag)
                    }
                    onReleased: function(mouse) {
                      root.previewSeek(mouse, seekDrag)
                      root.commitSeek()
                    }
                    onCanceled: root.seeking = false
                  }
                }
                Text {
                  anchors.left: parent.left; anchors.top: progressTrack.bottom; anchors.topMargin: Style.space(3)
                  text: root.formatTime(root.data.position)
                    + (root.seeking && root.pendingSeek >= 0 ? "  (" + root.formatTime(root.pendingSeek) + ")" : "")
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.right: parent.right; anchors.top: progressTrack.bottom; anchors.topMargin: Style.space(3)
                  text: root.formatTime(root.data.duration); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }

              Row {
                width: parent.width
                height: Math.max(playbackControls.implicitHeight, muteButton.implicitHeight)
                spacing: Style.space(8)

                Row {
                  id: playbackControls
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                    iconText: "󰒮"; tooltipText: "Предыдущий"; foreground: root.foreground
                    onClicked: root.action("previous")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                    iconText: root.playing ? "󰏤" : "󰐊"; tooltipText: root.playing ? "Пауза" : "Продолжить"
                    foreground: root.foreground; enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("pause")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                    iconText: "󰒭"; tooltipText: "Следующий"; foreground: root.foreground
                    onClicked: root.action("next")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 19
                    iconText: root.data.liked ? "󰋑" : "󰋕"
                    tooltipText: root.data.liked ? "Убрать из «Мне нравится»" : "Добавить в «Мне нравится»"
                    foreground: root.data.liked ? Color.accent : root.foreground
                    enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("like")
                  }
                }

                Rectangle {
                  width: Style.spacing.hairline; height: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.foreground; opacity: .16
                }

                Button {
                  id: muteButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: root.data.muted ? "󰖁" : "󰕾"
                  tooltipText: root.data.muted ? "Включить звук" : "Выключить звук"
                  foreground: root.foreground
                  onClicked: root.action("mute")
                }

                Rectangle {
                  id: volumeTrack
                  width: Math.max(Style.space(70), parent.width - playbackControls.width
                    - muteButton.width - volumePercent.width - Style.space(42))
                  height: Style.space(6); radius: height / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
                  Rectangle {
                    width: parent.width * Number(root.data.volume || 0) / 100
                    height: parent.height; radius: parent.radius
                    color: root.data.muted ? root.dim : root.foreground
                  }
                  MouseArea {
                    id: volumeDrag
                    anchors.fill: parent
                    anchors.topMargin: -Style.space(9); anchors.bottomMargin: -Style.space(9)
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) { root.volumeFromPointer(mouse, volumeDrag) }
                    onPositionChanged: function(mouse) {
                      if (pressed) root.volumeFromPointer(mouse, volumeDrag)
                    }
                    onReleased: function(mouse) {
                      root.volumeFromPointer(mouse, volumeDrag)
                      volumeDebounce.restart()
                    }
                  }
                }

                Text {
                  id: volumePercent
                  width: Style.space(34)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignRight
                  text: root.data.muted ? "MUTE" : Math.round(Number(root.data.volume || 0)) + "%"
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: !root.hasTrack; width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Выберите плейлист в медиатеке или найдите трек"
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
              }

              PanelSeparator { visible: root.queueDisplay.length > 0; foreground: root.foreground }

              Item {
                visible: root.queueDisplay.length > 0
                width: parent.width
                height: visible ? Math.max(queueHeading.implicitHeight, queuePosition.implicitHeight) : 0

                Text {
                  id: queueHeading
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - queuePosition.width - Style.space(12)
                  text: "ОЧЕРЕДЬ" + (root.data.queueName ? " · " + root.data.queueName : "")
                  elide: Text.ElideRight
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.letterSpacing: 1
                }

                Text {
                  id: queuePosition
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.data.queueCount ? root.data.queueIndex + "/" + root.data.queueCount : ""
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Flickable {
                id: queueList
                visible: root.queueDisplay.length > 0
                width: parent.width
                height: visible ? Math.min(queueColumn.implicitHeight, Style.space(260)) : 0
                contentWidth: width
                contentHeight: queueColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                  id: queueColumn
                  width: queueList.width - (queueList.contentHeight > queueList.height ? Style.space(8) : 0)
                  spacing: 0

                  Repeater {
                    id: queueRepeater
                    model: root.queueDisplay
                    BorderSurface {
                      id: queueRow
                      required property var modelData
                      width: queueColumn.width
                      height: Style.space(50)
                      radius: Style.cornerRadius
                      color: modelData.current
                        ? Style.selectedFillFor(root.foreground, Color.accent)
                        : (queueMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                      borderSpec: modelData.current
                        ? Border.controlSpec("normal", root.foreground, Color.accent)
                        : Border.none()

                      Row {
                        z: 1
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(9)

                        Text {
                          width: Style.space(18); anchors.verticalCenter: parent.verticalCenter
                          horizontalAlignment: Text.AlignHCenter
                          text: modelData.current ? (root.playing ? "󰏤" : "󰐊") : String(modelData.index + 1)
                          color: modelData.current ? Color.accent : root.dim
                          font.family: root.fontFamily; font.pixelSize: Style.font.caption
                        }
                        Column {
                          width: parent.width - Style.space(76); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                          Text {
                            width: parent.width; text: modelData.title; elide: Text.ElideRight
                            color: root.foreground; font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall; font.bold: modelData.current
                          }
                          Item {
                            width: parent.width
                            height: Style.space(14)
                            clip: true
                            Row {
                              anchors.left: parent.left
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: 0
                              Repeater {
                                model: queueRow.modelData.artists || []
                                Text {
                                  id: queueArtistLink
                                  required property var modelData
                                  required property int index
                                  text: modelData.name + (index < (queueRow.modelData.artists || []).length - 1 ? ", " : "")
                                  color: queueArtistMouse.containsMouse ? Color.accent : root.dim
                                  font.family: root.fontFamily; font.pixelSize: Style.font.caption
                                  MouseArea {
                                    id: queueArtistMouse; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.action("artist", queueArtistLink.modelData.id)
                                  }
                                }
                              }
                            }
                          }
                        }
                        Text {
                          width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                          horizontalAlignment: Text.AlignRight; text: root.formatTime(modelData.duration)
                          color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                        }
                      }
                      MouseArea {
                        id: queueMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!modelData.current) root.action("play_queue", modelData.index)
                      }
                    }
                  }
                }
              }
            }

            Column {
              visible: root.page === 1; width: parent.width; spacing: Style.space(6)
              BorderSurface {
                width: parent.width; height: Style.space(48); radius: Style.cornerRadius
                color: waveMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
                  : Style.normalFillFor(root.foreground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                Text {
                  anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
                  text: "󰝚   Моя волна"; color: root.foreground; font.family: root.fontFamily
                  font.pixelSize: Style.font.body; font.bold: true
                }
                MouseArea {
                  id: waveMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: { root.action("wave"); root.selectPage(0) }
                }
              }
              BorderSurface {
                width: parent.width; height: Style.space(44); radius: Style.cornerRadius
                color: likesMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                Text {
                  anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
                  text: "󰋑   Мне нравится"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
                }
                MouseArea { id: likesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.action("likes"); root.selectPage(0) } }
              }
              Repeater {
                model: root.data.playlists || []
                BorderSurface {
                  required property var modelData
                  width: content.width; height: Style.space(42); radius: Style.cornerRadius
                  color: playlistMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  borderSpec: Border.none()
                  Text {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(12); anchors.verticalCenter: parent.verticalCenter
                    text: "󰲸   " + modelData.title + "  ·  " + modelData.count; elide: Text.ElideRight
                    color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea { id: playlistMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.action("playlist", modelData.kind); root.selectPage(0) } }
                }
              }
              Text {
                visible: (root.data.playlists || []).length === 0; width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Пользовательских плейлистов пока нет"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              visible: root.page === 2; width: parent.width; spacing: Style.space(6)
              Row {
                width: parent.width; spacing: Style.space(8)
                TextField {
                  id: searchField; width: parent.width - searchButton.width - parent.spacing
                  placeholderText: "Трек или исполнитель"; foreground: root.foreground; font.family: root.fontFamily
                  Keys.onReturnPressed: root.action("search", text)
                  Keys.onEscapePressed: { focus = false; keyCatcher.forceActiveFocus() }
                }
                Button { id: searchButton; iconText: "󰍉"; tooltipText: "Найти"; foreground: root.foreground; onClicked: root.action("search", searchField.text) }
              }
              Repeater {
                model: root.data.searchResults || []
                BorderSurface {
                  required property var modelData
                  width: content.width; height: Style.space(48); radius: Style.cornerRadius
                  color: resultMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"; borderSpec: Border.none()
                  Column {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    Text { width: parent.width; text: modelData.title; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                    Text { width: parent.width; text: modelData.artist; elide: Text.ElideRight; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  }
                  MouseArea { id: resultMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.action("play_search", modelData.index); root.selectPage(0) } }
                }
              }
            }

            Text {
              visible: root.data.loading === true; text: "Загрузка…"; color: root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Выйти из аккаунта"
              color: Qt.darker(root.foreground, 1.8); font.family: root.fontFamily; font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.action("logout") }
            }
          }
        }
      }
    }
  }
}
