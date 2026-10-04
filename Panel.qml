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
  property int page: 0
  property int pageBeforeSettings: 0
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
  property bool coverExpanded: false
  property bool coverTransitioning: false
  property int coverStablePanelHeight: 0
  readonly property int coverTransitionDuration: 280
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
  property int catalogReturnPage: 2
  property real catalogSearchContentY: 0
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
  readonly property var libraryDisplay: data.libraryTracks || []
  readonly property bool browsingLibrary: String(data.libraryBrowseName || "") !== ""
  readonly property bool browsingCollection: browsingLibrary
  readonly property var trackListDisplay: browsingLibrary ? libraryDisplay : queueDisplay
  readonly property string playbackMode: String(preference("playbackMode", "repeatQueue"))
  readonly property string playbackModeIcon: playbackMode === "shuffle" ? "󰒟"
    : (playbackMode === "repeatTrack" ? "󰑘" : (playbackMode === "repeatQueue" ? "󰑖" : "󰐕"))
  readonly property string playbackModeLabel: playbackMode === "shuffle" ? "Перемешивание"
    : (playbackMode === "repeatTrack" ? "Повтор трека"
    : (playbackMode === "repeatQueue" ? "Повтор очереди" : "По порядку"))
  readonly property bool busy: data.connecting === true || data.restoring === true
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
  function setCoverExpanded(value) {
    var next = value === true && authenticated && hasTrack && !settingsOpen
    if (coverExpanded === next) return
    if (next) {
      playerActionsOpen = false
      coverStablePanelHeight = panel.contentHeight
    }
    coverTransitioning = true
    coverTransitionTimer.restart()
    coverExpanded = next
    if (next) {
      lyricsOpen = false
      trackInfoOpen = false
      page = 0
      catalogPage.clearSearchFocus()
      libraryPage.clearStationFocus()
      panelScroll.contentY = 0
      keyCatcher.forceActiveFocus()
    }
  }
  function openSettings() {
    playerActionsOpen = false
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
  function openCollectionTrack(source, index, row, canDelete, playlistKind, playlistTitle) {
    playerActionsOpen = false
    collectionController.openTrack(source, index, row, canDelete, playlistKind, playlistTitle)
    collectionPopup.open()
  }
  function openPlayerActions() {
    if (!authenticated || coverTransitioning) return
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
          String(data.libraryPlaylistKind || ""), String(data.libraryBrowseName || "")))
        collectionPopup.open()
    } else if (command === "queue") intent("closeLibraryQueue")
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
        if (root.trackInfoOpen) trackInfoList.positionViewAtBeginning()
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
  function maybeLoadMoreLibrary() {
    if (!root.browsingLibrary || root.data.libraryHasMore !== true
        || root.data.libraryLoadingMore === true || (session && session.actionRunning)) return
    if (queueList.contentY + queueList.height >= queueList.contentHeight - Style.space(50))
      root.intent("loadMoreLibraryTracks")
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
    if (t === " ") transport("togglePlayback")
    else if (t === "l") transport("toggleLike")
    else if (t === "d") transport("dislikeTrack")
    else if (t === "n") transport("nextTrack")
    else if (t === "p") transport("previousTrack")
    else if (t === "f") setCoverExpanded(!coverExpanded)
    else return false
    return true
  }
  function prepareCatalogNavigation(returnPage) {
    if (Number(returnPage) === 1) catalogReturnPage = 1
    else if (String(catalogDisplay.view || "search") === "search") catalogReturnPage = 2
    selectPage(2)
  }
  function openCatalogArtist(artistId, returnPage) {
    if (!artistId) return
    prepareCatalogNavigation(returnPage)
    catalogPage.clearSearchFocus()
    keyCatcher.forceActiveFocus()
    catalogController.openEntity("artist", artistId, "", "", "")
  }
  function openCatalogAlbum(albumId, returnPage) {
    if (!albumId) return
    prepareCatalogNavigation(returnPage)
    catalogPage.clearSearchFocus()
    keyCatcher.forceActiveFocus()
    catalogController.openEntity("album", albumId, "", "", "")
  }
  function openCatalogPlaylist(row, returnPage) {
    var value = row || {}
    prepareCatalogNavigation(returnPage)
    catalogPage.clearSearchFocus()
    keyCatcher.forceActiveFocus()
    catalogController.openEntity("playlist", "", value.uuid, value.owner, value.kind)
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
    var librarySnapshot = ActionIntents.optimisticLibrary(
      policy, argument, libraryHubDisplay.revision || 0)
    if (librarySnapshot) libraryController.applySnapshot(librarySnapshot)
    var optimistic = ActionIntents.optimisticData(policy, data)
    if (optimistic) data = optimistic
    if (policy.resetCatalogScroll) catalogPage.scrollToBeginning()
    return true
  }
  function intent(name, payload) {
    var request = ActionIntents.resolve(name, payload)
    return request ? action(request.command, request.argument) : false
  }
  function transport(intent, payload) {
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
      var result = DetailsReconciler.reconcile(parsed, {
        data: data, queueDisplay: queueDisplay,
        libraryHubDisplay: libraryHubDisplay, collectionDisplay: collectionDisplay,
        catalogDisplay: catalogDisplay, catalogSearchContentY: catalogSearchContentY,
        catalogInitialized: catalogInitialized, previousQueueIndex: previousQueueIndex,
        page: page
      }, {
        queueY: queueList ? queueList.contentY : 0,
        libraryY: libraryPage ? libraryPage.viewportY : 0,
        catalogY: catalogPage ? catalogPage.viewportY : 0
      }, detailsActionRevision, session ? session.actionRevision : 0)
      if (result.ignored) {
        if (opened && (!session || !session.actionRunning)) settleTimer.restart()
        return
      }
      if (result.changed.queue) queueDisplay = result.queueDisplay
      if (result.changed.libraryHub) {
        libraryHubDisplay = result.libraryHubDisplay
        libraryController.applySnapshot(result.libraryHubDisplay)
        if (result.intents.libraryViewport === "reset") {
          Qt.callLater(function() { if (libraryPage) libraryPage.resetViewport() })
        } else if (result.intents.libraryViewport === "preserve") {
          var libraryTargetY = result.intents.libraryTargetY
          Qt.callLater(function() {
            if (libraryPage) libraryPage.preserveViewport(libraryTargetY)
          })
        }
      }
      if (result.changed.collection) {
        collectionDisplay = result.collectionDisplay
        collectionController.applySnapshot(result.collectionDisplay)
      }
      if (result.changed.catalog) {
        catalogSearchContentY = result.catalogSearchContentY
        catalogDisplay = result.catalogDisplay
        if (result.initializeCatalog) {
          catalogInitialized = true
          catalogController.filter = String((result.catalogDisplay.search || {}).filter || "all")
          catalogController.fieldText = String((result.catalogDisplay.search || {}).fieldText || "")
          catalogPage.setSearchText(catalogController.fieldText)
        }
        catalogController.applySuggestions(result.catalogDisplay.suggestions || {})
        if (result.intents.catalogViewport === "restoreSearch") {
          var searchTargetY = result.intents.catalogTargetY
          Qt.callLater(function() { if (catalogPage) catalogPage.restoreViewport(searchTargetY) })
        } else if (result.intents.catalogViewport === "reset") {
          Qt.callLater(function() { if (catalogPage) catalogPage.resetViewport() })
        } else if (result.intents.catalogViewport === "preserve") {
          var catalogTargetY = result.intents.catalogTargetY
          Qt.callLater(function() {
            if (catalogPage) catalogPage.preserveViewport(catalogTargetY)
          })
        }
      }
      var nextData = result.data
      if (session && session.pendingVolume >= 0 && (expandedVolumeControl.pressed
          || regularVolumeControl.pressed
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
        Qt.callLater(function() { if (queueList) queueList.contentY = 0 })
      else if (result.intents.queueViewport === "preserve") {
        var queueTargetY = result.intents.queueTargetY
        Qt.callLater(function() {
          if (queueList) queueList.contentY = Math.min(queueTargetY,
            Math.max(0, queueList.contentHeight - queueList.height))
        })
      }
    } catch (e) {
      console.warn("Yandex Music status update failed:", String(e))
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
    playerActionsOpen = false
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
        catalogPage.focusSearch()
      })
    } else {
      // A hidden TextField keeps active focus unless it is transferred
      // explicitly, which would make it consume shortcuts from other pages.
      catalogPage.clearSearchFocus()
      libraryPage.clearStationFocus()
      keyCatcher.forceActiveFocus()
    }
  }

  LibraryController {
    id: libraryController
    ownPlaylists: root.data.playlists || []
    onSectionRequested: function(section) { root.intent("openLibrarySection", section) }
    onBackRequested: root.intent("returnLibraryHome")
    onRetryRequested: function(section) { root.intent("retryLibrarySection", section) }
    onLoadMoreRequested: root.intent("loadMoreLibrarySection")
    onCollectionRequested: function(command, argument) {
      if (command === "likes") root.intent("openLikes")
      else if (command === "playlist") root.intent("openOwnedPlaylist",
        argument === "" ? undefined : argument)
      else if (command === "browse_personal") root.intent("openPersonalPlaylist",
        argument === "" ? undefined : argument)
      root.selectPage(0)
    }
    onEntityRequested: function(type, id, uuid, owner, kind) {
      if (type === "artist") root.openCatalogArtist(id, 1)
      else if (type === "album") root.openCatalogAlbum(id, 1)
      else if (type === "playlist") root.openCatalogPlaylist(
        { uuid: uuid, owner: owner, kind: kind }, 1)
    }
    onTrackPlaybackRequested: function(index) {
      root.transport("playLibraryHubTrack", index)
      root.selectPage(0)
    }
    onStationPlaybackRequested: function(station, title) {
      root.intent("playStation", [station, title])
      root.selectPage(0)
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
      root.intent("searchCatalog", [filter, query])
    }
    onEntityRequested: function(type, id, uuid, owner, kind) {
      if (type === "artist") root.intent("openCatalogArtist", id)
      else if (type === "album") root.intent("openCatalogAlbum", id)
      else if (type === "playlist") root.intent("openCatalogPlaylist", [uuid, owner, kind])
    }
    onBackRequested: {
      root.intent("returnCatalogSearch")
      if (root.catalogReturnPage === 1) {
        root.catalogReturnPage = 2
        root.selectPage(1)
      }
    }
    onLoadMoreRequested: root.intent("loadMoreCatalogSearch")
    onReleaseMoreRequested: function(section) { root.intent("loadMoreArtistRelease", section) }
    onTrackPlaybackRequested: function(source, index) {
      root.transport("playCatalogTrack", [source, index])
    }
  }

  onCatalogDisplayChanged: if (page === 2) {
    if (String(catalogDisplay.view || "search") === "search")
      Qt.callLater(function() { if (root.page === 2) catalogPage.focusSearch() })
    else {
      catalogPage.clearSearchFocus()
      keyCatcher.forceActiveFocus()
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
        if (root.settingsOpen || root.playerActionsOpen || catalogPage.searchActiveFocus
            || libraryPage.stationSearchActiveFocus || !root.hasTrack) return
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
      blocked: catalogPage.searchActiveFocus || libraryPage.stationSearchActiveFocus
        || root.playerActionsOpen
      onCloseRequested: {
        if (root.playerActionsOpen) root.closePlayerActions()
        else if (root.coverExpanded) root.setCoverExpanded(false)
        else if (root.settingsOpen) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (!root.settingsOpen && !root.playerActionsOpen) root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && !root.settingsOpen && !root.playerActionsOpen)
          root.selectPage(root.page + dx)
      }
      onTextKey: function(t) {
        if (root.settingsOpen || root.playerActionsOpen) return
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
        interactive: !root.coverExpanded && !root.coverTransitioning && contentHeight > height
          && (root.settingsOpen || root.page !== 2)
        ScrollBar.vertical: ScrollBar {
          policy: root.coverExpanded || root.coverTransitioning || (!root.settingsOpen && root.page === 2)
            ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
          topPadding: root.settingsOpen ? Style.space(34) : 0
          bottomPadding: Style.space(4)
        }

        Column {
          id: content
          // Never derive layout width from contentHeight: switching pages or
          // animating the cover may toggle the scrollbar and create a feedback loop.
          property real stableGutter: Style.space(14)
          // fittedContentHeight includes the card's padding and border. Use a
          // screen-capped budget, not this Column's height, to avoid a size loop.
          readonly property real viewportBudget: Math.max(0,
            panel.fittedContentHeight(Style.space(620), Style.space(620))
              - panel.verticalContentInset)
          readonly property real regularErrorHeight: root.hasVisibleError
            ? errorContent.implicitHeight + Style.space(20) + spacing : 0
          readonly property real expandedViewportBudget: Math.min(viewportBudget,
            root.coverStablePanelHeight > 0 && (root.coverExpanded || root.coverTransitioning)
              ? root.coverStablePanelHeight - panel.verticalContentInset : viewportBudget)
          readonly property real expandedCoverSize: Math.min(width, Math.max(1,
            expandedViewportBudget - expandedPlayer.implicitHeight - spacing))
          readonly property real regularCoverBodyHeight: Style.space(68)
            + authenticatedContent.implicitHeight + regularErrorHeight
          readonly property real expandedCoverBodyHeight: expandedCoverSize
            + expandedPlayer.implicitHeight
          readonly property real regularCoverHeightBalance: root.settingsOpen ? 0 : Math.max(0,
            Math.min(expandedCoverBodyHeight - regularCoverBodyHeight,
              viewportBudget - spacing - regularCoverBodyHeight))
          readonly property real expandedCoverHeightBalance: Math.max(0,
            Math.min(regularCoverBodyHeight - expandedCoverBodyHeight,
              expandedViewportBudget - spacing - expandedCoverBodyHeight))
          x: stableGutter / 2
          width: panelScroll.width - stableGutter
          spacing: Style.space(12)

          Row {
            id: hero
            visible: !root.settingsOpen
            width: parent.width
            height: root.coverExpanded ? content.expandedCoverSize : Style.space(68)
            spacing: root.coverExpanded ? 0 : Style.space(14)
            leftPadding: root.coverExpanded ? (width - content.expandedCoverSize) / 2 : 0
            Behavior on leftPadding {
              NumberAnimation {
                duration: root.coverTransitionDuration
                easing.type: Easing.OutCubic
              }
            }
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
              width: root.coverExpanded ? content.expandedCoverSize : Style.space(68)
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
                textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                textFormat: Text.PlainText
                width: parent.width
                rightPadding: root.busy ? Style.space(28) : 0
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
                      textFormat: Text.PlainText
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
                        onClicked: root.openCatalogArtist(heroArtistLink.modelData.id)
                      }
                    }
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                id: heroAlbumLink
                width: parent.width
                text: root.hasTrack
                  ? String(root.data.album || root.data.queueName || "")
                  : (root.authenticated ? "Выберите музыку" : "Автономный плеер")
                color: heroAlbumMouse.containsMouse && String(root.data.albumId || "") !== ""
                  ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption; elide: Text.ElideRight
                MouseArea {
                  id: heroAlbumMouse; anchors.fill: parent
                  enabled: String(root.data.albumId || "") !== ""
                  hoverEnabled: enabled
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.openCatalogAlbum(root.data.albumId)
                }
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
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: String(root.data.title || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 0
              Repeater {
                model: root.data.artists || []
                Text {
                  textFormat: Text.PlainText
                  id: expandedArtistLink
                  required property var modelData
                  required property int index
                  text: modelData.name + (index < (root.data.artists || []).length - 1 ? ", " : "")
                  color: expandedArtistMouse.containsMouse ? Color.accent : root.dim
                  font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    id: expandedArtistMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openCatalogArtist(expandedArtistLink.modelData.id)
                  }
                }
              }
              Text {
                textFormat: Text.PlainText
                id: expandedAlbumLink
                visible: String(root.data.album || "") !== ""
                text: (root.data.artists || []).length > 0
                  ? "  ·  " + String(root.data.album) : String(root.data.album)
                color: expandedAlbumMouse.containsMouse && String(root.data.albumId || "") !== ""
                  ? Color.accent : root.dim
                font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                MouseArea {
                  id: expandedAlbumMouse; anchors.fill: parent
                  enabled: String(root.data.albumId || "") !== ""
                  hoverEnabled: enabled
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.openCatalogAlbum(root.data.albumId)
                }
              }
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
                textFormat: Text.PlainText
                anchors.left: parent.left; anchors.top: expandedProgressTrack.bottom
                anchors.topMargin: Style.space(3)
                text: root.formatTime(root.playbackPosition)
                  + (root.seeking && root.pendingSeek >= 0
                    ? "  (" + root.formatTime(root.pendingSeek) + ")" : "")
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right; anchors.top: expandedProgressTrack.bottom
                anchors.topMargin: Style.space(3)
                text: root.formatTime(root.data.duration)
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Item {
              width: parent.width
              height: Style.space(44)

              Button {
                id: expandedLikeButton
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: Style.space(40); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0
                iconSize: Style.space(20)
                iconText: root.data.liked ? "󰋑" : "󰋕"
                tooltipText: root.data.liked
                  ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
                foreground: root.data.liked ? Color.accent : root.foreground
                onClicked: root.transport("toggleLike")
              }
              Row {
                anchors.centerIn: parent
                spacing: Style.space(14)
                Button {
                  width: Style.space(42); height: Style.space(40)
                  horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                  iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.foreground
                  onClicked: root.transport("previousTrack")
                }
                Button {
                  width: Style.space(46); height: Style.space(44); radius: height / 2
                  horizontalPadding: 0; verticalPadding: 0; iconSize: 26
                  tooltipText: root.playing ? "Пауза (Space)" : "Продолжить (Space)"
                  foreground: Color.accent; bordered: true
                  onClicked: root.transport("togglePlayback")
                  Text {
                    textFormat: Text.PlainText
                    z: 2; anchors.centerIn: parent
                    anchors.horizontalCenterOffset: root.playing ? 0 : Style.space(2)
                    text: root.playing ? "󰏤" : "󰐊"
                    color: parent.foreground; font.family: root.fontFamily
                    font.pixelSize: parent.iconSize
                  }
                }
                Button {
                  width: Style.space(42); height: Style.space(40)
                  horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                  iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.foreground
                  onClicked: root.transport("nextTrack")
                }
              }
              Button {
                id: expandedMoreButton
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: Style.space(40); height: Style.space(38)
                horizontalPadding: 0; verticalPadding: 0
                iconText: "󰇙"; iconSize: Style.space(20)
                tooltipText: "Действия и настройки"
                foreground: root.foreground
                onClicked: root.openPlayerActions()
              }
            }

            VolumeControl {
              id: regularVolumeControl
              width: parent.width
              volume: Number(root.data.volume || 0)
              muted: root.data.muted === true
              foreground: root.foreground
              dim: root.dim
              fontFamily: root.fontFamily
              onMuteRequested: root.transport("toggleMute")
              onVolumeChangeRequested: function(value) { root.queueVolume(value) }
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
                  textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.data.authUrl ? "Открыть страницу авторизации" : "Войти через Яндекс"
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
              }
              MouseArea {
                id: authMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: if (root.data.authUrl) Quickshell.execDetached(["xdg-open", String(root.data.authUrl)]); else root.intent("authenticate")
              }
            }
          }

          Column {
            id: authenticatedContent
            visible: root.authenticated
            width: parent.width
            // Keep the popup equally tall in both cover states without
            // distorting the square artwork or compacting player controls.
            // Any difference that fits the viewport becomes invisible space
            // below this column; the inner panes absorb the remaining budget.
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
              id: navigationTabs
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
                    textFormat: Text.PlainText
                    anchors.centerIn: parent; text: modelData; color: root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.caption
                    font.bold: root.page === index; font.letterSpacing: .5
                  }
                  MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPage(index) }
                }
              }
            }

            Column {
              id: playerPage
              // Everything above the pane keeps its natural size, including
              // volume and contextual errors. Only the scrolling pane shrinks.
              // Keep a usable minimum on exceptionally short screens; the
              // outer Flickable remains a fallback rather than clipping controls.
              readonly property real paneHeight: Math.max(Style.space(80),
                Math.min(Style.space(260), content.viewportBudget
                  - Style.space(68) - content.spacing - content.regularErrorHeight
                  - navigationTabs.height - authenticatedContent.spacing
                  - trackPaneHeader.y - trackPaneHeader.height - spacing))
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
                  textFormat: Text.PlainText
                  anchors.left: parent.left; anchors.top: progressTrack.bottom; anchors.topMargin: Style.space(3)
                  text: root.formatTime(root.playbackPosition)
                    + (root.seeking && root.pendingSeek >= 0 ? "  (" + root.formatTime(root.pendingSeek) + ")" : "")
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right; anchors.top: progressTrack.bottom; anchors.topMargin: Style.space(3)
                  text: root.formatTime(root.data.duration); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }

              Column {
                id: playerControls
                width: parent.width
                spacing: Style.space(7)

                Item {
                  width: parent.width
                  height: Style.space(44)

                  Button {
                    id: likeButton
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40); height: Style.space(38)
                    horizontalPadding: 0; verticalPadding: 0
                    iconSize: Style.space(20)
                    iconText: root.data.liked ? "󰋑" : "󰋕"
                    tooltipText: root.data.liked
                      ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
                    foreground: root.data.liked ? Color.accent : root.foreground
                    enabled: root.hasTrack; opacity: enabled ? 1 : .4
                    onClicked: root.transport("toggleLike")
                  }
                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(14)
                    Button {
                      width: Style.space(42); height: Style.space(40)
                      horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                      iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.foreground
                      enabled: root.hasTrack; opacity: enabled ? 1 : .4
                      onClicked: root.transport("previousTrack")
                    }
                    Button {
                      width: Style.space(46); height: Style.space(44); radius: height / 2
                      horizontalPadding: 0; verticalPadding: 0; iconSize: 26
                      tooltipText: root.playing ? "Пауза (Space)" : "Продолжить (Space)"
                      foreground: Color.accent; bordered: true
                      enabled: root.hasTrack; opacity: enabled ? 1 : .4
                      onClicked: root.transport("togglePlayback")
                      Text {
                        textFormat: Text.PlainText
                        z: 2; anchors.centerIn: parent
                        anchors.horizontalCenterOffset: root.playing ? 0 : Style.space(2)
                        text: root.playing ? "󰏤" : "󰐊"
                        color: parent.foreground; font.family: root.fontFamily
                        font.pixelSize: parent.iconSize
                      }
                    }
                    Button {
                      width: Style.space(42); height: Style.space(40)
                      horizontalPadding: 0; verticalPadding: 0; iconSize: 22
                      iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.foreground
                      enabled: root.hasTrack; opacity: enabled ? 1 : .4
                      onClicked: root.transport("nextTrack")
                    }
                  }
                  Button {
                    id: moreActionsButton
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(40); height: Style.space(38)
                    horizontalPadding: 0; verticalPadding: 0
                    iconText: "󰇙"; iconSize: Style.space(20)
                    tooltipText: "Действия и настройки"
                    foreground: root.foreground
                    onClicked: root.openPlayerActions()
                  }
                }

                VolumeControl {
                  id: expandedVolumeControl
                  width: parent.width
                  volume: Number(root.data.volume || 0)
                  muted: root.data.muted === true
                  foreground: root.foreground
                  dim: root.dim
                  fontFamily: root.fontFamily
                  onMuteRequested: root.transport("toggleMute")
                  onVolumeChangeRequested: function(value) { root.queueVolume(value) }
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: !root.hasTrack && !root.browsingLibrary
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Выберите плейлист в медиатеке или найдите трек"
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
              }

              PanelSeparator {
                visible: root.hasTrack || root.browsingLibrary
                  || root.queueListLoading || root.trackListDisplay.length > 0
                foreground: root.foreground
              }

              Row {
                id: currentTrackPaneTabs
                visible: root.hasTrack
                width: parent.width
                height: visible ? Style.space(30) : 0
                spacing: Style.space(8)

                Repeater {
                  model: [
                    { label: "СПИСОК", pane: 0 },
                    { label: "ТЕКСТ", pane: 1 },
                    { label: "О ТРЕКЕ", pane: 2 }
                  ]
                  Item {
                    required property var modelData
                    readonly property bool selected: (modelData.pane === 0
                        && !root.currentTrackPaneOpen)
                      || (modelData.pane === 1 && root.lyricsOpen)
                      || (modelData.pane === 2 && root.trackInfoOpen)
                    width: (currentTrackPaneTabs.width - currentTrackPaneTabs.spacing * 2) / 3
                    height: currentTrackPaneTabs.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: modelData.label
                      color: parent.selected ? Color.accent : root.dim
                      font.family: root.fontFamily; font.pixelSize: Style.font.caption
                      font.bold: parent.selected; font.letterSpacing: .6
                    }
                    Rectangle {
                      anchors.left: parent.left; anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: Style.space(2); radius: height / 2
                      color: Color.accent
                      opacity: parent.selected ? 1 : 0
                      Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectCurrentTrackPane(modelData.pane)
                    }
                  }
                }
              }

              Item {
                id: trackPaneHeader
                visible: root.hasTrack || root.browsingLibrary
                  || root.queueListLoading || root.trackListDisplay.length > 0
                width: parent.width
                height: visible ? Style.space(24) : 0
                clip: true

                Button {
                  id: returnToQueueButton
                  visible: root.browsingCollection && !root.currentTrackPaneOpen
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Style.space(24) : 0
                  height: Style.space(24)
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: "󰁍"; iconSize: Style.font.icon
                  tooltipText: "Вернуться к очереди"
                  foreground: Color.accent
                  enabled: !root.busy
                  onClicked: root.intent("closeLibraryQueue")
                }

                Text {
                  textFormat: Text.PlainText
                  id: queueHeading
                  visible: !root.queueListLoading || root.currentTrackPaneOpen
                  anchors.left: returnToQueueButton.visible ? returnToQueueButton.right : parent.left
                  anchors.leftMargin: returnToQueueButton.visible ? Style.space(6) : 0
                  anchors.right: queuePosition.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.trackInfoOpen ? "СВЕДЕНИЯ И УЧАСТНИКИ"
                    : (root.lyricsOpen ? "ТЕКСТ ПЕСНИ"
                    : (root.browsingLibrary
                      ? "МЕДИАТЕКА · " + String(root.data.libraryBrowseName || "")
                      : "ОЧЕРЕДЬ" + (root.data.queueName ? " · " + root.data.queueName : "")))
                  elide: Text.ElideRight
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.letterSpacing: 1
                }

                Text {
                  textFormat: Text.PlainText
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
                height: visible ? playerPage.paneHeight : 0
                rowCount: 5
                foreground: root.foreground
              }

              Item {
                visible: !root.currentTrackPaneOpen && root.browsingLibrary
                  && !root.queueListLoading && root.trackListDisplay.length === 0
                width: parent.width; height: visible ? playerPage.paneHeight : 0
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "Плейлист пока пуст"
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              ListView {
                id: queueList
                visible: !root.currentTrackPaneOpen && !root.queueListLoading
                  && root.trackListDisplay.length > 0
                width: parent.width
                height: visible ? playerPage.paneHeight : 0
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
                  readonly property bool hovered: queueHover.hovered
                  width: queueList.width - (queueList.contentHeight > queueList.height ? Style.space(8) : 0)
                  height: Style.space(50)
                  radius: Style.cornerRadius
                  color: isCurrent
                    ? Style.selectedFillFor(root.foreground, Color.accent)
                    : (queueRow.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  borderSpec: isCurrent
                    ? Border.controlSpec("normal", root.foreground, Color.accent)
                    : Border.none()

                  HoverHandler { id: queueHover }

                  Row {
                    z: 1
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(9)

                    Text {
                      textFormat: Text.PlainText
                      width: Style.space(18); anchors.verticalCenter: parent.verticalCenter
                      horizontalAlignment: Text.AlignHCenter
                      text: queueRow.isCurrent ? (root.playing ? "󰏤" : "󰐊") : String(modelData.index + 1)
                      color: queueRow.isCurrent ? Color.accent : root.dim
                      font.family: root.fontFamily; font.pixelSize: Style.font.caption
                    }
                    Column {
                      width: parent.width - Style.space(76); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                      Text {
                        textFormat: Text.PlainText
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
                              textFormat: Text.PlainText
                              id: queueArtistLink
                              required property var modelData
                              required property int index
                              text: modelData.name + (index < (queueRow.modelData.artists || []).length - 1 ? ", " : "")
                              color: queueArtistMouse.containsMouse ? Color.accent : root.dim
                              font.family: root.fontFamily; font.pixelSize: Style.font.caption
                              MouseArea {
                                id: queueArtistMouse; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.openCatalogArtist(queueArtistLink.modelData.id)
                              }
                            }
                          }
                          Text {
                            textFormat: Text.PlainText
                            id: queueAlbumLink
                            visible: String(queueRow.modelData.album || "") !== ""
                            text: (queueRow.modelData.artists || []).length > 0
                              ? " · " + String(queueRow.modelData.album) : String(queueRow.modelData.album)
                            color: queueAlbumMouse.containsMouse && String(queueRow.modelData.albumId || "") !== ""
                              ? Color.accent : root.dim
                            font.family: root.fontFamily; font.pixelSize: Style.font.caption
                            MouseArea {
                              id: queueAlbumMouse; anchors.fill: parent
                              enabled: String(queueRow.modelData.albumId || "") !== ""
                              hoverEnabled: enabled
                              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                              onClicked: root.openCatalogAlbum(queueRow.modelData.albumId)
                            }
                          }
                        }
                      }
                    }
                    Item {
                      width: Style.space(40); height: Style.space(26)
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        textFormat: Text.PlainText
                        visible: !queueRow.hovered
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.formatTime(modelData.duration)
                        color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                      }
                      Button {
                        visible: queueRow.hovered
                        width: Style.space(26); height: Style.space(26)
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        horizontalPadding: 0; verticalPadding: 0
                        iconText: "󰐒"; iconSize: Style.font.icon
                        tooltipText: root.browsingLibrary && root.data.libraryEditable === true
                          ? "Добавить или удалить из плейлиста" : "Добавить в плейлист"
                        foreground: root.dim
                        onClicked: root.openCollectionTrack(
                          root.browsingLibrary ? "library" : "queue", Number(modelData.index), modelData,
                          root.browsingLibrary && root.data.libraryEditable === true,
                          String(root.data.libraryPlaylistKind || ""),
                          String(root.data.libraryBrowseName || ""))
                      }
                    }
                  }
                  MouseArea {
                    id: queueMouse; anchors.fill: parent
                    anchors.rightMargin: Style.space(36)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.browsingLibrary) root.transport("playLibraryTrack", modelData.index)
                      else if (!queueRow.isCurrent) root.transport("playQueueTrack", modelData.index)
                    }
                  }
                }

                footer: Item {
                  width: queueList.width
                  height: root.data.libraryLoadingMore === true ? Style.space(36) : 0
                  Text {
                    textFormat: Text.PlainText
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
                height: visible ? playerPage.paneHeight : 0
                rowCount: 5
                foreground: root.foreground
              }

              Item {
                visible: root.lyricsOpen && !root.lyricsLoading
                  && (!root.lyricsData.available || root.lyricsLines.length === 0)
                width: parent.width
                height: visible ? playerPage.paneHeight : 0

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(32)
                  spacing: Style.space(10)
                  Text {
                    textFormat: Text.PlainText
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
                height: visible ? playerPage.paneHeight : 0
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
                    textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
                  width: lyricsList.width
                  height: visible ? contentHeight + Style.space(20) : 0
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
                height: visible ? playerPage.paneHeight : 0
                rowCount: 5
                foreground: root.foreground
              }

              Item {
                visible: root.trackInfoOpen && !root.trackInfoLoading
                  && root.trackInfoRows.length === 0
                width: parent.width
                height: visible ? playerPage.paneHeight : 0

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(32)
                  spacing: Style.space(10)
                  Text {
                    textFormat: Text.PlainText
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
                height: visible ? playerPage.paneHeight : 0
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
                    : (trackInfoLink.containsMouse && String(modelData.entityId || "") !== ""
                      ? Style.hoverFillFor(root.foreground, Color.accent)
                      : Style.normalFillFor(root.foreground, Color.accent))
                  borderSpec: Border.none()

                  MouseArea {
                    id: trackInfoLink
                    z: 2
                    anchors.fill: parent
                    enabled: String(trackInfoRow.modelData.entityId || "") !== ""
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (trackInfoRow.modelData.entityType === "album")
                      root.openCatalogAlbum(trackInfoRow.modelData.entityId)
                  }

                  Column {
                    id: trackInfoRowContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: trackInfoRow.isSection ? 0 : Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: String(trackInfoRow.modelData.label || "")
                      color: trackInfoRow.isSection ? root.dim : Color.accent
                      font.family: root.fontFamily; font.pixelSize: Style.font.caption
                      font.bold: trackInfoRow.isSection
                      font.letterSpacing: trackInfoRow.isSection ? .7 : 0
                    }
                    Text {
                      textFormat: Text.PlainText
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
                      textFormat: Text.PlainText
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

            LibraryPage {
              id: libraryPage
              visible: !root.settingsOpen && root.page === 1
              width: parent.width
              controller: libraryController
              preferences: root.data.preferences || ({})
              foreground: root.foreground
              dim: root.dim
              fontFamily: root.fontFamily
              panelOpened: root.opened
              settingsOpen: root.settingsOpen
              settingsRunning: settingsProcess.running
              focusTarget: keyCatcher
              onPreferenceRequested: function(key, value) { root.setPreference(key, value) }
              onWaveRequested: {
                root.intent("startWave")
                root.selectPage(0)
              }
              onCollectionTrackRequested: function(index, value) {
                root.openCollectionTrack("libraryHub", index, value, false, "", "")
              }
            }

            CatalogPage {
              id: catalogPage
              visible: !root.settingsOpen && root.page === 2
              width: parent.width
              controller: catalogController
              snapshot: root.catalogDisplay
              foreground: root.foreground
              dim: root.dim
              fontFamily: root.fontFamily
              returnToLibrary: root.catalogReturnPage === 1
              hasVisibleError: root.hasVisibleError
              errorCardHeight: errorCard.height
              focusTarget: keyCatcher
              onArtistRequested: function(id) { root.openCatalogArtist(id) }
              onAlbumRequested: function(id) { root.openCatalogAlbum(id) }
              onPlaylistRequested: function(value) { root.openCatalogPlaylist(value) }
              onCollectionTrackRequested: function(source, index, value) {
                root.openCollectionTrack(source, index, value, false, "", "")
              }
              onEntityMoreRequested: root.intent("loadMoreCatalogEntity")
              onRetryEntityRequested: function(entity) {
                if (entity.type === "artist") root.intent("openCatalogArtist", entity.id)
                else if (entity.type === "album") root.intent("openCatalogAlbum", entity.id)
                else if (entity.type === "playlist")
                  root.intent("openCatalogPlaylist", [entity.uuid, entity.owner, entity.kind])
              }
            }

            Column {
              visible: root.settingsOpen
              width: parent.width
              spacing: Style.space(10)

              Item {
                width: parent.width
                height: Style.space(30)

                Button {
                  id: settingsBackButton
                  anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(30); height: Style.space(28)
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: "󰁍"; iconSize: Style.font.icon
                  tooltipText: "Вернуться"
                  foreground: root.foreground
                  onClicked: root.closeSettings()
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.left: settingsBackButton.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "НАСТРОЙКИ"
                  color: root.foreground; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  visible: String(root.data.version || "") !== ""
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  text: "v" + String(root.data.version || "")
                  color: root.dim; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                width: parent.width; label: "Показывать громкость"
                checked: Boolean(root.preference("showVolume", true)); foreground: root.foreground
                onClicked: root.setPreference("showVolume", !checked)
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
                textFormat: Text.PlainText
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
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "Яндекс Музыка подключена"
                    color: root.foreground; font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall; font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
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
                          root.intent("logout")
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
      anchors.fill: parent
      z: 190
      visible: root.playerActionsOpen
      enabled: visible

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, .22)
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.closePlayerActions()
      }

      Pane {
        id: playerActionsSheet
        x: Math.max(Style.space(10), parent.width - width - Style.space(10))
        y: Math.max(Style.space(48), parent.height - height - Style.space(16))
        width: Math.min(parent.width - Style.space(20), Style.space(326))
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

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "ДЕЙСТВИЯ"
            color: root.dim; font.family: root.fontFamily
            font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .8
            bottomPadding: Style.space(4)
          }

          Button {
            id: playerActionsFirstButton
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰐒"; text: "Добавить в плейлист"
            foreground: root.foreground
            enabled: root.activeQueueTargetValid && !root.busy
            onClicked: root.openCurrentTrackCollection()
          }
          Button {
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰐻"; text: "Радио по треку"
            foreground: root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("track_radio")
          }
          Button {
            visible: root.hasTrack
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󱐴"
            text: root.data.disliked
              ? "Снять «Не рекомендовать»" : "Не рекомендовать"
            foreground: root.data.disliked ? Color.urgent : root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("dislike")
          }
          Button {
            visible: root.browsingLibrary && root.data.libraryEditable === true
            width: parent.width; height: Style.space(36)
            leftAlign: true; focusable: true
            iconText: "󰎈"; text: "Подобрать рекомендации"
            foreground: root.foreground
            enabled: !root.busy
            onClicked: root.runPlayerMenuAction("recommendations")
          }
          Button {
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

          Button {
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
      anchors.fill: parent
      z: 200
      visible: collectionController.opened

      MouseArea {
        anchors.fill: parent
        enabled: collectionPopup.dismissReady && !collectionController.busy
        onClicked: collectionPopup.close()
      }

      Pane {
        id: collectionPopup
        readonly property bool opened: collectionController.opened
        property bool dismissReady: false
        signal closed()
        function open() {
          dismissReady = false
          collectionDismissTimer.restart()
          forceActiveFocus()
        }
        function close() {
          if (!opened) return
          dismissReady = false
          closed()
        }
        x: Math.max(0, (parent.width - width) / 2)
        y: Math.max(Style.space(44), (parent.height - height) / 2)
        width: Math.min(parent.width - Style.space(20), Style.space(360))
        height: Math.min(parent.height - Style.space(80), Style.space(400))
        padding: Style.space(12)
        focus: true
        Keys.onEscapePressed: if (!collectionController.busy) close()
        onClosed: {
        if (!(root.collectionResumePending && collectionController.busy)) {
          root.collectionResumePending = false
          if (collectionController.opened) collectionController.close()
        }
      }
      background: BorderSurface {
        color: Color.background
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
        radius: Style.cornerRadius
      }

      contentItem: Column {
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: collectionController.mode === "recommendations"
            ? "РЕКОМЕНДАЦИИ · " + String(collectionController.playlistTitle || "Плейлист")
            : (collectionController.mode === "create" ? "НОВЫЙ ПЛЕЙЛИСТ"
            : (collectionController.mode === "delete" ? "УДАЛИТЬ ТРЕК"
            : (collectionController.mode === "result" ? "УПРАВЛЕНИЕ ПЛЕЙЛИСТОМ"
            : "ДОБАВИТЬ В ПЛЕЙЛИСТ")))
          color: root.dim; font.family: root.fontFamily
          font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: .8
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: ["track", "create", "delete"].indexOf(collectionController.mode) >= 0
          width: parent.width
          text: String(collectionController.target.title || "Трек")
          color: root.foreground; font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight
        }

        Column {
          visible: collectionController.mode === "track"
          width: parent.width; spacing: Style.space(6)
          Button {
            width: parent.width; text: "Создать новый приватный плейлист"
            iconText: "󰐕"; foreground: root.foreground; bordered: true
            enabled: !collectionController.busy
            onClicked: collectionController.beginCreate()
          }
          Text {
            textFormat: Text.PlainText
            visible: (collectionController.ownPlaylists || []).length > 0
            width: parent.width; text: "ВАШИ ПЛЕЙЛИСТЫ"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            visible: collectionController.checkingMemberships
            width: parent.width; text: "Проверяем, где уже есть этот трек…"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            visible: collectionController.membershipError !== ""
            width: parent.width; wrapMode: Text.WordWrap
            text: collectionController.membershipError
            color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Button {
            visible: collectionController.membershipError !== ""
            width: parent.width; text: "Повторить проверку"
            foreground: root.foreground; bordered: true
            enabled: !collectionController.busy && !collectionController.checkingMemberships
            onClicked: collectionController.retryMemberships()
          }
          ListView {
            width: parent.width
            height: Math.min(Style.space(132), contentHeight)
            clip: true; model: collectionController.ownPlaylists || []
            spacing: Style.space(4)
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Button {
              required property var modelData
              readonly property bool alreadyAdded: collectionController.playlistContains(
                String(modelData.kind || ""))
              width: ListView.view.width
              text: String(modelData.title || "Плейлист") + " · " + Number(modelData.count || 0)
                + (alreadyAdded ? " · Уже добавлен" : "")
              foreground: alreadyAdded ? Color.accent : root.foreground
              bordered: true
              enabled: !collectionController.busy
                && !collectionController.checkingMemberships
                && collectionController.membershipError === "" && !alreadyAdded
              onClicked: collectionController.requestAdd(String(modelData.kind || ""))
            }
          }
          Button {
            visible: collectionController.target.canDelete === true
            width: parent.width; text: "Удалить из этого плейлиста"
            iconText: "󰆴"; foreground: Color.urgent; bordered: true
            enabled: !collectionController.busy
            onClicked: collectionController.beginDelete()
          }
        }

        Column {
          visible: collectionController.mode === "create"
          width: parent.width; spacing: Style.space(8)
          TextField {
            id: playlistTitleField
            width: parent.width
            placeholderText: "Название плейлиста"
            foreground: root.foreground; font.family: root.fontFamily
            onTextEdited: collectionController.draftTitle = text
            Keys.onReturnPressed: collectionController.submitCreate()
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width; wrapMode: Text.WordWrap
            text: "Новый плейлист будет приватным. Выбранный трек добавится после создания."
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Row {
            width: parent.width; spacing: Style.space(8)
            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Назад"; foreground: root.foreground; bordered: true
              enabled: !collectionController.busy
              onClicked: collectionController.mode = "track"
            }
            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Создать"; foreground: Color.accent; bordered: true
              enabled: !collectionController.busy
                && String(collectionController.draftTitle || "").trim() !== ""
              onClicked: collectionController.submitCreate()
            }
          }
        }

        Column {
          visible: collectionController.mode === "delete"
          width: parent.width; spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            width: parent.width; wrapMode: Text.WordWrap
            text: "Удалить выбранный трек из «"
              + String(collectionController.target.playlistTitle || "плейлиста") + "»?"
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Row {
            width: parent.width; spacing: Style.space(8)
            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Отмена"; foreground: root.foreground; bordered: true
              enabled: !collectionController.busy
              onClicked: collectionController.mode = "track"
            }
            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Удалить"; foreground: Color.urgent; bordered: true
              enabled: !collectionController.busy
              onClicked: collectionController.confirmDelete()
            }
          }
        }

        Item {
          visible: collectionController.mode === "recommendations"
          width: parent.width
          height: visible ? Style.space(285) : 0
          Text {
            textFormat: Text.PlainText
            visible: collectionController.busy
            anchors.centerIn: parent
            text: "Подбираем треки…"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            visible: !collectionController.busy
              && collectionController.recommendations.length === 0
            anchors.centerIn: parent
            text: "Новых рекомендаций пока нет"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          ListView {
            visible: !collectionController.busy
              && collectionController.recommendations.length > 0
            anchors.fill: parent; clip: true
            model: collectionController.recommendations
            spacing: Style.space(4)
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: BorderSurface {
              required property var modelData
              width: ListView.view.width; height: Style.space(52)
              radius: Style.cornerRadius
              color: "transparent"; borderSpec: Border.none()
              Row {
                anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(8)
                CatalogImage {
                  width: Style.space(38); height: width
                  requestedSource: String(modelData.artUrl || "")
                  foreground: root.foreground; fontFamily: root.fontFamily
                  fillMode: Image.PreserveAspectCrop
                }
                Column {
                  width: parent.width - Style.space(80)
                  anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width; text: String(modelData.title || "Трек")
                    color: root.foreground; font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width; text: String(modelData.artist || "")
                    color: root.dim; font.family: root.fontFamily
                    font.pixelSize: Style.font.caption; elide: Text.ElideRight
                  }
                }
                Button {
                  width: Style.space(26); height: Style.space(26)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalPadding: 0; verticalPadding: 0
                  iconText: "󰐕"; iconSize: Style.font.icon
                  tooltipText: "Добавить"
                  foreground: Color.accent
                  enabled: !collectionController.busy
                  onClicked: collectionController.addRecommendation(modelData)
                }
              }
            }
          }
        }

        Column {
          visible: collectionController.mode === "result"
          width: parent.width; spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            width: parent.width; wrapMode: Text.WordWrap
            text: collectionController.error !== ""
              ? collectionController.error : collectionController.message
            color: collectionController.error !== "" ? Color.urgent : root.foreground
            font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Button {
            width: parent.width
            text: collectionController.error !== "" ? "Закрыть" : "Готово"
            foreground: root.foreground; bordered: true
            enabled: !collectionController.busy
            onClicked: collectionPopup.close()
          }
        }

        Button {
          visible: collectionController.mode === "track"
            || collectionController.mode === "recommendations"
          width: parent.width; text: "Закрыть"
          foreground: root.dim; bordered: true
          enabled: !collectionController.busy
          onClicked: collectionPopup.close()
        }
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
