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
  property int pageBeforeSettings: 0
  property bool settingsOpen: false
  property bool confirmLogout: false
  property bool waveOptionsOpen: false
  property bool lyricsOpen: false
  property bool lyricsAutoScroll: true
  property var lyricsData: ({ trackId: "", loading: false, available: false,
    synced: false, format: "", writers: [], lines: [], error: "" })
  property bool trackInfoOpen: false
  property var trackInfoData: ({ trackId: "", loading: false, available: false,
    credits: [], error: "" })
  property bool coverExpanded: false
  property bool coverTransitioning: false
  property int coverStablePanelHeight: 0
  readonly property int coverTransitionDuration: 280
  property string copiedAuthCode: ""
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-yandex-music"
  property var data: ({ authenticated: false, playlists: [], searchResults: [] })
  property string lastError: ""
  property string dismissedError: ""
  property string errorSource: ""
  property string lastActionCommand: ""
  property var lastActionArgument: undefined
  property bool refreshing: false
  property bool hasLoadedStatus: false
  property int pendingVolume: -1
  property int sentVolume: -1
  property int pendingSeek: -1
  property int sentSeek: -1
  property bool seeking: false
  property int busySeconds: 0
  property double positionClockMs: Date.now()
  readonly property real playbackPosition: {
    var position = Number(data.position || 0)
    var observedAt = Number(data.positionObservedAt || 0)
    if (playing && data.stopped !== true && observedAt > 0) {
      var elapsed = Math.max(0, positionClockMs / 1000 - observedAt)
      position += Math.min(3, elapsed)
    }
    var duration = Number(data.duration || 0)
    return Math.max(0, duration > 0 ? Math.min(duration, position) : position)
  }
  readonly property real displayPosition: (seeking || seekProcess.running) && pendingSeek >= 0
    ? pendingSeek : playbackPosition
  readonly property bool authenticated: data.authenticated === true
  readonly property bool playing: data.playing === true
  readonly property bool hasTrack: String(data.title || "") !== ""
  readonly property string currentTrackId: String(data.trackId || "")
  readonly property var lyricsLines: lyricsData.lines || []
  readonly property bool lyricsLoading: lyricsData.loading === true
  readonly property int lyricsCurrentIndex: currentLyricsLineIndex()
  readonly property bool trackInfoLoading: trackInfoData.loading === true
  readonly property var trackInfoRows: buildTrackInfoRows()
  readonly property bool currentTrackPaneOpen: lyricsOpen || trackInfoOpen
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Keep the queue model independent from frequently replaced status objects.
  // Rebinding ListView to an equivalent JS array resets its internal viewport.
  property var queueDisplay: []
  readonly property var artistDisplay: data.artistTracks || []
  readonly property var libraryDisplay: data.libraryTracks || []
  readonly property bool browsingArtist: artistDisplay.length > 0
  readonly property bool browsingLibrary: libraryDisplay.length > 0
  readonly property bool browsingCollection: browsingArtist || browsingLibrary
  readonly property var trackListDisplay: browsingArtist ? artistDisplay
    : (browsingLibrary ? libraryDisplay : queueDisplay)
  readonly property string playbackMode: String(preference("playbackMode", "repeatQueue"))
  readonly property string playbackModeIcon: playbackMode === "shuffle" ? "󰒟"
    : (playbackMode === "repeatTrack" ? "󰑘" : (playbackMode === "repeatQueue" ? "󰑖" : "󰐕"))
  readonly property string playbackModeLabel: playbackMode === "shuffle" ? "Перемешивание"
    : (playbackMode === "repeatTrack" ? "Повтор трека"
    : (playbackMode === "repeatQueue" ? "Повтор очереди" : "По порядку"))
  readonly property bool busy: data.connecting === true || data.restoring === true
    || data.loading === true || data.libraryLoadingMore === true
    || actionProcess.running || settingsProcess.running
    || (refreshing && !hasLoadedStatus)
  readonly property var networkInfo: data.network || ({})
  readonly property bool hasVisibleError: lastError !== "" && lastError !== dismissedError
  readonly property bool queueListLoading: data.loading === true
    && ["artist", "likes", "playlist", "wave", "radio"].indexOf(String(data.loadingKind || "")) >= 0
  readonly property bool searchListLoading: data.loading === true
    && String(data.loadingKind || "") === "search"
  readonly property string errorTitle: errorSource === "status"
    ? "Нет связи с музыкальным сервисом"
    : (errorSource === "backend" ? "Ошибка Яндекс Музыки" : "Не удалось выполнить действие")
  readonly property string loadingMessage: {
    if (refreshing && !hasLoadedStatus) return "Проверяем состояние сервиса…"
    if (data.connecting === true) return "Подключаемся к Яндекс Музыке…"
    if (data.restoring === true) return "Восстанавливаем очередь и позицию…"
    if (String(data.loadingStage || "") === "rateLimit")
      return "Яндекс ограничил запросы — повторяем с паузой…"
    if (data.libraryLoadingMore === true) return "Загружаем следующую страницу…"
    var kind = String(data.loadingKind || "")
    if (kind === "wave") return "Настраиваем «Мою волну»…"
    if (kind === "radio") return "Запускаем радио по треку…"
    if (kind === "likes") return "Загружаем любимые треки…"
    if (kind === "playlist") return "Загружаем плейлист…"
    if (kind === "search") return "Ищем треки…"
    if (kind === "artist") return "Загружаем треки исполнителя…"
    if (kind === "track" && String(data.loadingStage || "") === "downloadInfo")
      return "Получаем временную ссылку на трек…"
    if (kind === "track" && String(data.loadingStage || "") === "audioStream")
      return "Подключаем аудиопоток к mpv…"
    if (kind === "track") return "Подготавливаем трек…"
    if (settingsProcess.running) return "Сохраняем настройки…"
    if (actionProcess.running && lastActionCommand === "like") return "Обновляем отметку «Мне нравится»…"
    if (actionProcess.running && lastActionCommand === "dislike") return "Обновляем отметку «Не рекомендовать»…"
    if (actionProcess.running) return "Выполняем действие…"
    return "Загрузка…"
  }
  readonly property string loaderTooltip: {
    var lines = ["Сейчас: " + loadingMessage]
    if (busySeconds > 0) lines.push("Ожидание: " + busySeconds + " с")
    if (networkInfo.checking === true) {
      lines.push("API Яндекс Музыки: проверяем…")
    } else if (networkInfo.available === true) {
      var latency = Number(networkInfo.latencyMs || 0)
      lines.push("API Яндекс Музыки: доступно" + (latency > 0 ? " · " + latency + " мс" : ""))
      if (networkInfo.serviceAvailable === false)
        lines.push("Музыка недоступна для текущего региона")
      else if (networkInfo.serviceAvailable === true)
        lines.push("Музыка доступна для текущего региона")
    } else if (networkInfo.available === false) {
      lines.push("API Яндекс Музыки: недоступно"
        + (networkInfo.error ? " · " + networkInfo.error : ""))
    } else {
      lines.push("API Яндекс Музыки: ещё не проверено")
    }
    return lines.join("\n")
  }
  property int previousQueueIndex: 0

  function preference(key, fallback) {
    var preferences = data.preferences || {}
    return preferences[key] === undefined ? fallback : preferences[key]
  }
  function copyAuthCode() {
    var code = String(data.authCode || "").trim()
    if (code === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(code) + " | wl-copy"])
    copiedAuthCode = code
    authCodeCopiedTimer.restart()
  }
  function checkNetwork() {
    if (networkProcess.running) return
    networkProcess.command = [cli, "network"]
    networkProcess.running = true
  }
  function setPreference(key, value) {
    if (settingsProcess.running) return
    var preferences = {}
    var current = data.preferences || {}
    for (var preferenceKey in current) preferences[preferenceKey] = current[preferenceKey]
    preferences[key] = value
    var copy = {}
    for (var dataKey in data) copy[dataKey] = data[dataKey]
    copy.preferences = preferences
    data = copy
    settingsProcess.command = [cli, "setting", key, String(value)]
    settingsProcess.running = true
  }
  function setCoverExpanded(value) {
    var next = value === true && authenticated && hasTrack && !settingsOpen
    if (coverExpanded === next) return
    if (next) coverStablePanelHeight = panel.contentHeight
    coverTransitioning = true
    coverTransitionTimer.restart()
    coverExpanded = next
    if (next) {
      lyricsOpen = false
      trackInfoOpen = false
      page = 0
      searchField.focus = false
      panelScroll.contentY = 0
      keyCatcher.forceActiveFocus()
    }
  }
  function openSettings() {
    setCoverExpanded(false)
    pageBeforeSettings = page
    confirmLogout = false
    settingsOpen = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function closeSettings() {
    settingsOpen = false
    confirmLogout = false
    page = pageBeforeSettings
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function formatTime(value) {
    var seconds = Math.max(0, Math.round(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
  }
  function emptyLyrics(trackId, loading) {
    return { trackId: String(trackId || ""), loading: loading === true,
      available: false, synced: false, format: "", writers: [], lines: [], error: "" }
  }
  function currentLyricsLineIndex() {
    if (!lyricsData.synced || String(lyricsData.trackId || "") !== currentTrackId) return -1
    var current = -1
    for (var i = 0; i < lyricsLines.length; i++) {
      var timestamp = Number(lyricsLines[i].time)
      if (timestamp < 0) continue
      if (timestamp <= displayPosition + .05) current = i
      else break
    }
    return current
  }
  function setLyricsOpen(value) {
    var next = value === true && hasTrack
    if (lyricsOpen === next) return
    lyricsOpen = next
    lyricsAutoScroll = true
    if (!next) return
    trackInfoOpen = false
    if (String(lyricsData.trackId || "") !== currentTrackId)
      lyricsData = emptyLyrics(currentTrackId, true)
    refreshLyrics(false)
    lyricsScrollTimer.restart()
  }
  function refreshLyrics(force) {
    if (!lyricsOpen || !hasTrack || lyricsProcess.running) return
    lyricsProcess.command = [cli, force === true ? "lyrics_refresh" : "lyrics"]
    lyricsProcess.running = true
  }
  function applyLyrics(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      if (String(parsed.trackId || "") !== currentTrackId) {
        lyricsData = emptyLyrics(currentTrackId, true)
        lyricsPollTimer.restart()
        return
      }
      lyricsData = parsed
      if (parsed.loading === true) lyricsPollTimer.restart()
      else lyricsScrollTimer.restart()
    } catch (e) {
      var failed = emptyLyrics(currentTrackId, false)
      failed.error = "Музыкальный сервис вернул некорректный текст песни"
      lyricsData = failed
    }
  }
  function scrollToCurrentLyric() {
    if (!lyricsOpen || !lyricsAutoScroll || !lyricsData.synced
        || lyricsCurrentIndex < 0 || lyricsCurrentIndex >= lyricsList.count) return
    lyricsList.positionViewAtIndex(lyricsCurrentIndex, ListView.Center)
  }
  function seekToLyric(value) {
    if (!lyricsData.synced || Number(value) < 0) return
    pendingSeek = Math.max(0, Math.min(Number(data.duration || value), Math.round(Number(value))))
    lyricsAutoScroll = true
    commitSeek()
  }
  function emptyTrackInfo(trackId, loading) {
    return { trackId: String(trackId || ""), loading: loading === true,
      available: false, credits: [], error: "" }
  }
  function buildTrackInfoRows() {
    var rows = []
    function add(label, value) {
      var text = String(value === undefined || value === null ? "" : value).trim()
      if (text !== "") rows.push({ kind: "detail", label: label, value: text })
    }
    add("Альбом", trackInfoData.album)
    add("Дата релиза", trackInfoData.releaseDate || trackInfoData.year)
    add("Жанр", trackInfoData.genre)
    add("Лейбл", (trackInfoData.labels || []).join(", "))
    var trackNumber = Number(trackInfoData.trackNumber || 0)
    var discNumber = Number(trackInfoData.discNumber || 0)
    if (trackNumber > 0)
      add("Номер трека", String(trackNumber) + (discNumber > 1 ? " · диск " + discNumber : ""))
    if (Number(trackInfoData.duration || 0) > 0)
      add("Длительность", formatTime(trackInfoData.duration))
    add("Версия", trackInfoData.version)
    if (trackInfoData.explicit === true) add("Контент", "Ненормативная лексика")
    add("Другие названия", (trackInfoData.aliases || []).join(", "))
    if (String(trackInfoData.description || "").trim() !== "")
      rows.push({ kind: "detail", label: "Описание",
        value: String(trackInfoData.description).trim() })
    var credits = trackInfoData.credits || []
    if (credits.length > 0) rows.push({ kind: "section", label: "УЧАСТНИКИ", value: "" })
    for (var i = 0; i < credits.length; i++) {
      var credit = credits[i] || {}
      add(String(credit.title || "Участник"), credit.value)
    }
    return rows
  }
  function setTrackInfoOpen(value) {
    var next = value === true && hasTrack
    if (trackInfoOpen === next) return
    trackInfoOpen = next
    if (!next) return
    lyricsOpen = false
    if (String(trackInfoData.trackId || "") !== currentTrackId)
      trackInfoData = emptyTrackInfo(currentTrackId, true)
    refreshTrackInfo(false)
  }
  function refreshTrackInfo(force) {
    if (!trackInfoOpen || !hasTrack || trackInfoProcess.running) return
    trackInfoProcess.command = [cli, force === true ? "track_info_refresh" : "track_info"]
    trackInfoProcess.running = true
  }
  function applyTrackInfo(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      if (String(parsed.trackId || "") !== currentTrackId) {
        trackInfoData = emptyTrackInfo(currentTrackId, true)
        trackInfoPollTimer.restart()
        return
      }
      trackInfoData = parsed
      if (parsed.loading === true) trackInfoPollTimer.restart()
      else Qt.callLater(function() {
        if (root.trackInfoOpen) trackInfoList.positionViewAtBeginning()
      })
    } catch (e) {
      var failed = emptyTrackInfo(currentTrackId, false)
      failed.error = "Музыкальный сервис вернул некорректные сведения о треке"
      trackInfoData = failed
    }
  }
  function refresh() {
    if (statusProcess.running) return
    refreshing = true; statusProcess.command = [cli, "details"]; statusProcess.running = true
  }
  function maybeLoadMoreLibrary() {
    if (!root.browsingLibrary || root.data.libraryHasMore !== true
        || root.data.libraryLoadingMore === true || actionProcess.running) return
    if (queueList.contentY + queueList.height >= queueList.contentHeight - Style.space(50))
      root.action("load_more_library")
  }
  function normalizeShortcutKey(value) {
    var t = String(value || "").toLowerCase()
    var qwertyFromRussian = {
      "т": "n", "з": "p", "д": "l", "в": "d", "а": "f", "с": "c"
    }
    return qwertyFromRussian[t] || t
  }
  function runPlayerShortcut(value) {
    var t = normalizeShortcutKey(value)
    if (!hasTrack) return false
    if (t === " ") action("pause")
    else if (t === "l") action("like")
    else if (t === "d") action("dislike")
    else if (t === "n") action("next")
    else if (t === "p") action("previous")
    else if (t === "f") setCoverExpanded(!coverExpanded)
    else return false
    return true
  }
  function action(command, argument) {
    if (actionProcess.running) return
    lastActionCommand = command
    lastActionArgument = argument
    dismissedError = ""
    errorSource = ""
    var loadingKinds = { "artist": "artist", "likes": "likes", "playlist": "playlist",
      "wave": "wave", "track_radio": "radio", "search": "search" }
    if (loadingKinds[command] !== undefined || command === "load_more_library") {
      var optimistic = {}
      for (var key in data) optimistic[key] = data[key]
      if (loadingKinds[command] !== undefined) {
        optimistic.loading = true
        optimistic.loadingKind = loadingKinds[command]
      } else {
        optimistic.libraryLoadingMore = true
      }
      optimistic.error = ""
      data = optimistic
    }
    var args = [cli, command]
    if (argument !== undefined && argument !== null) args.push(String(argument))
    actionProcess.command = args; actionProcess.running = true
    if (command === "search") searchResultsList.positionViewAtBeginning()
  }
  function retryLastOperation() {
    dismissedError = ""
    lastError = ""
    if (errorSource === "status" || lastActionCommand === "") refresh()
    else action(lastActionCommand, lastActionArgument)
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
      var browseChanged = String(parsed.artistBrowseName || "") !== String(data.artistBrowseName || "")
        || String(parsed.libraryBrowseName || "") !== String(data.libraryBrowseName || "")
      var previousContentY = queueList.contentY
      var libraryExpanded = (parsed.libraryTracks || []).length > (data.libraryTracks || []).length
      if (Number(parsed.libraryRevision || 0) === Number(data.libraryRevision || 0))
        parsed.libraryTracks = data.libraryTracks || []
      if (Number(parsed.queueRevision || 0) === Number(data.queueRevision || 0)) {
        parsed.queueTracks = queueDisplay
      } else {
        queueDisplay = parsed.queueTracks || []
      }
      if (pendingVolume >= 0 && (volumeDrag.pressed || volumeProcess.running || volumeDebounce.running)) {
        parsed.volume = pendingVolume
        parsed.muted = false
      }
      data = parsed
      positionClockMs = Date.now()
      hasLoadedStatus = true
      var nextError = String(parsed.error || "")
      if (nextError !== lastError) dismissedError = ""
      lastError = nextError
      errorSource = lastError === "" ? "" : "backend"
      previousQueueIndex = Number(parsed.queueIndex || 0)
      if (queueChanged && page === 0) queueScrollTimer.restart()
      if (browseChanged && (String(parsed.artistBrowseName || "") !== ""
          || String(parsed.libraryBrowseName || "") !== ""))
        Qt.callLater(function() { queueList.contentY = 0 })
      else if (libraryExpanded)
        Qt.callLater(function() {
          queueList.contentY = Math.min(previousContentY,
            Math.max(0, queueList.contentHeight - queueList.height))
        })
    } catch (e) {
      errorSource = "status"
      lastError = "Музыкальный сервис вернул некорректный ответ"
    }
  }
  function scrollToCurrentTrack() {
    if (page !== 0 || browsingCollection || !queueList) return
    var index = Number(data.queueIndex || 0) - 1
    if (index < 0 || index >= queueList.count) return

    var item = queueList.itemAtIndex(index)
    var rowHeight = Style.space(50)
    var itemTop = item ? item.y : queueList.originY + index * rowHeight
    var itemBottom = itemTop + (item ? item.height : rowHeight)
    var viewportTop = queueList.contentY
    var viewportBottom = viewportTop + queueList.height
    var tolerance = 1
    if (itemTop >= viewportTop - tolerance && itemBottom <= viewportBottom + tolerance) return

    var targetY = itemTop < viewportTop ? itemTop : itemBottom - queueList.height
    var minimumY = queueList.originY
    var maximumY = Math.max(minimumY, minimumY + queueList.contentHeight - queueList.height)
    queueList.contentY = Math.max(minimumY, Math.min(targetY, maximumY))
  }
  function selectPage(index) {
    setCoverExpanded(false)
    settingsOpen = false
    confirmLogout = false
    page = Math.max(0, Math.min(2, index))
    if (page !== 0) {
      setLyricsOpen(false)
      setTrackInfoOpen(false)
    }
    if (page === 0) queueScrollTimer.restart()
    if (page === 2) {
      Qt.callLater(function() {
        if (root.page !== 2 || root.settingsOpen) return
        panelScroll.contentY = 0
        searchField.forceActiveFocus()
      })
    } else {
      // A hidden TextField keeps active focus unless it is transferred
      // explicitly, which would make it consume shortcuts from other pages.
      searchField.focus = false
      keyCatcher.forceActiveFocus()
    }
  }

  onBusyChanged: if (busy) busySeconds = 0
  onHasTrackChanged: if (!hasTrack) {
    setCoverExpanded(false)
    setLyricsOpen(false)
    setTrackInfoOpen(false)
  }
  onCurrentTrackIdChanged: {
    if (lyricsOpen) {
      lyricsData = emptyLyrics(currentTrackId, true)
      lyricsAutoScroll = true
      lyricsPollTimer.restart()
    }
    if (trackInfoOpen) {
      trackInfoData = emptyTrackInfo(currentTrackId, true)
      trackInfoPollTimer.restart()
    }
  }
  onLyricsCurrentIndexChanged: if (lyricsAutoScroll) lyricsScrollTimer.restart()

  onOpenedChanged: {
    if (opened) {
      positionClockMs = Date.now()
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      queueScrollTimer.restart()
    } else {
      settingsOpen = false
      confirmLogout = false
    }
  }

  Process {
    id: statusProcess; command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else {
        root.errorSource = "status"
        root.lastError = String(statusErr.text || "Фоновый музыкальный сервис недоступен")
      }
    }
  }
  Process {
    id: networkProcess; command: []
    stdout: StdioCollector { id: networkOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try {
          var copy = {}
          for (var key in root.data) copy[key] = root.data[key]
          copy.network = JSON.parse(networkOut.text || "{}")
          root.data = copy
        } catch (e) {}
      }
    }
  }
  Process {
    id: lyricsProcess; command: []
    stdout: StdioCollector { id: lyricsOut; waitForEnd: true }
    stderr: StdioCollector { id: lyricsErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyLyrics(lyricsOut.text)
      else {
        var failed = root.emptyLyrics(root.currentTrackId, false)
        failed.error = String(lyricsErr.text || "Не удалось получить текст песни")
        root.lyricsData = failed
      }
    }
  }
  Process {
    id: trackInfoProcess; command: []
    stdout: StdioCollector { id: trackInfoOut; waitForEnd: true }
    stderr: StdioCollector { id: trackInfoErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyTrackInfo(trackInfoOut.text)
      else {
        var failed = root.emptyTrackInfo(root.currentTrackId, false)
        failed.error = String(trackInfoErr.text || "Не удалось получить сведения о треке")
        root.trackInfoData = failed
      }
    }
  }
  Process {
    id: actionProcess; command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorSource = "action"
        root.lastError = String(actionErr.text || actionOut.text || "Не удалось выполнить действие")
      }
      settleTimer.restart()
    }
  }
  Process {
    id: settingsProcess
    command: []
    stdout: StdioCollector { id: settingsOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorSource = "action"
        root.lastError = String(settingsErr.text || settingsOut.text || "Не удалось сохранить настройку")
      }
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
  Timer {
    interval: 100
    running: root.opened && root.playing
    repeat: true
    onTriggered: root.positionClockMs = Date.now()
  }
  Timer { id: settleTimer; interval: 350; repeat: false; onTriggered: root.refresh() }
  Timer { id: queueScrollTimer; interval: 120; repeat: false; onTriggered: root.scrollToCurrentTrack() }
  Timer { id: lyricsPollTimer; interval: 500; repeat: false; onTriggered: root.refreshLyrics(false) }
  Timer { id: trackInfoPollTimer; interval: 500; repeat: false; onTriggered: root.refreshTrackInfo(false) }
  Timer { id: lyricsScrollTimer; interval: 100; repeat: false; onTriggered: root.scrollToCurrentLyric() }
  Timer {
    id: lyricsResumeScrollTimer
    interval: 3500
    repeat: false
    onTriggered: {
      root.lyricsAutoScroll = true
      root.scrollToCurrentLyric()
    }
  }
  Timer {
    id: coverTransitionTimer
    interval: root.coverTransitionDuration + 40
    repeat: false
    onTriggered: root.coverTransitioning = false
  }
  Timer {
    id: busyDurationTimer
    interval: 1000
    repeat: true
    running: root.busy
    onTriggered: root.busySeconds += 1
  }
  Timer {
    id: apiProbeDelay
    interval: 1800
    repeat: false
    running: root.busy
    onTriggered: root.checkNetwork()
  }
  Timer {
    id: authCodeCopiedTimer
    interval: 1800
    repeat: false
    onTriggered: root.copiedAuthCode = ""
  }

  component SkeletonList: Column {
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: (root.coverExpanded || root.coverTransitioning)
        && root.coverStablePanelHeight > 0
      ? root.coverStablePanelHeight
      : panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    // PanelKeyCatcher reserves h/j/k/l for directional navigation before
    // onTextKey runs. Give player shortcuts the first chance, especially L.
    Item {
      id: shortcutInterceptor
      Keys.onPressed: function(event) {
        if (event.modifiers & ~Qt.KeypadModifier) return
        if (root.settingsOpen || searchField.activeFocus || !root.hasTrack) return
        var t = event.text ? String(event.text).toLowerCase() : ""
        if (!t && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
          t = String.fromCharCode(event.key).toLowerCase()
        if (root.runPlayerShortcut(t)) event.accepted = true
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      Keys.forwardTo: [shortcutInterceptor]
      blocked: searchField.activeFocus
      onCloseRequested: {
        if (root.coverExpanded) root.setCoverExpanded(false)
        else if (root.settingsOpen) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { if (!root.settingsOpen) root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0 && !root.settingsOpen) root.selectPage(root.page + dx) }
      onTextKey: function(t) {
        if (root.settingsOpen) return
        var shortcut = root.normalizeShortcutKey(t)
        if (shortcut === "1") root.selectPage(0)
        else if (shortcut === "2") root.selectPage(1)
        else if (shortcut === "3" || shortcut === "/") root.selectPage(2)
        else if (shortcut === "c" && !root.authenticated
            && String(root.data.authCode || "") !== "") root.copyAuthCode()
        else root.runPlayerShortcut(shortcut)
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.coverExpanded && contentHeight > height
          && (root.settingsOpen || root.page !== 2)
        ScrollBar.vertical: ScrollBar {
          policy: root.coverExpanded || (!root.settingsOpen && root.page === 2)
            ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
          topPadding: root.settingsOpen ? Style.space(34) : 0
          bottomPadding: Style.space(4)
        }

        Column {
          id: content
          // Never derive layout width from contentHeight: switching pages or
          // animating the cover may toggle the scrollbar and create a feedback loop.
          property real stableGutter: Style.space(14)
          readonly property real regularCoverBodyHeight: Style.space(68)
            + authenticatedContent.implicitHeight
          readonly property real expandedCoverBodyHeight: width
            + expandedPlayer.implicitHeight
          readonly property real regularCoverHeightBalance: Math.max(0,
            expandedCoverBodyHeight - regularCoverBodyHeight)
          readonly property real expandedCoverHeightBalance: Math.max(0,
            regularCoverBodyHeight - expandedCoverBodyHeight)
          x: stableGutter / 2
          width: panelScroll.width - stableGutter
          spacing: Style.space(12)

          Row {
            id: hero
            visible: !root.settingsOpen
            width: parent.width
            height: root.coverExpanded ? width : Style.space(68)
            spacing: root.coverExpanded ? 0 : Style.space(14)
            Behavior on height {
              NumberAnimation {
                duration: root.coverTransitionDuration
                easing.type: Easing.OutCubic
              }
            }
            Behavior on spacing {
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            BorderSurface {
              id: coverSurface
              width: root.coverExpanded ? hero.width : Style.space(68)
              height: hero.height
              radius: root.coverExpanded ? Style.cornerRadius : Style.spacing.labelGap
              clip: true
              Behavior on width {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
              }
              Behavior on radius {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
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
              MouseArea {
                id: coverMouse
                anchors.fill: parent
                enabled: root.hasTrack
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.setCoverExpanded(!root.coverExpanded)
              }
              ToolTip {
                id: coverTooltip
                readonly property var tooltipBorderSpec: Border.localOrSurfaceSpec(
                  "tooltip", "border", Color.tooltip.border, Color.tooltip.border,
                  Math.max(1, Style.normalBorderWidth))
                visible: coverMouse.containsMouse && root.hasTrack
                text: root.coverExpanded ? "Свернуть обложку (F)" : "Развернуть обложку (F)"
                delay: 400
                padding: 0
                background: BorderSurface {
                  color: Color.tooltip.background
                  borderSpec: coverTooltip.tooltipBorderSpec
                  radius: 0
                }
                contentItem: Text {
                  textFormat: Text.PlainText
                  text: coverTooltip.text
                  color: Color.tooltip.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  leftPadding: Border.left(coverTooltip.tooltipBorderSpec)
                    + Style.spacing.controlPaddingX
                  rightPadding: Border.right(coverTooltip.tooltipBorderSpec)
                    + Style.spacing.controlPaddingX
                  topPadding: Border.top(coverTooltip.tooltipBorderSpec)
                    + Style.spacing.controlPaddingY
                  bottomPadding: Border.bottom(coverTooltip.tooltipBorderSpec)
                    + Style.spacing.controlPaddingY
                }
              }
              Rectangle {
                visible: coverMouse.containsMouse && root.hasTrack
                anchors.top: parent.top; anchors.right: parent.right
                anchors.margins: root.coverExpanded ? Style.space(10) : Style.space(5)
                width: root.coverExpanded ? Style.space(32) : Style.space(22)
                height: width; radius: width / 2
                color: Qt.rgba(0, 0, 0, .58)
                Text {
                  anchors.centerIn: parent
                  text: root.coverExpanded ? "↙" : "↗"
                  color: "white"; font.pixelSize: root.coverExpanded
                    ? Style.font.subtitle : Style.font.bodySmall
                }
              }
            }

            Column {
              id: heroDetails
              width: Math.max(0, hero.width - coverSurface.width - hero.spacing)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              opacity: root.coverExpanded ? 0 : 1
              clip: true
              enabled: !root.coverExpanded
              Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Text {
                width: parent.width
                rightPadding: (root.authenticated ? Style.space(32) : 0)
                  + (root.busy ? Style.space(28) : 0)
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

          Column {
            id: expandedPlayer
            width: parent.width
            height: root.coverExpanded
              ? implicitHeight + content.expandedCoverHeightBalance : 0
            opacity: root.coverExpanded ? 1 : 0
            spacing: Style.space(9)
            clip: true
            enabled: root.coverExpanded
            Behavior on height {
              NumberAnimation {
                duration: root.coverTransitionDuration
                easing.type: Easing.OutCubic
              }
            }
            Behavior on opacity {
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: String(root.data.title || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: String(root.data.artist || "")
                + (root.data.album ? "  ·  " + String(root.data.album) : "")
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
            }
            Item {
              width: parent.width - Style.space(12)
              height: Style.space(28)
              anchors.horizontalCenter: parent.horizontalCenter
              Rectangle {
                id: expandedProgressTrack
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6); radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
                Rectangle {
                  width: parent.width * Math.min(1,
                    root.displayPosition / Math.max(1, Number(root.data.duration || 1)))
                  height: parent.height; radius: parent.radius; color: Color.accent
                }
                MouseArea {
                  id: expandedSeekDrag
                  anchors.fill: parent
                  anchors.topMargin: -Style.space(8); anchors.bottomMargin: -Style.space(8)
                  cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    root.seeking = true
                    root.previewSeek(mouse, expandedSeekDrag)
                  }
                  onPositionChanged: function(mouse) {
                    if (pressed) root.previewSeek(mouse, expandedSeekDrag)
                  }
                  onReleased: function(mouse) {
                    root.previewSeek(mouse, expandedSeekDrag)
                    root.commitSeek()
                  }
                  onCanceled: root.seeking = false
                }
              }
              Text {
                anchors.left: parent.left; anchors.top: expandedProgressTrack.bottom
                anchors.topMargin: Style.space(3)
                text: root.formatTime(root.playbackPosition)
                  + (root.seeking && root.pendingSeek >= 0
                    ? "  (" + root.formatTime(root.pendingSeek) + ")" : "")
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right; anchors.top: expandedProgressTrack.bottom
                anchors.topMargin: Style.space(3)
                text: root.formatTime(root.data.duration)
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(10)
              Button {
                width: Style.space(42); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.foreground
                onClicked: root.action("previous")
              }
              Button {
                width: Style.space(46); height: Style.space(40)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 24
                iconText: root.playing ? "󰏤" : "󰐊"
                tooltipText: root.playing ? "Пауза (Space)" : "Продолжить (Space)"
                foreground: root.foreground
                onClicked: root.action("pause")
              }
              Button {
                width: Style.space(42); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.foreground
                onClicked: root.action("next")
              }
              Button {
                width: Style.space(42); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                iconText: "󰐻"; tooltipText: "Радио по треку"; foreground: root.foreground
                onClicked: root.action("track_radio")
              }
              Button {
                width: Style.space(42); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 21
                iconText: root.data.liked ? "󰋑" : "󰋕"
                tooltipText: root.data.liked
                  ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
                foreground: root.data.liked ? Color.accent : root.foreground
                onClicked: root.action("like")
              }
              Button {
                width: Style.space(42); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                iconText: "󰅂"
                tooltipText: root.data.disliked
                  ? "Снять отметку «Не рекомендовать» (D)" : "Не рекомендовать (D)"
                foreground: root.data.disliked ? Color.urgent : root.foreground
                onClicked: root.action("dislike")
              }
            }
          }

          BorderSurface {
            id: errorCard
            visible: root.hasVisibleError && !root.coverExpanded
            width: parent.width
            height: visible ? errorContent.implicitHeight + Style.space(20) : 0
            radius: Style.cornerRadius
            color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .08)
            borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)

            Column {
              id: errorContent
              anchors.left: parent.left; anchors.right: parent.right
              anchors.margins: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Row {
                width: parent.width
                spacing: Style.space(5)
                Text {
                  width: parent.width - retryErrorButton.width - dismissErrorButton.width - Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.errorTitle
                  color: Color.urgent; font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall; font.bold: true
                }
                Button {
                  id: retryErrorButton
                  iconText: "󰑐"; iconSize: Style.font.icon
                  horizontalPadding: Style.space(5); verticalPadding: Style.space(3)
                  tooltipText: "Повторить"; foreground: Color.urgent
                  onClicked: root.retryLastOperation()
                }
                Button {
                  id: dismissErrorButton
                  iconText: "󰅖"; iconSize: Style.font.icon
                  horizontalPadding: Style.space(5); verticalPadding: Style.space(3)
                  tooltipText: "Скрыть"; foreground: root.dim
                  onClicked: root.dismissedError = root.lastError
                }
              }
              Text {
                width: parent.width
                text: root.lastError; wrapMode: Text.WordWrap
                color: root.foreground; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Column {
            visible: !root.authenticated; width: parent.width; spacing: Style.space(10)
            Row {
              visible: root.data.authPending === true && String(root.data.authCode || "") !== ""
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Код: " + root.data.authCode; color: root.foreground
                font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true
              }
              Button {
                width: Style.space(122); height: Style.space(32)
                anchors.verticalCenter: parent.verticalCenter
                text: root.copiedAuthCode === String(root.data.authCode || "") ? "Скопировано" : "Копировать"
                iconText: root.copiedAuthCode === String(root.data.authCode || "") ? "󰄬" : "󰆏"
                tooltipText: "Скопировать код авторизации"
                foreground: root.copiedAuthCode === String(root.data.authCode || "") ? Color.accent : root.foreground
                bordered: true
                onClicked: root.copyAuthCode()
              }
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
            id: authenticatedContent
            visible: root.authenticated
            width: parent.width
            // Keep the popup equally tall in both cover states without
            // distorting the square artwork or compacting player controls.
            // Any difference between the two natural layouts becomes
            // invisible space below this column.
            height: root.coverExpanded ? 0
              : implicitHeight + content.regularCoverHeightBalance
            opacity: root.coverExpanded ? 0 : 1
            spacing: Style.space(12)
            clip: true
            enabled: !root.coverExpanded
            // While both animated blocks have a non-zero height, Column adds
            // a second gap. Cancel it visually so removing the zero-height
            // expanded block cannot move the tabs at the final frame.
            transform: Translate {
              y: expandedPlayer.height > 0 && authenticatedContent.height > 0
                ? -content.spacing : 0
            }
            Behavior on height {
              enabled: root.coverTransitioning
              NumberAnimation {
                duration: root.coverTransitionDuration
                easing.type: Easing.OutCubic
              }
            }
            Behavior on opacity {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Row {
              visible: !root.settingsOpen
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
              visible: !root.settingsOpen && root.page === 0; width: parent.width; spacing: Style.space(14)

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
                  text: root.formatTime(root.playbackPosition)
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
                    iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.foreground
                    onClicked: root.action("previous")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                    iconText: root.playing ? "󰏤" : "󰐊"
                    tooltipText: root.playing ? "Пауза (Space)" : "Продолжить (Space)"
                    foreground: root.foreground; enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("pause")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 20
                    iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.foreground
                    onClicked: root.action("next")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 18
                    iconText: "󰐻"; tooltipText: "Радио по треку"; foreground: root.foreground
                    enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("track_radio")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 19
                    iconText: root.data.liked ? "󰋑" : "󰋕"
                    tooltipText: root.data.liked
                      ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
                    foreground: root.data.liked ? Color.accent : root.foreground
                    enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("like")
                  }
                  Button {
                    width: Style.space(34); height: Style.space(30)
                    horizontalPadding: 0; verticalPadding: 0; iconSize: 18
                    iconText: "󰅂"
                    tooltipText: root.data.disliked
                      ? "Снять отметку «Не рекомендовать» (D)" : "Не рекомендовать (D)"
                    foreground: root.data.disliked ? Color.urgent : root.foreground
                    enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.action("dislike")
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

              PanelSeparator {
                visible: root.hasTrack || root.queueListLoading || root.trackListDisplay.length > 0
                foreground: root.foreground
              }

              Item {
                visible: root.hasTrack || root.queueListLoading || root.trackListDisplay.length > 0
                width: parent.width
                height: visible ? Style.space(24) : 0
                clip: true

                Text {
                  id: queueHeading
                  visible: !root.queueListLoading || root.currentTrackPaneOpen
                  anchors.left: parent.left; anchors.right: lyricsToggleButton.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.trackInfoOpen ? "О ТРЕКЕ"
                    : (root.lyricsOpen ? "ТЕКСТ ПЕСНИ"
                    : (root.browsingArtist
                      ? "ТРЕКИ ИСПОЛНИТЕЛЯ · " + String(root.data.artistBrowseName || "")
                      : (root.browsingLibrary
                        ? "МЕДИАТЕКА · " + String(root.data.libraryBrowseName || "")
                        : "ОЧЕРЕДЬ" + (root.data.queueName ? " · " + root.data.queueName : ""))))
                  elide: Text.ElideRight
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.letterSpacing: 1
                }

                Button {
                  id: lyricsToggleButton
                  visible: root.hasTrack
                  anchors.right: trackInfoToggleButton.left; anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28); height: Style.space(24)
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: root.lyricsOpen ? "󰐑" : "󰨖"
                  iconSize: Style.font.icon
                  tooltipText: root.lyricsOpen ? "Вернуться к очереди" : "Открыть текст песни"
                  foreground: root.lyricsOpen ? Color.accent : root.dim
                  onClicked: root.setLyricsOpen(!root.lyricsOpen)
                }

                Button {
                  id: trackInfoToggleButton
                  visible: root.hasTrack
                  anchors.right: queueModeButton.left; anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28); height: Style.space(24)
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: root.trackInfoOpen ? "󰐑" : "󰋽"
                  iconSize: Style.font.icon
                  tooltipText: root.trackInfoOpen ? "Вернуться к очереди" : "Сведения и участники"
                  foreground: root.trackInfoOpen ? Color.accent : root.dim
                  onClicked: root.setTrackInfoOpen(!root.trackInfoOpen)
                }

                Button {
                  id: queueModeButton
                  visible: !root.queueListLoading && !root.currentTrackPaneOpen
                  anchors.right: queuePosition.left; anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.currentTrackPaneOpen ? 0 : Style.space(26); height: Style.space(24)
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: root.browsingCollection ? "󰁍" : root.playbackModeIcon
                  iconSize: Style.font.icon
                  tooltipText: root.browsingCollection ? "Вернуться к очереди"
                    : root.playbackModeLabel + " · нажмите для смены"
                  foreground: root.browsingCollection || root.playbackMode !== "order" ? Color.accent : root.dim
                  onClicked: {
                    if (root.browsingArtist) root.action("close_artist")
                    else if (root.browsingLibrary) root.action("close_library")
                    else root.action("mode")
                  }
                }

                Text {
                  id: queuePosition
                  visible: !root.queueListLoading || root.currentTrackPaneOpen
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.trackInfoOpen ? (root.trackInfoLoading ? "…" : "")
                    : (root.lyricsOpen
                      ? (root.lyricsLoading ? "…" : (root.lyricsData.synced ? "LRC"
                        : (root.lyricsData.available ? "TEXT" : "")))
                    : (root.browsingLibrary && Number(root.data.libraryTotal || 0) > root.trackListDisplay.length
                      ? root.trackListDisplay.length + "/" + Number(root.data.libraryTotal || 0)
                      : (root.browsingCollection ? String(root.trackListDisplay.length)
                      : (root.data.queueCount ? root.data.queueIndex + "/" + root.data.queueCount : ""))))
                  color: root.lyricsOpen && root.lyricsData.synced ? Color.accent : root.dim
                  font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }

                Rectangle {
                  visible: root.queueListLoading && !root.currentTrackPaneOpen
                  anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                  width: parent.width * .48; height: Style.space(7); radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
                }
                Rectangle {
                  visible: root.queueListLoading && !root.currentTrackPaneOpen
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(48); height: Style.space(7); radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .07)
                }
                Rectangle {
                  id: queueHeaderShimmer
                  visible: root.queueListLoading && !root.currentTrackPaneOpen
                  width: parent.width * .16; height: parent.height
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .045)
                  rotation: 8
                  NumberAnimation on x {
                    from: -queueHeaderShimmer.width
                    to: queueHeaderShimmer.parent.width + queueHeaderShimmer.width
                    duration: 1050; loops: Animation.Infinite
                    easing.type: Easing.InOutQuad
                    running: root.queueListLoading && !root.currentTrackPaneOpen
                  }
                }
              }

              SkeletonList {
                visible: !root.currentTrackPaneOpen && root.queueListLoading
                width: parent.width
                height: visible ? Style.space(260) : 0
                rowCount: 5
                foreground: root.foreground
              }

              ListView {
                id: queueList
                visible: !root.currentTrackPaneOpen && !root.queueListLoading
                  && root.trackListDisplay.length > 0
                width: parent.width
                height: visible ? Style.space(260) : 0
                clip: true
                model: root.trackListDisplay
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                cacheBuffer: height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                onContentYChanged: root.maybeLoadMoreLibrary()
                onMovementEnded: root.maybeLoadMoreLibrary()

                delegate: BorderSurface {
                  id: queueRow
                  required property var modelData
                  readonly property bool isCurrent: !root.browsingCollection
                    && Number(root.data.queueIndex || 0) - 1 === Number(modelData.index)
                  width: queueList.width - (queueList.contentHeight > queueList.height ? Style.space(8) : 0)
                  height: Style.space(50)
                  radius: Style.cornerRadius
                  color: isCurrent
                    ? Style.selectedFillFor(root.foreground, Color.accent)
                    : (queueMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  borderSpec: isCurrent
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
                      text: queueRow.isCurrent ? (root.playing ? "󰏤" : "󰐊") : String(modelData.index + 1)
                      color: queueRow.isCurrent ? Color.accent : root.dim
                      font.family: root.fontFamily; font.pixelSize: Style.font.caption
                    }
                    Column {
                      width: parent.width - Style.space(76); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                      Text {
                        width: parent.width; text: modelData.title; elide: Text.ElideRight
                        color: root.foreground; font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall; font.bold: queueRow.isCurrent
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
                    onClicked: {
                      if (root.browsingArtist) root.action("play_artist_track", modelData.index)
                      else if (root.browsingLibrary) root.action("play_library_track", modelData.index)
                      else if (!queueRow.isCurrent) root.action("play_queue", modelData.index)
                    }
                  }
                }

                footer: Item {
                  width: queueList.width
                  height: root.data.libraryLoadingMore === true ? Style.space(36) : 0
                  Text {
                    visible: root.data.libraryLoadingMore === true
                    anchors.centerIn: parent
                    text: "󰔟  Загружаем ещё 50…"
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
              }

              SkeletonList {
                visible: root.lyricsOpen && root.lyricsLoading
                width: parent.width
                height: visible ? Style.space(260) : 0
                rowCount: 5
                foreground: root.foreground
              }

              Item {
                visible: root.lyricsOpen && !root.lyricsLoading
                  && (!root.lyricsData.available || root.lyricsLines.length === 0)
                width: parent.width
                height: visible ? Style.space(260) : 0

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(32)
                  spacing: Style.space(10)
                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: String(root.lyricsData.error || "") !== ""
                      ? String(root.lyricsData.error) : "Текст этой песни недоступен"
                    color: String(root.lyricsData.error || "") !== "" ? Color.urgent : root.dim
                    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                  Button {
                    visible: String(root.lyricsData.error || "") !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Повторить"; iconText: "󰑐"; bordered: true
                    foreground: root.foreground
                    enabled: !lyricsProcess.running
                    onClicked: root.refreshLyrics(true)
                  }
                }
              }

              ListView {
                id: lyricsList
                visible: root.lyricsOpen && !root.lyricsLoading
                  && root.lyricsData.available && root.lyricsLines.length > 0
                width: parent.width
                height: visible ? Style.space(260) : 0
                clip: true
                model: root.lyricsLines
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                cacheBuffer: height
                spacing: Style.space(2)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                onMovementStarted: {
                  root.lyricsAutoScroll = false
                  lyricsResumeScrollTimer.stop()
                }
                onMovementEnded: lyricsResumeScrollTimer.restart()

                delegate: BorderSurface {
                  id: lyricRow
                  required property var modelData
                  required property int index
                  readonly property bool isCurrent: index === root.lyricsCurrentIndex
                  readonly property bool canSeek: root.lyricsData.synced && Number(modelData.time) >= 0
                  width: lyricsList.width
                    - (lyricsList.contentHeight > lyricsList.height ? Style.space(8) : 0)
                  height: String(modelData.text || "") === "" ? Style.space(18)
                    : Math.max(Style.space(38), lyricText.implicitHeight + Style.space(14))
                  radius: Style.cornerRadius
                  color: isCurrent
                    ? Style.selectedFillFor(root.foreground, Color.accent)
                    : (lyricMouse.containsMouse && canSeek
                      ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  borderSpec: isCurrent
                    ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none()

                  Text {
                    id: lyricText
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(lyricRow.modelData.text || "")
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: lyricRow.isCurrent ? Color.accent
                      : (root.lyricsData.synced ? root.dim : root.foreground)
                    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                    font.bold: lyricRow.isCurrent
                  }
                  MouseArea {
                    id: lyricMouse
                    anchors.fill: parent
                    enabled: lyricRow.canSeek
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.seekToLyric(lyricRow.modelData.time)
                  }
                }

                footer: Text {
                  width: lyricsList.width
                  height: visible ? implicitHeight + Style.space(20) : 0
                  visible: (root.lyricsData.writers || []).length > 0
                  topPadding: Style.space(10)
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: "Авторы текста: " + (root.lyricsData.writers || []).join(", ")
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              SkeletonList {
                visible: root.trackInfoOpen && root.trackInfoLoading
                width: parent.width
                height: visible ? Style.space(260) : 0
                rowCount: 5
                foreground: root.foreground
              }

              Item {
                visible: root.trackInfoOpen && !root.trackInfoLoading
                  && root.trackInfoRows.length === 0
                width: parent.width
                height: visible ? Style.space(260) : 0

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(32)
                  spacing: Style.space(10)
                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: String(root.trackInfoData.error || "") !== ""
                      ? String(root.trackInfoData.error) : "Подробные сведения недоступны"
                    color: String(root.trackInfoData.error || "") !== "" ? Color.urgent : root.dim
                    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                  Button {
                    visible: String(root.trackInfoData.error || "") !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Повторить"; iconText: "󰑐"; bordered: true
                    foreground: root.foreground
                    enabled: !trackInfoProcess.running
                    onClicked: root.refreshTrackInfo(true)
                  }
                }
              }

              ListView {
                id: trackInfoList
                visible: root.trackInfoOpen && !root.trackInfoLoading
                  && root.trackInfoRows.length > 0
                width: parent.width
                height: visible ? Style.space(260) : 0
                clip: true
                model: root.trackInfoRows
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                cacheBuffer: height
                spacing: Style.space(4)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: BorderSurface {
                  id: trackInfoRow
                  required property var modelData
                  readonly property bool isSection: String(modelData.kind || "") === "section"
                  width: trackInfoList.width
                    - (trackInfoList.contentHeight > trackInfoList.height ? Style.space(8) : 0)
                  height: isSection ? Style.space(28)
                    : Math.max(Style.space(44), trackInfoRowContent.implicitHeight + Style.space(14))
                  radius: Style.cornerRadius
                  color: isSection ? "transparent"
                    : Style.normalFillFor(root.foreground, Color.accent)
                  borderSpec: Border.none()

                  Column {
                    id: trackInfoRowContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: trackInfoRow.isSection ? 0 : Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text {
                      width: parent.width
                      text: String(trackInfoRow.modelData.label || "")
                      color: trackInfoRow.isSection ? root.dim : Color.accent
                      font.family: root.fontFamily; font.pixelSize: Style.font.caption
                      font.bold: trackInfoRow.isSection
                      font.letterSpacing: trackInfoRow.isSection ? .7 : 0
                    }
                    Text {
                      visible: !trackInfoRow.isSection
                      width: parent.width
                      text: String(trackInfoRow.modelData.value || "")
                      wrapMode: Text.WordWrap
                      color: root.foreground; font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }

                footer: Item {
                  width: trackInfoList.width
                  height: String(root.trackInfoData.error || "") !== ""
                    ? trackInfoErrorContent.implicitHeight + Style.space(20) : 0
                  Column {
                    id: trackInfoErrorContent
                    visible: String(root.trackInfoData.error || "") !== ""
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                      text: String(root.trackInfoData.error || "")
                      color: Color.urgent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Button {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Повторить"; iconText: "󰑐"; bordered: true
                      foreground: root.foreground
                      enabled: !trackInfoProcess.running
                      onClicked: root.refreshTrackInfo(true)
                    }
                  }
                }
              }
            }

            Column {
              visible: !root.settingsOpen && root.page === 1; width: parent.width; spacing: Style.space(6)
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
                Text {
                  anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
                  text: root.waveOptionsOpen ? "󰅃" : "󰅀"
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: waveMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.waveOptionsOpen = !root.waveOptionsOpen
                }
              }

              Column {
                visible: root.waveOptionsOpen
                width: parent.width
                spacing: Style.space(7)

                Dropdown {
                  x: Style.space(8); width: parent.width - Style.space(16)
                  label: "Настроение"
                  value: String(root.preference("waveMood", "all"))
                  foreground: root.foreground; fontFamily: root.fontFamily
                  options: [
                    { value: "all", label: "Любое" },
                    { value: "fun", label: "Весёлое" },
                    { value: "active", label: "Энергичное" },
                    { value: "calm", label: "Спокойное" },
                    { value: "sad", label: "Грустное" }
                  ]
                  onChanged: function(value) { root.setPreference("waveMood", value) }
                }
                Dropdown {
                  x: Style.space(8); width: parent.width - Style.space(16)
                  label: "Подбор треков"
                  value: String(root.preference("waveDiversity", "default"))
                  foreground: root.foreground; fontFamily: root.fontFamily
                  options: [
                    { value: "default", label: "Сбалансированный" },
                    { value: "favorite", label: "Больше любимого" },
                    { value: "popular", label: "Популярное" },
                    { value: "discover", label: "Больше нового" }
                  ]
                  onChanged: function(value) { root.setPreference("waveDiversity", value) }
                }
                Dropdown {
                  x: Style.space(8); width: parent.width - Style.space(16)
                  label: "Язык"
                  value: String(root.preference("waveLanguage", "any"))
                  foreground: root.foreground; fontFamily: root.fontFamily
                  options: [
                    { value: "any", label: "Любой" },
                    { value: "russian", label: "Русская музыка" },
                    { value: "not-russian", label: "Зарубежная музыка" }
                  ]
                  onChanged: function(value) { root.setPreference("waveLanguage", value) }
                }
                Button {
                  x: Style.space(8); width: parent.width - Style.space(16)
                  text: settingsProcess.running ? "Сохраняем настройки…" : "Запустить Мою волну"
                  iconText: "󰐊"; foreground: root.foreground; bordered: true
                  enabled: !settingsProcess.running; opacity: enabled ? 1 : .5
                  onClicked: {
                    root.action("wave")
                    root.waveOptionsOpen = false
                    root.selectPage(0)
                  }
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
              visible: !root.settingsOpen && root.page === 2; width: parent.width; spacing: Style.space(6)
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
              Item {
                id: searchResultsViewport
                width: parent.width
                height: Math.max(Style.space(240), Style.space(424)
                  - (root.hasVisibleError ? errorCard.height + Style.space(12) : 0))
                clip: true

                SkeletonList {
                  visible: root.searchListLoading
                  anchors.fill: parent
                  rowCount: 9
                  foreground: root.foreground
                }

                ListView {
                  id: searchResultsList
                  visible: !root.searchListLoading
                  anchors.fill: parent
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height
                  cacheBuffer: height
                  model: root.data.searchResults || []
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  delegate: BorderSurface {
                    required property var modelData
                    width: searchResultsList.width
                      - (searchResultsList.contentHeight > searchResultsList.height ? Style.space(8) : 0)
                    height: Style.space(48); radius: Style.cornerRadius
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
              Item {
                width: 1
                height: Style.space(8)
              }
            }

            Column {
              visible: root.settingsOpen
              width: parent.width
              spacing: Style.space(10)

              Item {
                width: parent.width
                height: Style.space(18)

                Text {
                  anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                  text: "НАСТРОЙКИ"
                  color: root.foreground; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
                }
                Text {
                  visible: String(root.data.version || "") !== ""
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  text: "v" + String(root.data.version || "")
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                text: "ВОСПРОИЗВЕДЕНИЕ"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .7
              }

              Toggle {
                width: parent.width
                label: "Продолжать после перезапуска"
                description: "Возобновлять игравший трек после запуска сервиса"
                checked: Boolean(root.preference("autoResume", true))
                foreground: root.foreground
                onClicked: root.setPreference("autoResume", !checked)
              }

              Text {
                text: "ВОССТАНОВЛЕНИЕ СЕССИИ"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .7
              }
              Toggle {
                width: parent.width; label: "Восстанавливать очередь"
                checked: Boolean(root.preference("restoreQueue", true)); foreground: root.foreground
                onClicked: root.setPreference("restoreQueue", !checked)
              }
              Toggle {
                width: parent.width; label: "Восстанавливать позицию трека"
                checked: Boolean(root.preference("restorePosition", true)); foreground: root.foreground
                onClicked: root.setPreference("restorePosition", !checked)
              }
              Toggle {
                width: parent.width; label: "Восстанавливать громкость"
                checked: Boolean(root.preference("restoreVolume", true)); foreground: root.foreground
                onClicked: root.setPreference("restoreVolume", !checked)
              }

              Dropdown {
                width: parent.width
                label: "Качество аудио"
                value: String(root.preference("audioQuality", "best"))
                foreground: root.foreground; fontFamily: root.fontFamily
                options: [
                  { value: "best", label: "Лучшее доступное" },
                  { value: "economy", label: "Экономия трафика" }
                ]
                onChanged: function(nextValue) { root.setPreference("audioQuality", nextValue) }
              }

              Text {
                text: "ВЕРХНИЙ БАР"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .7
              }

              Toggle {
                width: parent.width; label: "Показывать кнопки управления"
                checked: Boolean(root.preference("showControls", true)); foreground: root.foreground
                onClicked: root.setPreference("showControls", !checked)
              }
              Toggle {
                width: parent.width; label: "Показывать исполнителя"
                checked: Boolean(root.preference("showArtist", true)); foreground: root.foreground
                onClicked: root.setPreference("showArtist", !checked)
              }
              Toggle {
                width: parent.width; label: "Показывать название трека"
                checked: Boolean(root.preference("showTitle", true)); foreground: root.foreground
                onClicked: root.setPreference("showTitle", !checked)
              }

              Toggle {
                width: parent.width
                label: "Показывать обложку"
                checked: Boolean(root.preference("showCover", true))
                foreground: root.foreground
                onClicked: root.setPreference("showCover", !checked)
              }

              Dropdown {
                width: parent.width
                label: "Форма обложки"
                value: String(root.preference("coverShape", "rounded"))
                foreground: root.foreground; fontFamily: root.fontFamily
                options: [
                  { value: "square", label: "Квадратная" },
                  { value: "rounded", label: "Скруглённая" },
                  { value: "circle", label: "Круглая" }
                ]
                onChanged: function(value) { root.setPreference("coverShape", value) }
              }

              Toggle {
                width: parent.width
                label: "Показывать линию прогресса"
                checked: Boolean(root.preference("showProgress", true))
                foreground: root.foreground
                onClicked: root.setPreference("showProgress", !checked)
              }

              Dropdown {
                width: parent.width
                label: "Длинные названия"
                value: String(root.preference("longTitleMode", "truncate"))
                foreground: root.foreground; fontFamily: root.fontFamily
                options: [
                  { value: "truncate", label: "Обрезать многоточием" },
                  { value: "scroll", label: "Плавно прокручивать" }
                ]
                onChanged: function(value) { root.setPreference("longTitleMode", value) }
              }

              Dropdown {
                width: parent.width
                label: "Ширина информации о треке"
                value: String(root.preference("barWidth", "normal"))
                foreground: root.foreground; fontFamily: root.fontFamily
                options: [
                  { value: "compact", label: "Компактная" },
                  { value: "normal", label: "Обычная" },
                  { value: "wide", label: "Широкая" }
                ]
                onChanged: function(nextValue) { root.setPreference("barWidth", nextValue) }
              }

              Dropdown {
                width: parent.width
                label: "Уведомления при смене трека"
                value: String(root.preference("notifications", "off"))
                foreground: root.foreground; fontFamily: root.fontFamily
                options: [
                  { value: "off", label: "Выключены" },
                  { value: "all", label: "Показывать всегда" }
                ]
                onChanged: function(value) { root.setPreference("notifications", value) }
              }

              Text {
                text: "АККАУНТ"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .7
              }

              BorderSurface {
                width: parent.width
                height: accountContent.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Style.normalFillFor(root.foreground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                Column {
                  id: accountContent
                  anchors.left: parent.left; anchors.right: parent.right
                  anchors.margins: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)
                  Text {
                    width: parent.width
                    text: "Яндекс Музыка подключена"
                    color: root.foreground; font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall; font.bold: true
                  }
                  Text {
                    visible: root.confirmLogout
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Токен авторизации будет удалён. Для повторного входа понадобится браузер."
                    color: Color.urgent; font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Button {
                      width: root.confirmLogout
                        ? parent.width - cancelLogoutButton.width - parent.spacing : parent.width
                      text: root.confirmLogout ? "Подтвердить выход" : "Выйти из аккаунта"
                      foreground: Color.urgent; bordered: true
                      onClicked: {
                        if (root.confirmLogout) {
                          root.action("logout")
                          root.closeSettings()
                        } else root.confirmLogout = true
                      }
                    }
                    Button {
                      id: cancelLogoutButton
                      visible: root.confirmLogout
                      text: "Отмена"; foreground: root.foreground; bordered: true
                      onClicked: root.confirmLogout = false
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Item {
      id: settingsButton
      visible: root.authenticated && !root.coverExpanded
      z: 101
      anchors.top: parent.top; anchors.right: parent.right
      anchors.topMargin: Style.space(7); anchors.rightMargin: Style.space(7)
      width: Style.space(28); height: Style.space(28)

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: settingsButtonMouse.containsMouse || root.settingsOpen
          ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
      }
      Text {
        anchors.centerIn: parent
        text: root.settingsOpen ? "󰁍" : "󰒓"
        color: root.settingsOpen ? Color.accent : root.dim
        font.family: root.fontFamily; font.pixelSize: Style.font.icon
      }
      MouseArea {
        id: settingsButtonMouse
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
        onEntered: if (root.bar) root.bar.showTooltip(settingsButton,
          root.settingsOpen ? "Вернуться" : "Настройки")
        onExited: if (root.bar) root.bar.hideTooltip(settingsButton)
      }
    }

    Item {
      id: cornerLoader
      property real savedAngle: 0
      visible: root.busy
      z: 100
      anchors.top: parent.top; anchors.right: parent.right
      anchors.topMargin: Style.space(9); anchors.rightMargin: root.authenticated ? Style.space(40) : Style.space(10)
      width: Style.space(24); height: Style.space(24)

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(18); height: width; radius: width / 2
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .2)
      }

      Canvas {
        id: loaderArc
        anchors.centerIn: parent
        width: Style.space(18); height: width
        antialiasing: true
        rotation: cornerLoader.savedAngle
        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          context.beginPath()
          context.arc(width / 2, height / 2, width / 2 - Style.space(1.5),
            -Math.PI / 2, Math.PI * .85, false)
          context.lineWidth = Style.space(2)
          context.lineCap = "round"
          context.strokeStyle = Color.accent
          context.stroke()
        }
      }

      Timer {
        interval: 16
        repeat: true
        running: root.busy
        onTriggered: cornerLoader.savedAngle = (cornerLoader.savedAngle + 7.2) % 360
      }

      MouseArea {
        id: cornerLoaderMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onEntered: root.checkNetwork()
      }

      PanelToolTip {
        visible: cornerLoaderMouse.containsMouse
        text: root.loaderTooltip
        fontFamily: root.fontFamily
      }
    }
  }
}
