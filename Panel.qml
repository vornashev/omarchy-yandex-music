import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DetailsReconciler.js" as DetailsReconciler
import "ActionIntents.js" as ActionIntents

Panel {
  id: root
  moduleName: "vornashev.yandex-music"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var session: null
  readonly property int page: navController.page
  readonly property var navigation: navController
  readonly property var activeRoute: navController.top
  readonly property bool atRoot: navController.breadcrumbs.length === 1
  readonly property bool nowRoot: page === 0 && atRoot
  readonly property bool catalogRoute: ["search", "artist", "album", "playlist"].indexOf(activeRoute.kind) >= 0
  readonly property bool collectionRoute: activeRoute.kind === "collection"
  readonly property bool libraryRoute: activeRoute.kind === "libraryHome" || activeRoute.kind === "librarySection"
  property bool routeReady: true
  property bool navigationExpanded: false
  property int navigationGeneration: 0
  property bool routeViewportPending: false
  property var routeSnapshots: ({})
  property var browseDisplay: ({ libraryTracks: [], libraryLoading: false })
  property bool settingsOpen: false
  property bool confirmLogout: false
  property bool playerActionsOpen: false
  property bool lyricsOpen: false
  property bool lyricsAutoScroll: true
  property var lyricsData: ({ trackId: "", loading: false, available: false,
    synced: false, format: "", writers: [], lines: [], error: "" })
  property bool trackInfoOpen: false
  property var trackInfoData: ({ trackId: "", loading: false, available: false,
    credits: [], error: "" })
  readonly property string popupLayout: {
    var value = String(preference("popupLayout", "compact"))
    return value === "wide" || value === "mini" ? value : "compact"
  }
  readonly property bool layoutWide: authenticated && !authDone && popupLayout === "wide"
    && (panel.availableCardWidth <= 0 || panel.availableCardWidth >= Style.space(1040))
  readonly property bool layoutMini: authenticated && !authDone && popupLayout === "mini" && !settingsOpen
    && !collectionController.opened && !navigationExpanded
  property bool authDone: false
  property bool authFlowActive: false
  property string lastAuthCode: ""
  readonly property bool showAuth: !authenticated || authDone
  readonly property bool settingsBusy: settingsProcess.running
  readonly property bool lyricsRefreshing: lyricsProcess.running
  readonly property bool trackInfoRefreshing: trackInfoProcess.running
  property string copiedAuthCode: ""
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-yandex-music"
  property var data: ({ authenticated: false, playlists: [], searchResults: [] })
  property var catalogDisplay: ({ view: "search", revision: 0,
    search: { fieldText: "", query: "", filter: "all", loading: false,
      loadingMore: false, error: "", sections: {
        tracks: { items: [], total: 0, hasMore: false },
        artists: { items: [], total: 0, hasMore: false },
        albums: { items: [], total: 0, hasMore: false },
        playlists: { items: [], total: 0, hasMore: false } } },
    suggestions: { query: "", generation: 0, loading: false, items: [], error: "" },
    entity: {} })
  property bool catalogInitialized: false
  property var libraryHubDisplay: ({ view: "home", section: "", loading: false,
    error: "", warning: "", items: [], revision: 0 })
  property var collectionDisplay: ({ busy: false, operation: "", error: "", message: "",
    playlistKind: "", playlistTitle: "", recommendations: [], revision: 0 })
  property bool collectionResumePending: false
  property var pendingSuggestionCommand: []
  property string lastError: ""
  property string dismissedError: ""
  property string errorSource: ""
  property string lastActionCommand: ""
  property var lastActionArgument: undefined
  property bool refreshing: false
  property bool hasLoadedStatus: false
  property int detailsVolumeRevision: 0
  property int detailsActionRevision: 0
  property bool detailsStartedAfterVolume: true
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
  readonly property int activeQueueIndex: Number(data.queueIndex || 0) - 1
  readonly property var activeQueueRow: activeQueueIndex >= 0
      && activeQueueIndex < queueDisplay.length
    ? queueDisplay[activeQueueIndex] : null
  readonly property bool activeQueueTargetValid: activeQueueRow !== null
    && String(activeQueueRow.trackId || "") === currentTrackId
  readonly property var libraryDisplay: browseDisplay.libraryTracks || []
  readonly property string playbackMode: String(preference("playbackMode", "repeatQueue"))
  readonly property string playbackModeIcon: playbackMode === "shuffle" ? "󰒟"
    : (playbackMode === "repeatTrack" ? "󰑘" : (playbackMode === "repeatQueue" ? "󰑖" : "󰐕"))
  readonly property string playbackModeLabel: playbackMode === "shuffle" ? "Перемешивание"
    : (playbackMode === "repeatTrack" ? "Повтор трека"
    : (playbackMode === "repeatQueue" ? "Повтор очереди" : "По порядку"))
  readonly property bool busy: !routeReady || data.connecting === true || data.restoring === true
    || data.loading === true || data.libraryLoadingMore === true
    || libraryController.loading || libraryController.loadingMore
    || collectionController.busy || (session && session.actionRunning) || settingsProcess.running
    || (refreshing && !hasLoadedStatus)
  readonly property var networkInfo: data.network || ({})
  readonly property bool hasVisibleError: lastError !== "" && lastError !== dismissedError
  readonly property bool queueListLoading: data.loading === true
    && ["likes", "playlist", "personal", "wave", "radio", "station"].indexOf(String(data.loadingKind || "")) >= 0
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
    if (kind === "station") return "Запускаем радиостанцию…"
    if (kind === "likes") return "Загружаем любимые треки…"
    if (kind === "playlist") return "Загружаем плейлист…"
    if (kind === "personal") return "Загружаем персональную подборку…"
    if (kind === "search") return "Ищем треки…"
    if (kind === "artist") return "Загружаем треки исполнителя…"
    if (kind === "track" && String(data.loadingStage || "") === "downloadInfo")
      return "Получаем временную ссылку на трек…"
    if (kind === "track" && String(data.loadingStage || "") === "audioStream")
      return "Подключаем аудиопоток к mpv…"
    if (kind === "track") return "Подготавливаем трек…"
    if (settingsProcess.running) return "Сохраняем настройки…"
    if (collectionController.busy) {
      var operation = String(collectionDisplay.operation || "")
      if (operation === "create") return "Создаём приватный плейлист…"
      if (operation === "delete") return "Удаляем трек из плейлиста…"
      if (operation === "recommendations") return "Подбираем рекомендации…"
      return "Обновляем плейлист…"
    }
    if (session && session.actionRunning && session.lastCommand === "like") return "Обновляем отметку «Мне нравится»…"
    if (session && session.actionRunning && session.lastCommand === "dislike") return "Обновляем отметку «Не рекомендовать»…"
    if (session && session.actionRunning) return "Выполняем действие…"
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
  function startAuth() {
    authDone = false
    dismissedError = ""
    intent("authenticate")
  }
  function cancelAuth() { intent("cancelAuthentication") }
  function openAuthPage() {
    var url = String(data.authUrl || "")
    if (url !== "") Quickshell.execDetached(["xdg-open", url])
  }
  function finishAuth(startWave) {
    authDone = false
    authFlowActive = false
    if (startWave) {
      navIntent("startWave")
      selectPage(0)
    } else selectPage(1)
  }
  onAuthenticatedChanged: if (authenticated && authFlowActive) {
    authDone = true
    authFlowActive = false
  }
  onDataChanged: {
    if (data.authPending === true) authFlowActive = true
    var code = String(data.authCode || "")
    if (code !== "") lastAuthCode = code
  }
  function setPopupLayout(value) {
    var next = value === "wide" || value === "mini" ? value : "compact"
    if (next === popupLayout && preference("popupLayout", "compact") === next) return
    if (next === "mini") navigationExpanded = false
    playerActionsOpen = false
    setPreference("popupLayout", next)
  }
  function toggleLayout() {
    if (!authenticated || authDone) return
    setPopupLayout(popupLayout === "wide" ? "compact" : "wide")
  }
  function openRailShortcut(command, argument) {
    rememberRoute()
    navigationExpanded = true
    navController.openFromRail(command, argument,
      command === "playlist" ? playlistTitle(argument) : sectionTitle(command))
  }
  function playlistTitle(kind) {
    var rows = data.playlists || []
    for (var i = 0; i < rows.length; i++)
      if (String(rows[i].kind) === String(kind)) return String(rows[i].title || "Плейлист")
    return "Плейлист"
  }
  function sectionTitle(section) {
    var names = { wave: "Моя волна", likes: "Мне нравится", history: "Недавно слушали",
      personal: "Персональные плейлисты", albums: "Альбомы", artists: "Исполнители",
      playlists: "Плейлисты", stations: "Станции" }
    return names[section] || "Медиатека"
  }
  function pauseLyricsAutoScroll() {
    lyricsAutoScroll = false
    lyricsResumeScrollTimer.stop()
  }
  function resumeLyricsAutoScrollLater() { lyricsResumeScrollTimer.restart() }
  function openSettings() {
    playerActionsOpen = false
    confirmLogout = false
    settingsOpen = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function closeSettings() {
    settingsOpen = false
    confirmLogout = false
    activateRoute(page, activeRoute)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function openCollectionTrack(source, index, row, canDelete, playlistKind, playlistTitle, anchor) {
    playerActionsOpen = false
    collectionController.openTrack(source, index, row, canDelete, playlistKind, playlistTitle)
    collectionPopup.open(anchor)
  }
  function openPlayerActions() {
    if (!authenticated) return
    playerActionsOpen = true
    Qt.callLater(function() {
      if (!root.playerActionsOpen) return
      if (root.hasTrack) playerActionsFirstButton.forceActiveFocus()
      else playerActionsSettingsButton.forceActiveFocus()
    })
  }
  function closePlayerActions(restoreFocus) {
    if (!playerActionsOpen) return
    playerActionsOpen = false
    if (restoreFocus !== false)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function openCurrentTrackCollection() {
    if (!hasTrack || !activeQueueTargetValid) return
    var row = activeQueueRow
    var index = activeQueueIndex
    closePlayerActions(false)
    openCollectionTrack("queue", index, row, false, "", "")
  }
  function runPlayerMenuAction(command) {
    closePlayerActions(false)
    if (command === "settings") openSettings()
    else if (command === "recommendations") {
      if (collectionController.openRecommendations(
          String(browseDisplay.libraryPlaylistKind || ""), String(browseDisplay.libraryBrowseName || "")))
        collectionPopup.open()
    } else if (command === "queue") {
      rememberRoute()
      navController.selectTab(0)
      navController.popToRoot()
    }
    else if (command === "dislike") transport("dislikeTrack")
    else if (command === "track_radio") intent("startTrackRadio")
    else if (command === "mode") intent("cyclePlaybackMode")
  }
  function selectCurrentTrackPane(index) {
    if (index === 1) setLyricsOpen(true)
    else if (index === 2) setTrackInfoOpen(true)
    else {
      setLyricsOpen(false)
      setTrackInfoOpen(false)
      queueScrollTimer.restart()
    }
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
        || lyricsCurrentIndex < 0 || lyricsCurrentIndex >= trackPane.lyricsList.count) return
    trackPane.lyricsList.positionViewAtIndex(lyricsCurrentIndex, ListView.Center)
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
    var albumTitle = String(trackInfoData.album || "").trim()
    if (albumTitle !== "") rows.push({ kind: "detail", label: "Альбом",
      value: albumTitle, entityType: "album", entityId: String(trackInfoData.albumId || "") })
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
        if (root.trackInfoOpen) trackPane.resetInfoScroll()
      })
    } catch (e) {
      var failed = emptyTrackInfo(currentTrackId, false)
      failed.error = "Музыкальный сервис вернул некорректные сведения о треке"
      trackInfoData = failed
    }
  }
  function refresh() {
    if (!opened || statusProcess.running) return
    detailsActionRevision = session ? session.actionRevision : 0
    if (session) {
      detailsVolumeRevision = session.volumeRevision
      detailsStartedAfterVolume = !session.volumePending
    }
    refreshing = true; statusProcess.command = [cli, "details"]; statusProcess.running = true
  }
  function normalizeShortcutKey(value) {
    var t = String(value || "").toLowerCase()
    var qwertyFromRussian = {
      "т": "n", "з": "p", "д": "l", "в": "d", "ц": "w", "с": "c"
    }
    return qwertyFromRussian[t] || t
  }
  function runPlayerShortcut(value) {
    var t = normalizeShortcutKey(value)
    if (t === "w") {
      toggleLayout()
      return true
    }
    if (!hasTrack) return false
    if (t === " ") transport("togglePlayback")
    else if (t === "l") transport("toggleLike")
    else if (t === "d") transport("dislikeTrack")
    else if (t === "n") transport("nextTrack")
    else if (t === "p") transport("previousTrack")
    else return false
    return true
  }
  function pushRoute(route) {
    rememberRoute()
    navigationExpanded = true
    navController.push(route)
  }
  function openCatalogArtist(artistId, title) {
    if (artistId) pushRoute({ kind: "artist", args: { id: String(artistId) },
      title: typeof title === "string" ? title : "Исполнитель", scrollY: 0 })
  }
  function openCatalogAlbum(albumId, title) {
    if (albumId) pushRoute({ kind: "album", args: { id: String(albumId) },
      title: typeof title === "string" ? title : "Альбом", scrollY: 0 })
  }
  function openCatalogPlaylist(row) {
    var value = row || {}
    pushRoute({ kind: "playlist", args: { uuid: String(value.uuid || ""),
      owner: String(value.owner || ""), kind: String(value.kind || "") },
      title: String(value.title || "Плейлист"), scrollY: 0 })
  }
  function openLibraryCollection(command, argument, title) {
    pushRoute({ kind: "collection", args: { command: command, argument: String(argument || "") },
      title: String(title || (command === "likes" ? "Мне нравится" : playlistTitle(argument))), scrollY: 0 })
  }
  function routeKey(route) {
    var value = route || {}
    var args = value.args || {}
    return value.kind + ":" + (args.id || args.uuid
      || (value.kind === "playlist" ? String(args.owner || "") + ":" + String(args.kind || "")
      : value.kind === "collection" ? String(args.command || "") + ":" + String(args.argument || "")
      : String(args.section || "")))
  }
  function rememberRoute() {
    var y = nowRoot ? trackPane.queueList.contentY
      : collectionRoute ? collectionPage.scrollY
      : catalogRoute ? catalogPage.viewportY : libraryPage.viewportY
    navController.saveScroll(y)
    var copy = Object.assign({}, routeSnapshots)
    copy[routeKey(activeRoute)] = { catalog: catalogDisplay, hub: libraryHubDisplay, browse: browseDisplay }
    routeSnapshots = copy
  }
  function popRoute(depth) {
    if (atRoot) return false
    rememberRoute()
    if (depth === undefined) navController.pop()
    else navController.popTo(depth)
    return true
  }
  function escapeNavigation() {
    if (collectionController.opened) collectionPopup.close()
    else if (playerActionsOpen) closePlayerActions()
    else if (settingsOpen) closeSettings()
    else if (!popRoute()) close()
  }
  function focusRoute() {
    catalogPage.clearSearchFocus()
    libraryPage.clearStationFocus()
    keyCatcher.forceActiveFocus()
    if (page === 2 && atRoot)
      Qt.callLater(function() {
        if (root.page === 2 && root.atRoot && !root.settingsOpen) catalogPage.focusSearch()
      })
  }
  function restoreRouteViewport(generation) {
    Qt.callLater(function() {
      if (generation !== root.navigationGeneration) return
      var y = Number(root.activeRoute.scrollY || 0)
      if (root.nowRoot) trackPane.queueList.contentY = y
      else if (root.collectionRoute) collectionPage.preserveViewport(y)
      else if (root.catalogRoute) catalogPage.preserveViewport(y)
      else libraryPage.preserveViewport(y)
    })
  }
  function activateRoute(index, route) {
    navigationGeneration += 1
    // Now already has its queue model; a later details reply must not undo manual scrolling.
    routeViewportPending = route.kind !== "now"
    pendingNav = null
    settingsOpen = false
    playerActionsOpen = false
    confirmLogout = false
    routeReady = route.kind === "now" || (route.kind === "librarySection" && route.args.section === "wave")
    libraryPage.waveOptionsOpen = route.kind === "librarySection" && route.args.section === "wave"
    if (!nowRoot) {
      setLyricsOpen(false)
      setTrackInfoOpen(false)
    }
    var keep = {}
    for (var p = 0; p < navController.stacks.length; p++)
      for (var r = 0; r < navController.stacks[p].length; r++) {
        var key = routeKey(navController.stacks[p][r])
        if (routeSnapshots[key]) keep[key] = routeSnapshots[key]
      }
    routeSnapshots = keep
    var cached = routeSnapshots[routeKey(route)]
    if (catalogRoute) {
      var search = (cached ? cached.catalog : catalogDisplay).search
      catalogDisplay = cached ? cached.catalog : { view: route.kind, search: search,
        suggestions: {}, entity: { type: route.kind, loading: route.kind !== "search", tracks: [] } }
      catalogController.view = route.kind
    } else if (libraryRoute) {
      libraryHubDisplay = cached ? cached.hub : { view: route.kind === "libraryHome" ? "home" : "section",
        section: String(route.args.section || ""), items: [], loading: !routeReady, revision: 0 }
      libraryController.applySnapshot(libraryHubDisplay)
    } else if (collectionRoute) {
      browseDisplay = cached ? cached.browse : { libraryTracks: [], libraryLoading: true,
        libraryBrowseName: route.title, libraryBrowseKind: route.args.command, libraryBrowseArg: route.args.argument }
    }
    var args = route.args || {}
    if (route.kind === "artist" || route.kind === "album" || route.kind === "playlist")
      catalogController.openEntity(route.kind, args.id, args.uuid, args.owner, args.kind)
    else if (route.kind === "search") navIntent("returnCatalogSearch")
    else if (route.kind === "libraryHome") navIntent("loadLibraryHome")
    else if (route.kind === "librarySection" && args.section !== "wave") navIntent("openLibrarySection", args.section)
    else if (route.kind === "collection") {
      if (args.command === "likes") navIntent("openLikes")
      else if (args.command === "playlist") navIntent("openOwnedPlaylist", args.argument)
      else if (args.command === "browse_queue_source") navIntent("openQueueSourceCollection")
      else navIntent("openPersonalPlaylist", args.argument)
    }
    focusRoute()
    restoreRouteViewport(navigationGeneration)
    if (opened) settleTimer.restart()
  }
  function openQueueSource() {
    var kind = String(data.queueSourceKind || "")
    var argument = String(data.queueSourceArg || "")
    var title = String(data.queueSourceName || data.queueName || "")
    rememberRoute()
    navigationExpanded = true
    if (kind === "likes" || kind === "playlist") navController.openFromRail(kind, argument, title)
    else {
      navController.selectTab(1)
      navController.popToRoot()
      if (kind === "browse_personal") openLibraryCollection(kind, argument, title)
      else if (kind === "search") openLibraryCollection("browse_queue_source", "", title)
      else if (kind === "artist") openCatalogArtist(argument, title)
      else if (kind === "album") openCatalogAlbum(argument, title)
      else if (kind === "catalog_playlist") openCatalogPlaylist(JSON.parse(argument || "{}"))
      else if (kind === "libraryHub") pushRoute({ kind: "librarySection", args: { section: argument },
        title: sectionTitle(argument), scrollY: 0 })
      else if (kind === "wave" || kind === "station") pushRoute({ kind: "librarySection",
        args: { section: kind === "wave" ? "wave" : "stations" }, title: title || sectionTitle(kind), scrollY: 0 })
    }
  }
  function routeMatches(parsed) {
    var args = activeRoute.args || {}
    if (collectionRoute) return String(parsed.libraryBrowseKind || "") === String(args.command || "")
      && String(parsed.libraryBrowseArg || "") === String(args.argument || "")
    if (libraryRoute) {
      if (args.section === "wave") return true
      var hub = parsed.libraryHub || {}
      return activeRoute.kind === "libraryHome" ? hub.view === "home"
        : hub.view === "section" && String(hub.section || "") === args.section
    }
    if (catalogRoute) {
      var catalog = parsed.catalog || {}
      if (activeRoute.kind === "search") return catalog.view === "search"
      var entity = catalog.entity || {}
      return catalog.view === activeRoute.kind && String(entity.id || "") ===
        String(args.id || args.uuid || (String(args.owner || "") + ":" + String(args.kind || "")))
    }
    return true
  }
  function refreshRoute() {
    if (collectionRoute) activateRoute(page, activeRoute)
    else if (activeRoute.kind === "librarySection") intent("retryLibrarySection", activeRoute.args.section)
    else if (catalogRoute && !atRoot) activateRoute(page, activeRoute)
    else libraryController.requestHome(true)
  }
  NavController {
    id: navController
    onRouteActivated: function(index, route) { root.activateRoute(index, route) }
  }
  function startSuggestionRequest() {
    if (suggestionProcess.running || pendingSuggestionCommand.length === 0) return
    suggestionProcess.command = pendingSuggestionCommand
    pendingSuggestionCommand = []
    suggestionProcess.running = true
  }
  function requestSuggestions(query, generation) {
    pendingSuggestionCommand = [cli, "catalog_suggest", String(generation), String(query)]
    startSuggestionRequest()
  }
  function action(command, argument) {
    var policy = ActionIntents.policyForCommand(command)
    if (!policy || !session || !session.action(command, argument)) return false
    lastActionCommand = command
    lastActionArgument = argument
    dismissedError = ""
    errorSource = ""
    // Состояние просмотра принадлежит маршруту, не оптимистическому ответу другого экрана.
    var optimistic = ActionIntents.optimisticData(policy, data)
    if (optimistic) data = optimistic
    if (policy.resetCatalogScroll) catalogPage.scrollToBeginning()
    return true
  }
  // User navigation must not be lost while another command is still running
  // (single-flight session): keep the latest request and replay it afterwards.
  property var pendingNav: null
  function navIntent(name, payload) {
    if (intent(name, payload)) {
      pendingNav = null
      return true
    }
    pendingNav = { name: name, payload: payload }
    return false
  }
  function replayPendingNav() {
    if (!pendingNav) return
    var next = pendingNav
    pendingNav = null
    navIntent(next.name, next.payload)
  }
  function intent(name, payload) {
    var request = ActionIntents.resolve(name, payload)
    return request ? action(request.command, request.argument) : false
  }
  function transport(intent, payload) {
    if (!routeReady && ["playLibraryTrack", "playLibraryCollection", "playLibraryHubTrack",
        "playCatalogTrack"].indexOf(intent) >= 0) return false
    if (!session || !session.transport(intent, payload)) return false
    lastActionCommand = session.lastCommand
    lastActionArgument = session.lastArgument
    dismissedError = ""
    errorSource = ""
    return true
  }
  function retryLastOperation() {
    dismissedError = ""
    lastError = ""
    // Session restore errors leave authenticated=false with no last action.
    // A plain status refresh would return the same sticky error, so trigger
    // an explicit backend reconnect instead.
    if (!authenticated && data.authPending !== true) {
      intent("reconnect")
      return
    }
    if (errorSource === "status" || lastActionCommand === "") refresh()
    else action(lastActionCommand, lastActionArgument)
  }
  function queueVolume(value) {
    if (!session || !session.queueVolume(value)) return
    var copy = {}
    for (var key in data) copy[key] = data[key]
    copy.volume = session.pendingVolume
    copy.muted = false
    data = copy
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
      var matches = routeMatches(parsed)
      if (!matches) {
        parsed.catalog = catalogDisplay
        parsed.catalogRevision = Number(data.catalogRevision || 0)
        parsed.libraryHub = libraryHubDisplay
        parsed.libraryHubRevision = Number(data.libraryHubRevision || 0)
        parsed.libraryTracks = libraryDisplay
        parsed.libraryRevision = Number(data.libraryRevision || 0)
      }
      var result = DetailsReconciler.reconcile(parsed, {
        data: data, queueDisplay: queueDisplay,
        libraryHubDisplay: libraryHubDisplay, collectionDisplay: collectionDisplay,
        catalogDisplay: catalogDisplay,
        catalogInitialized: catalogInitialized, previousQueueIndex: previousQueueIndex,
        nowRoot: nowRoot
      }, {
        queueY: trackPane.queueList ? trackPane.queueList.contentY : 0,
        libraryY: libraryPage ? libraryPage.viewportY : 0,
        catalogY: catalogPage ? catalogPage.viewportY : 0
      }, detailsActionRevision, session ? session.actionRevision : 0)
      if (result.ignored) {
        if (opened && (!session || !session.actionRunning)) settleTimer.restart()
        return
      }
      if (matches) {
        routeReady = true
        if (collectionRoute) {
          var browse = {}
          for (var field in result.data)
            if (field.indexOf("library") === 0 && field !== "libraryHub") browse[field] = result.data[field]
          browseDisplay = browse
        }
      }
      if (result.changed.queue) queueDisplay = result.queueDisplay
      if (result.changed.libraryHub) {
        libraryHubDisplay = result.libraryHubDisplay
        libraryController.applySnapshot(result.libraryHubDisplay)
        var libraryTargetY = routeViewportPending ? Number(activeRoute.scrollY || 0) : libraryPage.viewportY
        var libraryGeneration = navigationGeneration
        Qt.callLater(function() {
          if (root.navigationGeneration === libraryGeneration && root.libraryRoute)
            libraryPage.preserveViewport(libraryTargetY)
        })
      }
      if (result.changed.collection) {
        collectionDisplay = result.collectionDisplay
        collectionController.applySnapshot(result.collectionDisplay)
      }
      if (result.changed.catalog) {
        catalogDisplay = result.catalogDisplay
        if (result.initializeCatalog) {
          catalogInitialized = true
          catalogController.filter = String((result.catalogDisplay.search || {}).filter || "all")
          catalogController.fieldText = String((result.catalogDisplay.search || {}).fieldText || "")
          catalogPage.setSearchText(catalogController.fieldText)
        }
        catalogController.applySuggestions(result.catalogDisplay.suggestions || {})
        var catalogTargetY = routeViewportPending ? Number(activeRoute.scrollY || 0)
          : result.intents.catalogViewport === "reset" && activeRoute.kind === "search" ? 0 : catalogPage.viewportY
        var catalogGeneration = navigationGeneration
        Qt.callLater(function() {
          if (root.navigationGeneration === catalogGeneration && root.catalogRoute)
            catalogPage.preserveViewport(catalogTargetY)
        })
        if (catalogRoute && !atRoot) {
          var entityTitle = String((catalogDisplay.entity || {}).name || (catalogDisplay.entity || {}).title || "")
          if (entityTitle !== "") navController.setTitle(entityTitle)
        }
      }
      if (matches && routeViewportPending) {
        focusRoute()
        restoreRouteViewport(navigationGeneration)
        routeViewportPending = false
      }
      var nextData = result.data
      if (session && session.pendingVolume >= 0 && (nowPane.volumeControl.pressed
          || compactPlayer.volumeControl.pressed
          || session.shouldPreserveVolume(detailsVolumeRevision, detailsStartedAfterVolume))) {
        nextData.volume = session.pendingVolume
        nextData.muted = false
      }
      data = nextData
      positionClockMs = Date.now()
      hasLoadedStatus = true
      var nextError = String(nextData.error || "")
      if (nextError !== lastError) dismissedError = ""
      lastError = nextError
      errorSource = lastError === "" ? "" : "backend"
      previousQueueIndex = result.previousQueueIndex
      if (result.intents.queueCurrent) queueScrollTimer.restart()
      if (result.intents.queueViewport === "reset")
        Qt.callLater(function() { if (trackPane.queueList) trackPane.queueList.contentY = 0 })
      else if (result.intents.queueViewport === "preserve") {
        var queueTargetY = result.intents.queueTargetY
        Qt.callLater(function() {
          if (trackPane.queueList) trackPane.queueList.contentY = Math.min(queueTargetY,
            Math.max(0, trackPane.queueList.contentHeight - trackPane.queueList.height))
        })
      }
    } catch (e) {
      console.warn("Yandex Music status update failed:", String(e))
      errorSource = "status"
      lastError = "Музыкальный сервис вернул некорректный ответ"
    }
  }
  function scrollToCurrentTrack() {
    if (!opened || !nowRoot || !trackPane.queueList || !trackPane.queueList.visible
        || trackPane.queueList.moving || trackPane.queueList.ScrollBar.vertical.pressed) return
    var index = Number(data.queueIndex || 0) - 1
    if (index < 0 || index >= trackPane.queueList.count) return

    trackPane.queueList.positionViewAtIndex(index, ListView.Center)
  }
  function selectPage(index) {
    rememberRoute()
    navigationExpanded = true
    navController.selectTab(Math.max(0, Math.min(2, index)))
  }

  LibraryController {
    id: libraryController
    ownPlaylists: root.data.playlists || []
    onHomeRequested: function(force) { root.navIntent(force ? "retryLibraryHome" : "loadLibraryHome") }
    onSectionRequested: function(section) {
      root.pushRoute({ kind: "librarySection", args: { section: section },
        title: root.sectionTitle(section), scrollY: 0 })
    }
    onBackRequested: root.popRoute()
    onRetryRequested: function(section) { root.navIntent("retryLibrarySection", section) }
    onLoadMoreRequested: root.intent("loadMoreLibrarySection")
    onCollectionRequested: function(command, argument, title) {
      root.openLibraryCollection(command, argument, title)
    }
    onEntityRequested: function(type, id, uuid, owner, kind, title) {
      if (type === "artist") root.openCatalogArtist(id, title)
      else if (type === "album") root.openCatalogAlbum(id, title)
      else if (type === "playlist") root.openCatalogPlaylist(
        { uuid: uuid, owner: owner, kind: kind, title: title })
    }
    onTrackPlaybackRequested: function(index) {
      root.transport("playLibraryHubTrack", index)
    }
    onStationPlaybackRequested: function(station, title) {
      root.navIntent("playStation", [station, title])
    }
  }

  CollectionController {
    id: collectionController
    ownPlaylists: root.data.playlists || []
    onMembershipsRequested: function(source, index, trackId, albumId) {
      if (!root.intent("inspectPlaylistMembership", [source, index, trackId, albumId]))
        collectionController.membershipRequestFailed()
    }
    onAddRequested: function(kind, source, index, trackId, albumId) {
      if (!root.intent("addPlaylistTrack", [kind, source, index, trackId, albumId]))
        collectionController.requestPending = false
    }
    onCreateRequested: function(title, source, index, trackId, albumId) {
      if (!root.intent("createPlaylist", [source, index, trackId, albumId, title]))
        collectionController.requestPending = false
    }
    onDeleteRequested: function(kind, source, index, trackId, albumId) {
      if (!root.intent("deletePlaylistTrack", [kind, source, index, trackId, albumId]))
        collectionController.requestPending = false
    }
    onRecommendationsRequested: function(kind, title) {
      if (!root.intent("loadPlaylistRecommendations", [kind, title]))
        collectionController.requestPending = false
    }
    onClearRequested: {
      if (!collectionClearProcess.running) {
        collectionClearProcess.command = [root.cli, "collection_clear"]
        collectionClearProcess.running = true
      }
    }
  }

  CatalogController {
    id: catalogController
    onSuggestRequested: function(query, generation) { root.requestSuggestions(query, generation) }
    onSuggestionsClearRequested: function(fieldText) {
      root.pendingSuggestionCommand = [root.cli, "catalog_clear_suggestions", String(fieldText)]
      root.startSuggestionRequest()
    }
    onSearchRequested: function(query, filter) {
      navController.setRootTitle(2, query ? "Поиск «" + query + "»" : "Поиск")
      navController.saveScroll(0)
      root.navIntent("searchCatalog", [filter, query])
    }
    onEntityRequested: function(type, id, uuid, owner, kind) {
      if (type === "artist") root.navIntent("openCatalogArtist", id)
      else if (type === "album") root.navIntent("openCatalogAlbum", id)
      else if (type === "playlist") root.navIntent("openCatalogPlaylist", [uuid, owner, kind])
    }
    onBackRequested: root.popRoute()
    onLoadMoreRequested: root.intent("loadMoreCatalogSearch")
    onReleaseMoreRequested: function(section) { root.intent("loadMoreArtistRelease", section) }
    onTrackPlaybackRequested: function(source, index) {
      root.transport("playCatalogTrack", [source, index])
    }
    onRadioRequested: function(station, title) {
      root.navIntent("playStation", [station, title])
    }
  }

  onBusyChanged: if (busy) busySeconds = 0
  onHasTrackChanged: if (!hasTrack) {
    playerActionsOpen = false
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
      rememberRoute()
      navigationExpanded = false
      playerActionsOpen = false
      settingsOpen = false
      confirmLogout = false
      if (collectionPopup.opened) {
        collectionResumePending = collectionController.busy
        collectionPopup.close()
      }
    }
    if (opened && collectionResumePending) {
      collectionResumePending = false
      if (collectionController.opened) collectionPopup.open()
    }
  }

  Process {
    id: statusProcess; command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (DetailsReconciler.isStaleResponse(root.detailsActionRevision,
          root.session ? root.session.actionRevision : 0)) {
        if (root.opened && (!root.session || !root.session.actionRunning)) settleTimer.restart()
        return
      }
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
    id: collectionClearProcess; command: []
    onExited: settleTimer.restart()
  }
  Process {
    id: suggestionProcess; command: []
    onExited: {
      if (root.pendingSuggestionCommand.length > 0) root.startSuggestionRequest()
      else settleTimer.restart()
    }
  }
  Connections {
    target: root.session
    function onActionFinished(exitCode, stdoutText, stderrText) {
      if (!root.opened) return
      if (exitCode !== 0) {
        root.lastActionCommand = root.session.lastCommand
        root.lastActionArgument = root.session.lastArgument
        root.errorSource = "action"
        root.lastError = String(stderrText || stdoutText || "Не удалось выполнить действие")
      }
      var policy = ActionIntents.policyForCommand(root.session.lastCommand)
      if (!policy || policy.refresh === "settle") settleTimer.restart()
      Qt.callLater(root.replayPendingNav)
    }
    function onVolumeDrained() {
      if (root.opened) settleTimer.restart()
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
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }
  Timer {
    interval: 100
    running: root.opened && root.playing
    repeat: true
    onTriggered: root.positionClockMs = Date.now()
  }
  Timer { id: settleTimer; interval: 350; repeat: false; onTriggered: root.refresh() }
  Timer { id: collectionDismissTimer; interval: 250; repeat: false
    onTriggered: collectionPopup.dismissReady = true }
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


  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: 0
    contentWidth: panel.fittedContentWidth(root.layoutWide ? Style.space(1040)
      : (root.layoutMini ? Style.space(380) : Style.space(400)))
    contentHeight: root.layoutMini ? Style.space(101)
      : (root.showAuth ? panel.cappedContentHeight(authView.implicitHeight)
        : panel.cappedContentHeight(Style.space(640)))

    // PanelKeyCatcher reserves h/j/k/l for directional navigation before
    // onTextKey runs. Give player shortcuts the first chance, especially L.
    Item {
      id: shortcutInterceptor
      Keys.onPressed: function(event) {
        var back = event.key === Qt.Key_Backspace
          || (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier))
        if (event.key === Qt.Key_Escape) {
          root.escapeNavigation()
          event.accepted = true
          return
        }
        if (back && !root.settingsOpen && !root.playerActionsOpen && !collectionController.opened
            && !(catalogPage.searchActiveFocus && catalogController.fieldText.length > 0)) {
          if (root.popRoute()) event.accepted = true
          return
        }
        if (event.modifiers & ~Qt.KeypadModifier) return
        if (root.settingsOpen || root.playerActionsOpen || catalogPage.searchActiveFocus
            || libraryPage.stationSearchActiveFocus) return
        var t = event.text ? String(event.text).toLowerCase() : ""
        if (!t && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
          t = String.fromCharCode(event.key).toLowerCase()
        if (root.runPlayerShortcut(t)) event.accepted = true
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "keyCatcher"
      anchors.fill: parent
      Keys.forwardTo: [shortcutInterceptor]
      blocked: catalogPage.searchActiveFocus || libraryPage.stationSearchActiveFocus
        || root.playerActionsOpen
      onCloseRequested: {
        root.escapeNavigation()
      }
      onTabRequested: function(direction) {
        if (!root.settingsOpen && !root.playerActionsOpen) root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && !root.settingsOpen && !root.playerActionsOpen)
          root.selectPage(root.page + dx)
      }
      onReturnRequested: {
        if (root.showAuth) authView.press()
        else if (root.page === 1 && !root.settingsOpen && !root.playerActionsOpen
                 && !collectionController.opened && !libraryPage.settingsRunning && !libraryPage.waveLoading
                 && (libraryPage.waveOptionsOpen || libraryController.view === "home"))
          libraryPage.waveRequested()
      }
      onTextKey: function(t) {
        if (root.settingsOpen || root.playerActionsOpen) return
        var shortcut = root.normalizeShortcutKey(t)
        if (root.showAuth) {
          if (shortcut === "c" && authView.stage === "code" && authView.hasCode) root.copyAuthCode()
          else if (shortcut === "r" && authView.stage === "expired") root.startAuth()
          return
        }
        if (shortcut === "1") root.selectPage(0)
        else if (shortcut === "2") root.selectPage(1)
        else if (shortcut === "3" || shortcut === "/") root.selectPage(2)
        else root.runPlayerShortcut(shortcut)
      }

      Item {
        id: ui
        anchors.fill: parent
        readonly property bool wide: root.layoutWide
        readonly property bool mini: root.layoutMini
        readonly property bool compact: root.authenticated && !root.authDone && !wide && !mini
        readonly property real bannerBottom: wide
          ? (root.nowRoot && !root.settingsOpen ? Style.space(12) : wideMiniBar.height + Style.space(12))
          : (compactMini.visible ? compactMini.height + Style.space(10) : Style.space(10))

        // ── signed out / first sign-in ────────────────────────────────────
        AuthPage {
          id: authView
          visible: root.showAuth
          panel: root
          anchors.fill: parent
          z: 150
        }

        // ── wide ──────────────────────────────────────────────────────────
        RailPane {
          id: rail
          visible: ui.wide
          panel: root
          selectedShortcut: root.navigation.selectedShortcut
          width: Style.space(220)
          anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        }
        Item {
          id: wideMain
          visible: ui.wide
          anchors.left: rail.right; anchors.right: parent.right
          anchors.top: parent.top; anchors.bottom: parent.bottom

          Item {
            id: wideNowPage
            visible: !root.settingsOpen && root.nowRoot
            anchors.fill: parent
            NowPane {
              id: nowPane
              objectName: "nowPane"
              panel: root
              width: Style.space(380)
              anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            }
            Rectangle {
              anchors.left: nowPane.right; anchors.top: parent.top; anchors.bottom: parent.bottom
              width: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
            }
            Item {
              id: wideQueueSlot
              anchors.left: nowPane.right; anchors.leftMargin: 1
              anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
            }
          }
          Item {
            id: widePageArea
            visible: !wideNowPage.visible
            anchors.fill: parent
            anchors.bottomMargin: wideMiniBar.height
            Item { id: wideLibrarySlot; anchors.fill: parent; anchors.topMargin: root.atRoot ? 0 : Style.space(68); visible: !root.settingsOpen && root.libraryRoute }
            Item { id: wideCatalogSlot; anchors.fill: parent; anchors.topMargin: root.atRoot ? 0 : Style.space(68); visible: !root.settingsOpen && root.catalogRoute }
            Item { id: wideCollectionSlot; anchors.fill: parent; anchors.topMargin: Style.space(68); visible: !root.settingsOpen && root.collectionRoute }
            Item { id: wideSettingsSlot; anchors.fill: parent; visible: root.settingsOpen }
          }
          MiniBar {
            id: wideMiniBar
            objectName: "wideMiniBar"
            mode: "wide"; panel: root
            visible: root.hasTrack && !wideNowPage.visible
            height: visible ? implicitHeight : 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          }
        }

        // ── compact ───────────────────────────────────────────────────────
        Item {
          id: compactRoot
          visible: ui.compact
          anchors.fill: parent

          PageTabs {
            id: compactTabs
            visible: !root.settingsOpen
            height: visible ? implicitHeight : 0
            panel: root
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
          }
          Item {
            id: compactNowPage
            visible: !root.settingsOpen && root.nowRoot
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: compactTabs.bottom; anchors.bottom: parent.bottom
            CompactPlayer {
              id: compactPlayer
              objectName: "compactPlayer"
              panel: root
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
              height: implicitHeight
            }
            Rectangle {
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: compactPlayer.bottom
              height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
            }
            Item {
              id: compactTrackSlot
              anchors.left: parent.left; anchors.right: parent.right
              anchors.top: compactPlayer.bottom; anchors.bottom: parent.bottom
            }
          }
          Item {
            id: compactPageArea
            visible: !root.settingsOpen && !root.nowRoot
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: compactTabs.bottom; anchors.bottom: compactMini.visible ? compactMini.top : parent.bottom
            Item { id: compactLibrarySlot; anchors.fill: parent; anchors.topMargin: root.atRoot ? 0 : Style.space(36); visible: root.libraryRoute }
            Item { id: compactCatalogSlot; anchors.fill: parent; anchors.topMargin: root.atRoot ? 0 : Style.space(36); visible: root.catalogRoute }
            Item { id: compactCollectionSlot; anchors.fill: parent; anchors.topMargin: Style.space(36); visible: root.collectionRoute }
          }
          MiniBar {
            id: compactMini
            objectName: "compactMini"
            mode: "compact"; panel: root
            visible: root.hasTrack && !root.settingsOpen && !root.nowRoot
            height: visible ? implicitHeight : 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          }
          Item {
            id: compactSettingsSlot
            visible: root.settingsOpen
            anchors.fill: parent
          }
        }

        // ── mini ──────────────────────────────────────────────────────────
        MiniBar {
          id: miniPopup
          visible: ui.mini
          mode: "popup"; panel: root
          anchors.fill: parent
        }

        // ── shared pages (re-parented between wide and compact slots) ────
        NavHeader {
          id: navigationHeader
          objectName: "navigationHeader"
          parent: ui.wide ? widePageArea : compactPageArea
          wide: ui.wide
          visible: root.authenticated && !root.atRoot && !root.settingsOpen && !ui.mini
          x: ui.wide ? Style.space(28) : 0
          y: ui.wide ? Style.space(24) : 0
          width: parent.width - (ui.wide ? Style.space(56) : 0)
          height: ui.wide ? Style.space(26) : Style.space(36)
          breadcrumbs: root.navigation.breadcrumbs
          foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          contextIcon: root.activeRoute.kind === "librarySection" ? "refresh-cw" : "ellipsis"
          onBackRequested: root.popRoute()
          onDepthRequested: function(depth) { root.popRoute(depth) }
          onContextRequested: {
            if (root.collectionRoute && root.browseDisplay.libraryEditable === true) {
              if (collectionController.openRecommendations(String(root.browseDisplay.libraryPlaylistKind || ""),
                  String(root.browseDisplay.libraryBrowseName || ""))) collectionPopup.open()
            } else root.refreshRoute()
          }
        }
        CollectionPage {
          id: collectionPage
          objectName: "collectionPage"
          panel: root; wide: ui.wide
          visible: root.authenticated && root.collectionRoute && !root.settingsOpen && !ui.mini
          parent: ui.wide ? wideCollectionSlot : compactCollectionSlot
          anchors.fill: parent
          onArtistRequested: function(id, name) { root.openCatalogArtist(id, name) }
          onAlbumRequested: function(id, title) { root.openCatalogAlbum(id, title) }
          onCollectionTrackRequested: function(index, value, anchor) {
            root.openCollectionTrack("library", index, value, root.browseDisplay.libraryEditable === true,
              String(root.browseDisplay.libraryPlaylistKind || ""), String(root.browseDisplay.libraryBrowseName || ""), anchor)
          }
        }
        TrackPane {
          id: trackPane
          panel: root
          wide: ui.wide
          visible: root.authenticated && !root.settingsOpen && root.nowRoot && !ui.mini
          parent: ui.wide ? wideQueueSlot : compactTrackSlot
          anchors.fill: parent
        }
        LibraryPage {
          id: libraryPage
          objectName: "libraryPage"
          wide: ui.wide
          visible: root.authenticated && root.libraryRoute && !root.settingsOpen && !ui.mini
          enabled: root.routeReady
          parent: ui.wide ? wideLibrarySlot : compactLibrarySlot
          anchors.fill: parent
          controller: libraryController
          preferences: root.data.preferences || ({})
          waveActive: root.data.waveActive === true
          wavePlaying: root.data.playing === true
          waveLoading: root.data.loading === true && root.data.loadingKind === "wave"
          likesTotal: root.data.likesTotal === undefined ? -1 : Number(root.data.likesTotal)
          foreground: root.foreground
          dim: root.dim
          fontFamily: root.fontFamily
          panelOpened: root.opened
          settingsOpen: root.settingsOpen
          settingsRunning: settingsProcess.running
          focusTarget: keyCatcher
          onPreferenceRequested: function(key, value) { root.setPreference(key, value) }
          onWaveOptionsRequested: root.pushRoute({ kind: "librarySection",
            args: { section: "wave" }, title: "Моя волна", scrollY: 0 })
          onWavePlaybackRequested: root.transport("togglePlayback")
          onWaveRequested: {
            root.navIntent("startWave")
          }
          onCollectionTrackRequested: function(index, value, anchor) {
            root.openCollectionTrack("libraryHub", index, value, false, "", "", anchor)
          }
        }
        CatalogPage {
          id: catalogPage
          objectName: "catalogPage"
          wide: ui.wide
          visible: root.authenticated && root.catalogRoute && !root.settingsOpen && !ui.mini
          enabled: root.routeReady
          parent: ui.wide ? wideCatalogSlot : compactCatalogSlot
          anchors.fill: parent
          controller: catalogController
          snapshot: root.catalogDisplay
          foreground: root.foreground
          dim: root.dim
          fontFamily: root.fontFamily
          onEscapeRequested: root.escapeNavigation()
          hasVisibleError: root.hasVisibleError
          errorCardHeight: errorCard.height
          focusTarget: keyCatcher
          currentTrackId: root.currentTrackId
          onArtistRequested: function(id, name) { root.openCatalogArtist(id, name) }
          onAlbumRequested: function(id, title) { root.openCatalogAlbum(id, title) }
          onPlaylistRequested: function(value) { root.openCatalogPlaylist(value) }
          onCollectionTrackRequested: function(source, index, value, anchor) {
            root.openCollectionTrack(source, index, value, false, "", "", anchor)
          }
          onEntityMoreRequested: root.intent("loadMoreCatalogEntity")
          onRetryEntityRequested: function(entity) {
            if (entity.type === "artist") root.navIntent("openCatalogArtist", entity.id)
            else if (entity.type === "album") root.navIntent("openCatalogAlbum", entity.id)
            else if (entity.type === "playlist")
              root.navIntent("openCatalogPlaylist", [entity.uuid, entity.owner, entity.kind])
          }
        }
        SettingsPage {
          id: settingsPage
          panel: root
          wide: ui.wide
          visible: root.authenticated && root.settingsOpen
          parent: ui.wide ? wideSettingsSlot : compactSettingsSlot
          anchors.fill: parent
        }

        // ── contextual error ─────────────────────────────────────────────
        BorderSurface {
          id: errorCard
          visible: root.hasVisibleError
          anchors.left: parent.left; anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: ui.wide ? rail.width + Style.space(12)
          + (root.nowRoot && !root.settingsOpen ? nowPane.width : 0) : Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.bottomMargin: ui.bannerBottom
          z: 60
          height: visible ? errorContent.implicitHeight + Style.space(20) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .14)
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
                textFormat: Text.PlainText
                width: parent.width - retryErrorButton.width - dismissErrorButton.width - Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.errorTitle
                color: Color.urgent; font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall; font.bold: true
              }
              IconButton {
                id: retryErrorButton
                iconText: "󰑐"; iconSize: Style.font.icon
                horizontalPadding: Style.space(5); verticalPadding: Style.space(3)
                tooltipText: "Повторить"; foreground: Color.urgent
                onClicked: root.retryLastOperation()
              }
              IconButton {
                id: dismissErrorButton
                iconText: "󰅖"; iconSize: Style.font.icon
                horizontalPadding: Style.space(5); verticalPadding: Style.space(3)
                tooltipText: "Скрыть"; foreground: root.dim
                onClicked: root.dismissedError = root.lastError
              }
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.lastError; wrapMode: Text.WordWrap
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    Item {
      anchors.fill: parent
      z: 190
      visible: root.playerActionsOpen
      enabled: visible

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, .5)
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.closePlayerActions()
      }

      Pane {
        id: playerActionsSheet
        x: Math.max(Style.space(10), (parent.width - width) / 2)
        y: Math.max(Style.space(10), (parent.height - height) / 2)
        width: Math.min(parent.width - Style.space(20), Style.space(380))
        height: playerActionsContent.implicitHeight + topPadding + bottomPadding
        padding: Style.space(10)
        focus: true
        Keys.onEscapePressed: root.closePlayerActions()
        background: BorderSurface {
          color: Color.background
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius
        }

        contentItem: Column {
          id: playerActionsContent
          spacing: Style.space(4)

          Item {
            visible: root.hasTrack
            width: parent.width; height: Style.space(52)
            CatalogImage {
              id: sheetCover
              anchors.left: parent.left; anchors.leftMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(40); height: width
              requestedSource: String(root.data.artUrl || "")
              foreground: root.foreground; fontFamily: root.fontFamily
              fillMode: Image.PreserveAspectCrop
            }
            Column {
              anchors.left: sheetCover.right; anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                width: parent.width; elide: Text.ElideRight
                text: String(root.data.title || "")
                color: root.foreground; font.family: root.fontFamily
                font.pixelSize: Style.font.body; font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width; elide: Text.ElideRight
                text: String(root.data.artist || "")
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: !root.hasTrack
            width: parent.width
            text: "ДЕЙСТВИЯ"
            color: root.dim; font.family: root.fontFamily
            font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .8
            bottomPadding: Style.space(4)
          }

          IconButton {
            id: playerActionsFirstButton
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰐒"; text: "Добавить в плейлист"
            foreground: root.foreground
            enabled: root.activeQueueTargetValid && !root.busy
            onClicked: root.openCurrentTrackCollection()
          }
          IconButton {
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰐻"; text: "Радио по треку"
            foreground: root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("track_radio")
          }
          IconButton {
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󱐴"
            text: root.data.disliked
              ? "Снять «Не рекомендовать»" : "Не рекомендовать"
            foreground: root.data.disliked ? Color.urgent : root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("dislike")
            BorderSurface {
              anchors.right: parent.right; anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20); height: Style.space(18)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "D"; color: root.dim
                font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
          }
          IconButton {
            visible: root.collectionRoute && root.browseDisplay.libraryEditable === true
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰎈"; text: "Подобрать рекомендации"
            foreground: root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("recommendations")
          }
          IconButton {
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: root.playbackModeIcon
            text: "Режим: " + root.playbackModeLabel
            foreground: root.playbackMode !== "order" ? Color.accent : root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("mode")
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          IconButton {
            id: playerActionsSettingsButton
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰒓"; text: "Настройки"
            foreground: root.foreground
            onClicked: root.runPlayerMenuAction("settings")
          }
        }
      }
    }

    Item {
      id: collectionOverlay
      anchors.fill: parent
      z: 200
      visible: collectionController.opened

      Rectangle {
        anchors.fill: parent
        color: "#99000000"
        visible: !root.layoutWide
      }
      MouseArea {
        anchors.fill: parent
        enabled: collectionPopup.dismissReady && !collectionController.busy
        onClicked: collectionPopup.close()
      }
      PlaylistSheet {
        id: collectionPopup
        controller: collectionController
        wide: root.layoutWide
        foreground: root.foreground
        dim: root.dim
        fontFamily: root.fontFamily
        readonly property bool opened: collectionController.opened
        property bool dismissReady: false
        property point anchorPoint: Qt.point(-1, -1)
        signal closed()
        function open(anchor) {
          anchorPoint = anchor ? anchor.mapToItem(collectionOverlay, anchor.width, anchor.height)
            : Qt.point(-1, -1)
          dismissReady = false
          collectionDismissTimer.restart()
          activate()
        }
        function close() {
          if (!opened || collectionController.busy) return
          dismissReady = false
          closed()
        }
        x: root.layoutWide ? Math.max(Style.space(16), Math.min(parent.width - width - Style.space(16),
          anchorPoint.x >= 0 ? anchorPoint.x - width : parent.width - width - Style.space(24))) : 0
        y: root.layoutWide ? Math.max(Style.space(16), Math.min(parent.height - height - Style.space(16),
          anchorPoint.y >= 0 ? anchorPoint.y + Style.space(4) : Style.space(155)))
          : Math.max(0, parent.height - height)
        width: root.layoutWide ? Style.space(340) : parent.width
        height: Math.min(parent.height - (root.layoutWide ? Style.space(32) : Style.space(40)),
          Style.space(root.layoutWide
            ? (collectionController.target.canDelete ? 512 : collectionController.mode === "create" ? 443 : 403)
            : (collectionController.target.canDelete ? 560 : 470)))
        onDismissed: close()
        onClosed: {
          if (!(root.collectionResumePending && collectionController.busy)) {
            root.collectionResumePending = false
            if (collectionController.opened) collectionController.close()
          }
          keyCatcher.forceActiveFocus()
        }
      }
    }

    Item {
      id: cornerLoader
      property real savedAngle: 0
      visible: root.busy
      z: 100
      anchors.top: parent.top; anchors.right: parent.right
      anchors.topMargin: Style.space(9); anchors.rightMargin: Style.space(10)
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
