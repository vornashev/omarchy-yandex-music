import QtQuick

Item {
  id: root
  width: 0
  height: 0

  property var snapshot: ({ view: "home", section: "", loading: false,
    loadingMore: false, hasMore: false, total: 0,
    error: "", warning: "", items: [], revision: 0 })
  property var ownPlaylists: []
  property string stationQuery: ""
  property int stationPageSize: 50
  property int stationVisibleCount: stationPageSize
  readonly property string view: String(snapshot.view || "home")
  readonly property string section: String(snapshot.section || "")
  readonly property bool stationMode: view === "section" && section === "stations"
  readonly property bool loading: snapshot.loading === true
  readonly property bool loadingMore: !stationMode && snapshot.loadingMore === true
  readonly property bool hasMore: stationMode
    ? stationVisibleCount < filteredStationItems().length
    : snapshot.hasMore === true
  readonly property var rows: buildRows()

  signal sectionRequested(string section)
  signal backRequested()
  signal retryRequested(string section)
  signal loadMoreRequested()
  signal collectionRequested(string command, string argument)
  signal entityRequested(string type, string id, string uuid, string owner, string kind)
  signal trackPlaybackRequested(int index)
  signal stationPlaybackRequested(string station, string title)

  function sectionTitle(value) {
    var labels = {
      personal: "ПЕРСОНАЛЬНЫЕ ПЛЕЙЛИСТЫ",
      history: "НЕДАВНО СЛУШАЛИ",
      albums: "ЛЮБИМЫЕ АЛЬБОМЫ",
      artists: "ЛЮБИМЫЕ ИСПОЛНИТЕЛИ",
      playlists: "СОХРАНЁННЫЕ ПЛЕЙЛИСТЫ",
      stations: "РАДИОСТАНЦИИ"
    }
    return labels[String(value || "")] || "МЕДИАТЕКА"
  }

  function filteredStationItems() {
    var items = snapshot.items || []
    if (!stationMode) return items
    var query = String(stationQuery || "").trim().toLowerCase()
    if (query === "") return items
    var filtered = []
    for (var i = 0; i < items.length; i++) {
      var value = items[i] || {}
      var haystack = (String(value.title || "") + " "
        + String(value.subtitle || "")).toLowerCase()
      if (haystack.indexOf(query) >= 0) filtered.push(value)
    }
    return filtered
  }

  function setStationQuery(value) {
    var next = String(value || "")
    if (stationQuery === next) return
    stationQuery = next
    stationVisibleCount = stationPageSize
  }

  function buildRows() {
    var rows = []
    if (view === "home") {
      rows.push({ kind: "section", title: "ВАША МУЗЫКА" })
      rows.push({ kind: "collection", command: "likes", title: "Мне нравится",
        icon: "󰋑", subtitle: "Любимые треки" })
      var playlists = ownPlaylists || []
      for (var i = 0; i < playlists.length; i++) {
        var playlist = playlists[i] || {}
        rows.push({ kind: "collection", command: "playlist", argument: String(playlist.kind || ""),
          title: String(playlist.title || "Плейлист"), icon: "󰲸",
          subtitle: Number(playlist.count || 0) + " треков" })
      }
      rows.push({ kind: "section", title: "ДЛЯ ВАС" })
      rows.push({ kind: "navigation", section: "personal", title: "Персональные плейлисты",
        icon: "󰎈", subtitle: "Плейлист дня, Тайник, Премьера и Дежавю" })
      rows.push({ kind: "navigation", section: "history", title: "Недавно слушали",
        icon: "󰋚", subtitle: "Треки и контексты из истории" })
      rows.push({ kind: "section", title: "ЛЮБИМОЕ" })
      rows.push({ kind: "navigation", section: "albums", title: "Альбомы",
        icon: "󰀥", subtitle: "Отмеченные альбомы" })
      rows.push({ kind: "navigation", section: "artists", title: "Исполнители",
        icon: "󰠃", subtitle: "Любимые исполнители" })
      rows.push({ kind: "navigation", section: "playlists", title: "Плейлисты",
        icon: "󰲸", subtitle: "Сохранённые чужие плейлисты" })
      rows.push({ kind: "section", title: "РАДИО" })
      rows.push({ kind: "navigation", section: "stations", title: "Все радиостанции",
        icon: "󰐻", subtitle: "Жанры, занятия и настроение" })
      return rows
    }

    rows.push({ kind: "back", title: "Назад в медиатеку", icon: "󰁍" })
    rows.push({ kind: "section", title: sectionTitle(section) })
    if (String(snapshot.error || "") !== "") {
      rows.push({ kind: "error", title: String(snapshot.error) })
      rows.push({ kind: "retry", title: "Повторить" })
      return rows
    }
    if (String(snapshot.warning || "") !== "")
      rows.push({ kind: "warning", title: String(snapshot.warning) })
    var items = stationMode ? filteredStationItems() : (snapshot.items || [])
    var visibleItems = stationMode ? items.slice(0, stationVisibleCount) : items
    for (var j = 0; j < visibleItems.length; j++) {
      var value = visibleItems[j] || {}
      rows.push({ kind: String(value.entityType || "item"), value: value })
    }
    if (!loading && items.length === 0)
      rows.push({ kind: "empty", title: stationMode && String(stationQuery || "").trim() !== ""
        ? "Ничего не найдено" : "Здесь пока ничего нет" })
    if (!stationMode && (hasMore || loadingMore))
      rows.push({ kind: "loadMore", title: loadingMore ? "Загружаем…" : "Загрузить ещё" })
    return rows
  }

  function applySnapshot(value) {
    var previousView = view
    var previousSection = section
    snapshot = value || ({ view: "home", section: "", loading: false,
      loadingMore: false, hasMore: false, total: 0,
      error: "", warning: "", items: [], revision: 0 })
    if (previousView !== view || previousSection !== section) {
      stationQuery = ""
      stationVisibleCount = stationPageSize
    } else if (stationMode) {
      stationVisibleCount = Math.max(stationPageSize,
        Math.min(stationVisibleCount, filteredStationItems().length))
    }
  }

  function openSection(value) {
    var next = String(value || "")
    if (next === "") return
    sectionRequested(next)
  }

  function requestMore() {
    if (!hasMore || loadingMore) return
    if (stationMode) {
      stationVisibleCount = Math.min(filteredStationItems().length,
        stationVisibleCount + stationPageSize)
      return
    }
    var copy = {}
    for (var key in snapshot) copy[key] = snapshot[key]
    copy.loadingMore = true
    snapshot = copy
    loadMoreRequested()
  }

  function activate(row) {
    var value = row || {}
    var kind = String(value.kind || "")
    if (kind === "back") backRequested()
    else if (kind === "retry") retryRequested(section)
    else if (kind === "loadMore") requestMore()
    else if (kind === "navigation") openSection(value.section)
    else if (kind === "collection")
      collectionRequested(String(value.command || ""), String(value.argument || ""))
    else {
      var item = value.value || {}
      if (item.available === false) return
      var type = String(item.entityType || kind)
      if (String(item.personalId || "") !== "")
        collectionRequested("browse_personal", String(item.personalId))
      else if (type === "track")
        trackPlaybackRequested(Number(item.trackIndex || 0))
      else if (type === "station")
        stationPlaybackRequested(String(item.stationId || ""), String(item.title || "Радиостанция"))
      else if (type === "artist")
        entityRequested("artist", String(item.id || ""), "", "", "")
      else if (type === "album")
        entityRequested("album", String(item.id || ""), "", "", "")
      else if (type === "playlist")
        entityRequested("playlist", "", String(item.uuid || ""),
                        String(item.owner || ""), String(item.kind || ""))
    }
  }
}
