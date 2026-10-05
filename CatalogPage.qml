import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Поиск и страницы сущностей; навигационным стеком управляет родитель.
Item {
  id: root
  required property var controller
  required property var snapshot
  property bool wide: false
  property color foreground: "white"
  property color dim: "gray"
  property string fontFamily: ""
  property bool hasVisibleError: false
  property real errorCardHeight: 0
  property var focusTarget: null
  property string currentTrackId: ""
  readonly property bool searchActiveFocus: searchField.activeFocus
  readonly property var viewport: wideAll ? allFlick : (wideEntity ? entityFlick : catalogResultsList)
  readonly property real viewportY: Math.max(0, viewport.contentY - (viewport.originY || 0))
  readonly property bool searchListLoading: isSearch ? search.loading === true : entity.loading === true
  readonly property var rows: buildCatalogRows()
  readonly property string view: String(snapshot.view || "search")
  readonly property bool isSearch: view === "search"
  readonly property var search: snapshot.search || ({})
  readonly property var sections: search.sections || ({})
  readonly property var entity: snapshot.entity || ({})
  readonly property string filterValue: String(search.filter || controller.filter || "all")
  readonly property real pad: wide ? Style.space(28) : Style.space(16)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .08)
  readonly property bool hasQuery: String(search.query || "") !== ""
  readonly property var best: bestResult()
  readonly property bool wideAll: wide && isSearch && filterValue === "all" && hasQuery
    && !search.loading && best.type !== ""
  readonly property bool wideArtist: wide && view === "artist" && !searchListLoading
  readonly property bool wideEntity: wide && !isSearch && !searchListLoading

  signal artistRequested(string id, string name)
  signal albumRequested(string id, string title)
  signal playlistRequested(var value)
  signal collectionTrackRequested(string source, int index, var value, var anchor)
  signal entityMoreRequested()
  signal retryEntityRequested(var entity)
  signal escapeRequested()

  function setSearchText(value) { searchField.text = String(value || "") }
  function focusSearch() { if (visible && isSearch) searchField.forceActiveFocus() }
  function clearSearchFocus() { searchField.focus = false }
  function scrollToBeginning() { preserveViewport(0) }
  function resetViewport() { preserveViewport(0) }
  function restoreViewport(y) { preserveViewport(y) }
  function preserveViewport(y) {
    var surface = viewport
    if (surface === catalogResultsList) surface.forceLayout()
    surface.contentY = (surface.originY || 0) + Math.max(0, Math.min(Number(y) || 0,
      Math.max(0, surface.contentHeight - surface.height)))
  }

  onIsSearchChanged: if (!isSearch) clearSearchFocus()
  onVisibleChanged: if (!visible) clearSearchFocus()

  function sectionItems(name) { return (sections[name] || {}).items || [] }
  function sectionTotal(name) { return Number((sections[name] || {}).total || 0) }
  function groupNumber(value) {
    return String(Number(value || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  }
  function artistLine(value) {
    var artists = value.artists || []
    var names = []
    for (var i = 0; i < artists.length; i++) names.push(String(artists[i].name || ""))
    return names.filter(function(n) { return n !== "" }).join(", ")
  }
  function bestResult() {
    var order = [["artists", "artist", "Исполнитель"], ["albums", "album", "Альбом"],
      ["playlists", "playlist", "Плейлист"], ["tracks", "track", "Трек"]]
    for (var i = 0; i < order.length; i++) {
      var items = sectionItems(order[i][0])
      if (items.length > 0) return { type: order[i][1], label: order[i][2], value: items[0] }
    }
    return { type: "", label: "", value: ({}) }
  }
  function openBest() {
    var value = best.value
    if (best.type === "artist") artistRequested(value.id, String(value.name || value.title || ""))
    else if (best.type === "album") albumRequested(value.id, String(value.title || ""))
    else if (best.type === "playlist") playlistRequested(value)
    else if (best.type === "track") controller.trackPlaybackRequested("search", Number(value.index || 0))
  }
  function setFilter(value) {
    controller.filter = value
    if (controller.trimmedText() !== "") controller.submit()
  }

  function activateRow(row) {
    var value = row.value || {}
    if (row.kind === "track")
      root.controller.trackPlaybackRequested(String(row.source || "search"), Number(value.index || 0))
    else if (row.kind === "artist") root.artistRequested(value.id, String(value.name || value.title || ""))
    else if (row.kind === "album") root.albumRequested(value.id, String(value.title || ""))
    else if (row.kind === "playlist") root.playlistRequested(value)
    else if (row.kind === "loadSearch") root.controller.loadMoreRequested()
    else if (row.kind === "loadEntity") root.entityMoreRequested()
    else if (row.kind === "loadRelease")
      root.controller.releaseMoreRequested(String(row.section || ""))
    else if (row.kind === "retrySearch") root.controller.submit()
    else if (row.kind === "retryEntity") root.retryEntityRequested(root.snapshot.entity || {})
  }

  function buildCatalogRows() {
    var rows = []
    var snapshot = root.snapshot || {}
    var view = String(snapshot.view || "search")
    var search = snapshot.search || {}
    var sections = search.sections || {}
    var labels = { tracks: "ТРЕКИ", artists: "ИСПОЛНИТЕЛИ",
      albums: "АЛЬБОМЫ", playlists: "ПЛЕЙЛИСТЫ" }
    if (view === "search") {
      if (String(search.query || "") === "" && search.loading !== true) {
        rows.push({ kind: "empty", title: "Введите запрос для поиска по каталогу" })
        return rows
      }
      var names = ["tracks", "artists", "albums", "playlists"]
      var selected = String(search.filter || root.controller.filter || "all")
      if (selected === "all" && !root.wide && root.best.type !== "")
        rows.push({ kind: "best", type: root.best.type, label: root.best.label, value: root.best.value })
      for (var i = 0; i < names.length; i++) {
        var name = names[i]
        if (selected !== "all" && selected + "s" !== name) continue
        var section = sections[name] || { items: [], total: 0, hasMore: false }
        rows.push({ kind: "section", title: labels[name], count: Number(section.total || 0) })
        var items = section.items || []
        for (var j = 0; j < items.length; j++)
          rows.push({ kind: name.slice(0, -1), value: items[j], source: "search" })
        if (items.length === 0 && search.loading !== true)
          rows.push({ kind: "empty", title: "Ничего не найдено" })
      }
      if (String(search.error || "") !== "") {
        rows.push({ kind: "error", title: search.error })
        rows.push({ kind: "retrySearch", title: "Повторить поиск" })
      }
      var hasMore = false
      for (var n = 0; n < names.length; n++)
        if ((sections[names[n]] || {}).hasMore === true) hasMore = true
      if (hasMore || search.loadingMore === true)
        rows.push({ kind: "loadSearch", title: search.loadingMore ? "Загружаем…" : "Загрузить ещё" })
      return rows
    }
    var entity = snapshot.entity || {}
    rows.push({ kind: "entityHeader", value: entity })
    if (wide && String(entity.description || "") !== "")
      rows.push({ kind: "description", title: entity.description })
    if (String(entity.error || "") !== "") {
      rows.push({ kind: "error", title: entity.error })
      rows.push({ kind: "retryEntity", title: "Повторить загрузку" })
    }
    if (String(entity.warning || "") !== "") rows.push({ kind: "warning", title: entity.warning })
    var tracks = entity.tracks || []
    if (tracks.length > 0) rows.push({ kind: "section", title: view === "artist" ? "ПОПУЛЯРНЫЕ ТРЕКИ" : "ТРЕКИ", count: tracks.length })
    for (var k = 0; k < tracks.length; k++)
      rows.push({ kind: "track", value: tracks[k], source: "entity" })
    if ((view === "album" || view === "playlist") && (entity.hasMore === true || entity.loadingMore === true))
      rows.push({ kind: "loadEntity", title: entity.loadingMore ? "Загружаем…" : "Загрузить ещё треки" })
    if (view === "artist") {
      var releaseSections = [{ key: "albums", title: "АЛЬБОМЫ" }, { key: "singles", title: "СИНГЛЫ" }]
      for (var r = 0; r < releaseSections.length; r++) {
        var releaseSection = releaseSections[r]
        var releases = entity[releaseSection.key] || []
        rows.push({ kind: "section", title: releaseSection.title, count: releases.length })
        for (var a = 0; a < releases.length; a++) rows.push({ kind: "album", value: releases[a] })
        if ((entity.releaseErrors || {})[releaseSection.key])
          rows.push({ kind: "error", title: entity.releaseErrors[releaseSection.key] })
        if ((entity.releaseHasMore || {})[releaseSection.key] === true
            || (entity.releaseLoading || {})[releaseSection.key] === true)
          rows.push({ kind: "loadRelease", section: releaseSection.key,
            title: (entity.releaseLoading || {})[releaseSection.key] ? "Загружаем…" : "Загрузить ещё" })
      }
      var similar = entity.similar || []
      if (similar.length > 0)
        rows.push({ kind: "section", title: "ПОХОЖИЕ ИСПОЛНИТЕЛИ", count: similar.length })
      for (var s = 0; s < similar.length; s++)
        rows.push({ kind: "artist", value: similar[s] })
    }
    return rows
  }

  // ── building blocks ───────────────────────────────────────────────────
  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
    font.bold: true; font.letterSpacing: 1.2
  }
  component LinkLabel: Text {
    id: link
    signal clicked()
    textFormat: Text.PlainText
    color: linkMouse.containsMouse ? Color.accent : root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
    MouseArea {
      id: linkMouse
      anchors.fill: parent; anchors.margins: -Style.space(4)
      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }
  component ActionButton: IconButton {
    property bool primary: false
    height: Style.space(30)
    horizontalPadding: Style.space(14)
    fontSize: Style.font.bodySmall
    bordered: true
    foreground: primary ? Color.accent : root.foreground
    background: primary ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .22) : "transparent"
  }
  component TrackLine: BorderSurface {
    id: line
    property var value: ({})
    property string source: "search"
    property int number: 0
    property bool current: false
    readonly property bool hovered: lineHover.hovered
    height: Style.space(52)
    radius: Style.cornerRadius
    color: hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
    borderSpec: Border.none()
    HoverHandler { id: lineHover }
    Text {
      textFormat: Text.PlainText
      visible: line.number > 0
      anchors.left: parent.left; width: Style.space(28)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      text: String(line.number); color: root.dim
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
    }
    CatalogImage {
      id: lineCover
      anchors.left: parent.left; anchors.leftMargin: line.number > 0 ? Style.space(34) : Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36); height: width
      requestedSource: String(line.value.artUrl || "")
      foreground: root.foreground; fontFamily: root.fontFamily
      fillMode: Image.PreserveAspectCrop
    }
    Column {
      z: 1
      anchors.left: lineCover.right; anchors.leftMargin: Style.space(12)
      anchors.right: lineTail.left; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: String(line.value.title || "Без названия")
        color: root.foreground; font.family: root.fontFamily
        font.pixelSize: Style.font.body; font.bold: true
      }
      Item {
        width: parent.width; height: Style.space(14); clip: true
        Row {
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            model: line.value.artists || []
            Text {
              textFormat: Text.PlainText
              id: lineArtist
              required property var modelData
              required property int index
              text: modelData.name + (index < (line.value.artists || []).length - 1 ? ", " : "")
              color: lineArtistMouse.containsMouse ? Color.accent : root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
              MouseArea {
                id: lineArtistMouse; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.artistRequested(lineArtist.modelData.id, String(lineArtist.modelData.name || ""))
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: String(line.value.album || "") !== ""
            text: (line.value.artists || []).length > 0 ? " · " + String(line.value.album) : String(line.value.album)
            color: lineAlbumMouse.containsMouse && String(line.value.albumId || "") !== "" ? Color.accent : root.dim
            font.family: root.fontFamily; font.pixelSize: Style.font.caption
            MouseArea {
              id: lineAlbumMouse; anchors.fill: parent
              enabled: String(line.value.albumId || "") !== ""
              hoverEnabled: enabled
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.albumRequested(line.value.albumId, String(line.value.albumTitle || ""))
            }
          }
        }
      }
    }
    Item {
      id: lineTail
      z: 2
      anchors.right: parent.right; anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40); height: Style.space(26)
      Text {
        textFormat: Text.PlainText
        visible: !line.hovered
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
        text: Number(line.value.duration || 0) > 0 ? formatDuration(line.value.duration) : ""
        color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
      }
      IconButton {
        id: lineTrackAction
        visible: line.hovered
        width: Style.space(26); height: Style.space(26)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        horizontalPadding: 0; verticalPadding: 0
        iconText: "󰐒"; iconSize: Style.font.icon
        tooltipText: "В плейлист…"
        foreground: hot ? Color.accent : root.dim
        onClicked: root.collectionTrackRequested(
          line.source === "entity" ? "catalogEntity" : "catalogSearch",
          Number(line.value.index || 0), line.value, lineTrackAction)
      }
    }
    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: Style.space(52)
      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: root.controller.trackPlaybackRequested(line.source, Number(line.value.index || 0))
    }
  }
  function formatDuration(value) {
    var seconds = Math.max(0, Math.round(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
  }
  component ArtistBubble: Item {
    id: bubble
    property var value: ({})
    property real size: Style.space(64)
    width: size + Style.space(20); height: size + Style.space(26)
    RoundImage {
      id: bubbleImage
      anchors.horizontalCenter: parent.horizontalCenter
      width: bubble.size; height: width
      requestedSource: String(bubble.value.artUrl || "")
      foreground: root.foreground; fontFamily: root.fontFamily
    }
    Text {
      textFormat: Text.PlainText
      anchors.top: bubbleImage.bottom; anchors.topMargin: Style.space(8)
      width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
      text: String(bubble.value.name || bubble.value.title || "")
      color: bubbleMouse.containsMouse ? Color.accent : root.dim
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: bubbleMouse
      anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: root.artistRequested(bubble.value.id, String(bubble.value.name || bubble.value.title || ""))
    }
  }
  component CoverCard: Item {
    id: card
    property var value: ({})
    property string kind: "album"
    property real size: Style.space(100)
    signal clicked()
    width: size; height: size + Style.space(40)
    CatalogImage {
      id: cardImage
      width: card.size; height: width
      requestedSource: String(card.value.artUrl || "")
      foreground: root.foreground; fontFamily: root.fontFamily
      fillMode: Image.PreserveAspectCrop
    }
    Text {
      textFormat: Text.PlainText
      anchors.top: cardImage.bottom; anchors.topMargin: Style.space(6)
      width: parent.width; elide: Text.ElideRight
      text: String(card.value.title || card.value.name || "")
      color: cardMouse.containsMouse ? Color.accent : root.foreground
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      anchors.top: cardImage.bottom; anchors.topMargin: Style.space(24)
      width: parent.width; elide: Text.ElideRight
      text: String(card.value.year || card.value.ownerName || root.artistLine(card.value) || "")
      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: cardMouse
      anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: card.clicked()
    }
  }

  // Поле и фильтры видны только в корне поиска; общий NavHeader находится снаружи.
  Item {
    id: header
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: root.isSearch ? Style.space(root.wide ? 118 : 106) : 0

    Item {
      id: searchRow
      visible: root.isSearch
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      anchors.top: parent.top; anchors.topMargin: Style.space(root.wide ? 24 : 12)
      height: Style.space(40)
      TextField {
        id: searchField
        anchors.fill: parent
        leftPadding: Style.space(38)
        rightPadding: Style.space(root.wide ? 110 : 40)
        placeholderText: "Трек, исполнитель, альбом или плейлист"
        foreground: root.foreground
        font.family: root.fontFamily
        onTextEdited: root.controller.updateInput(text)
        Keys.onDownPressed: function(event) {
          if (!root.controller.moveSuggestion(1)) return
          suggestionList.positionViewAtIndex(
            root.controller.highlightedSuggestionIndex, ListView.Contain)
          event.accepted = true
        }
        Keys.onUpPressed: function(event) {
          if (!root.controller.moveSuggestion(-1)) return
          suggestionList.positionViewAtIndex(
            root.controller.highlightedSuggestionIndex, ListView.Contain)
          event.accepted = true
        }
        Keys.onReturnPressed: {
          if (root.controller.acceptHighlightedSuggestion())
            text = root.controller.fieldText
          else
            root.controller.submit()
        }
        Keys.onEscapePressed: {
          root.controller.dismissSuggestions()
          focus = false
          if (root.focusTarget) root.focusTarget.forceActiveFocus()
          root.escapeRequested()
        }
      }
      LucideIcon {
        z: 2
        anchors.left: parent.left; anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰍉"; color: searchField.activeFocus ? Color.accent : root.dim
        fontFamily: root.fontFamily; size: Style.font.icon
      }
      LucideIcon {
        z: 2
        visible: root.controller.suggestionLoading
        anchors.right: parent.right; anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰦖"; color: root.dim
        fontFamily: root.fontFamily; size: Style.space(15)
        RotationAnimator on rotation {
          running: root.controller.suggestionLoading
          from: 0; to: 360; duration: 800; loops: Animation.Infinite
        }
      }
      Text {
        textFormat: Text.PlainText
        z: 2
        visible: root.wide && !root.controller.suggestionLoading && searchField.text !== ""
        anchors.right: parent.right; anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        text: "Esc — очистить"; color: root.dim
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: chips
      visible: root.isSearch
      anchors.left: parent.left; anchors.leftMargin: root.pad
      anchors.right: parent.right; anchors.rightMargin: root.pad
      anchors.top: searchRow.bottom; anchors.topMargin: Style.space(12)
      height: Style.space(30)
      spacing: Style.space(root.wide ? 10 : 6)
      Repeater {
        model: [
          { value: "all", label: "Все", name: "" },
          { value: "track", label: "Треки", name: "tracks" },
          { value: "artist", label: root.wide ? "Артисты" : "Артисты", name: "artists" },
          { value: "album", label: "Альбомы", name: "albums" },
          { value: "playlist", label: root.wide ? "Плейлисты" : "Плейл.", name: "playlists" }]
        BorderSurface {
          id: chip
          required property var modelData
          readonly property bool on: root.controller.filter === modelData.value
          readonly property real total: modelData.name === "" ? 0 : root.sectionTotal(modelData.name)
          width: root.wide ? chipRow.implicitWidth + Style.space(24)
            : (chips.width - chips.spacing * 4) / (modelData.value === "all" ? 6 : 5) * (modelData.value === "all" ? 1 : 1)
          height: Style.space(30)
          radius: Style.cornerRadius
          color: on ? Style.selectedFillFor(root.foreground, Color.accent)
            : (chipMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
          borderSpec: Border.controlSpec(on ? "selected" : "normal", root.foreground, Color.accent)
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: chip.modelData.label
              color: chip.on ? root.foreground : root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: chip.on
            }
            Text {
              textFormat: Text.PlainText
              visible: root.wide && chip.total > 0
              text: root.groupNumber(chip.total); color: root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            id: chipMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.setFilter(chip.modelData.value)
          }
        }
      }
    }

  }

  // ── body ──────────────────────────────────────────────────────────────
  Item {
    id: body
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: header.bottom; anchors.bottom: parent.bottom
    clip: true

    SkeletonList {
      visible: root.searchListLoading
      anchors.fill: parent
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      rowCount: 8
      foreground: root.foreground
    }

    // wide search "all": best result + artists on the left, tracks on the right
    Flickable {
      id: allFlick
      visible: root.wideAll && !root.searchListLoading && !root.controller.suggestionsVisible
      anchors.fill: parent
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      contentWidth: width
      contentHeight: Math.max(allLeft.implicitHeight, allRight.implicitHeight) + Style.space(20)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: allLeft
        width: Style.space(280)
        spacing: Style.space(12)
        SectionLabel { text: "ЛУЧШИЙ РЕЗУЛЬТАТ" }
        BorderSurface {
          width: parent.width; height: bestColumn.implicitHeight + Style.space(32)
          color: Style.normalFillFor(root.foreground, Color.accent)
          borderSpec: Border.none()
          Column {
            id: bestColumn
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.margins: Style.space(16)
            spacing: Style.space(10)
            CatalogImage {
              width: Style.space(96); height: width
              requestedSource: String(root.best.value.artUrl || "")
              foreground: root.foreground; fontFamily: root.fontFamily
              fillMode: Image.PreserveAspectCrop
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: String(root.best.value.name || root.best.value.title || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.title + Style.space(6); font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: root.best.label + (root.artistLine(root.best.value) !== ""
                ? " · " + root.artistLine(root.best.value) : "")
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Row {
              spacing: Style.space(8)
              ActionButton {
                visible: root.best.type === "artist"
                primary: true
                text: "Радио"; iconText: "󰐷"
                onClicked: root.controller.radioRequested("artist:" + String(root.best.value.id || ""),
                  String(root.best.value.name || ""))
              }
              ActionButton {
                text: root.best.type === "track" ? "Играть" : "Открыть →"
                onClicked: root.openBest()
              }
            }
          }
        }
        SectionLabel { visible: root.sectionItems("artists").length > 0; topPadding: Style.space(6); text: "АРТИСТЫ" }
        Row {
          visible: root.sectionItems("artists").length > 0
          spacing: Style.space(2)
          Repeater {
            model: root.sectionItems("artists").slice(0, 3)
            ArtistBubble { required property var modelData; value: modelData }
          }
        }
        SectionLabel { visible: root.sectionItems("albums").length > 0; topPadding: Style.space(6); text: "АЛЬБОМЫ" }
        Row {
          visible: root.sectionItems("albums").length > 0
          spacing: Style.space(12)
          Repeater {
            model: root.sectionItems("albums").slice(0, 2)
            CoverCard {
              required property var modelData
              value: modelData; size: Style.space(84)
              onClicked: root.albumRequested(modelData.id, String(modelData.title || ""))
            }
          }
        }
        SectionLabel { visible: root.sectionItems("playlists").length > 0; topPadding: Style.space(6); text: "ПЛЕЙЛИСТЫ" }
        Row {
          visible: root.sectionItems("playlists").length > 0
          spacing: Style.space(12)
          Repeater {
            model: root.sectionItems("playlists").slice(0, 2)
            CoverCard {
              required property var modelData
              value: modelData; size: Style.space(84)
              onClicked: root.playlistRequested(modelData)
            }
          }
        }
      }

      Column {
        id: allRight
        x: allLeft.width + Style.space(24)
        width: allFlick.width - x
        spacing: Style.space(4)
        Item {
          width: parent.width; height: Style.space(24)
          SectionLabel {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: "ТРЕКИ · " + root.groupNumber(root.sectionTotal("tracks"))
          }
          LinkLabel {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "Все →"
            onClicked: root.setFilter("track")
          }
        }
        Repeater {
          model: root.sectionItems("tracks")
          TrackLine {
            required property var modelData
            width: allRight.width
            value: modelData; source: "search"
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: root.sectionItems("tracks").length === 0
          text: "Треков не найдено"; color: root.dim
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          visible: String(root.search.error || "") !== ""
          width: parent.width; wrapMode: Text.WordWrap
          text: String(root.search.error || ""); color: Color.urgent
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // wide entity pages (artist / album / playlist)
    Flickable {
      id: entityFlick
      visible: root.wideEntity
      anchors.fill: parent
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      contentWidth: width
      contentHeight: entityColumn.implicitHeight + Style.space(24)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: entityColumn
        width: entityFlick.width
        spacing: Style.space(16)

        Item {
          width: parent.width; height: Style.space(140)
          CatalogImage {
            id: heroCover
            width: Style.space(140); height: width
            requestedSource: String(root.entity.artUrl || "")
            foreground: root.foreground; fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            anchors.left: heroCover.right; anchors.leftMargin: Style.space(20)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            SectionLabel {
              color: Color.accent
              text: root.view === "artist" ? "ИСПОЛНИТЕЛЬ" : (root.view === "album" ? "АЛЬБОМ" : "ПЛЕЙЛИСТ")
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: String(root.entity.title || root.entity.name || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.space(26); font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width; elide: Text.ElideRight
              text: [root.artistLine(root.entity), root.entity.year || root.entity.releaseDate,
                root.entity.genre, root.entity.ownerName].filter(function(v) {
                  return String(v || "") !== "" }).join(" · ")
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              visible: String(root.entity.description || "") !== ""
              width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
              text: String(root.entity.description || ""); color: root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; lineHeight: 1.25
            }
            Row {
              visible: root.view === "artist"
              spacing: Style.space(8)
              ActionButton {
                primary: true
                text: "Радио исполнителя"; iconText: "󰐷"
                onClicked: root.controller.radioRequested("artist:" + String(root.entity.id || ""),
                  String(root.entity.name || root.entity.title || ""))
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: String(root.entity.error || "") !== ""
          width: parent.width; wrapMode: Text.WordWrap
          text: String(root.entity.error || ""); color: Color.urgent
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
        IconButton {
          visible: String(root.entity.error || "") !== ""
          text: "Повторить загрузку"; iconText: "󰑐"; bordered: true; foreground: root.foreground
          onClicked: root.retryEntityRequested(root.entity)
        }

        Row {
          width: parent.width
          spacing: Style.space(24)
          Column {
            id: entityTracks
            width: root.view === "artist" ? parent.width * .6 - Style.space(12) : parent.width
            spacing: Style.space(2)
            SectionLabel {
              visible: (root.entity.tracks || []).length > 0
              bottomPadding: Style.space(4)
              text: (root.view === "artist" ? "ПОПУЛЯРНЫЕ ТРЕКИ" : "ТРЕКИ") + " · " + (root.entity.tracks || []).length
            }
            Repeater {
              model: root.entity.tracks || []
              TrackLine {
                required property var modelData
                required property int index
                width: entityTracks.width
                value: modelData; source: "entity"; number: index + 1
                current: String(modelData.trackId || "") === root.currentTrackId
              }
            }
            IconButton {
              visible: (root.view === "album" || root.view === "playlist")
                && (root.entity.hasMore === true || root.entity.loadingMore === true)
              text: root.entity.loadingMore ? "Загружаем…" : "Загрузить ещё треки"
              bordered: true; foreground: Color.accent
              onClicked: root.entityMoreRequested()
            }
          }
          Column {
            id: entityReleases
            visible: root.view === "artist"
            width: parent.width * .4 - Style.space(12)
            spacing: Style.space(10)
            property string releaseKind: "albums"
            Item {
              width: parent.width; height: Style.space(22)
              SectionLabel {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: (entityReleases.releaseKind === "albums" ? "АЛЬБОМЫ" : "СИНГЛЫ") + " · "
                  + (root.entity[entityReleases.releaseKind] || []).length
              }
              LinkLabel {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: entityReleases.releaseKind === "albums" ? "Синглы" : "Альбомы"
                onClicked: entityReleases.releaseKind = entityReleases.releaseKind === "albums" ? "singles" : "albums"
              }
            }
            Flow {
              width: parent.width; spacing: Style.space(12)
              Repeater {
                model: root.entity[entityReleases.releaseKind] || []
                CoverCard {
                  required property var modelData
                  value: modelData
                  size: (entityReleases.width - Style.space(12)) / 2
                  onClicked: root.albumRequested(modelData.id, String(modelData.title || ""))
                }
              }
            }
            IconButton {
              visible: (root.entity.releaseHasMore || {})[entityReleases.releaseKind] === true
              text: "Загрузить ещё"; bordered: true; foreground: Color.accent
              onClicked: root.controller.releaseMoreRequested(entityReleases.releaseKind)
            }
          }
        }

        SectionLabel { visible: root.view === "artist" && (root.entity.similar || []).length > 0; text: "ПОХОЖИЕ ИСПОЛНИТЕЛИ" }
        Row {
          visible: root.view === "artist" && (root.entity.similar || []).length > 0
          spacing: Style.space(6)
          Repeater {
            model: (root.entity.similar || []).slice(0, 8)
            ArtistBubble { required property var modelData; value: modelData; size: Style.space(56) }
          }
        }
      }
    }

    // generic list: compact layout, single-type filters and fallbacks
    ListView {
      id: catalogResultsList
      visible: !root.searchListLoading && !root.controller.suggestionsVisible
        && !root.wideAll && !root.wideEntity
      anchors.fill: parent
      anchors.leftMargin: root.pad
      anchors.rightMargin: root.pad
      anchors.topMargin: root.isSearch ? 0 : Style.space(14)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: Math.max(0, height * 2)
      model: root.rows
      spacing: Style.space(2)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: BorderSurface {
        id: catalogRow
        required property var modelData
        readonly property string rowKind: String(modelData.kind || "")
        readonly property var value: modelData.value || ({})
        readonly property bool actionable: ["track", "artist", "album", "playlist", "best",
          "loadSearch", "loadEntity", "loadRelease", "retrySearch", "retryEntity"].indexOf(rowKind) >= 0
        readonly property bool hovered: catalogHover.hovered
        width: catalogResultsList.width
          - (catalogResultsList.contentHeight > catalogResultsList.height ? Style.space(8) : 0)
        height: rowKind === "best" ? Style.space(64)
          : rowKind === "entityHeader" ? compactEntityHero.implicitHeight
          : (rowKind === "description" ? Math.max(Style.space(52), catalogText.implicitHeight + Style.space(18))
          : (rowKind === "section" ? Style.space(34)
          : (rowKind === "track" ? Style.space(52)
          : (rowKind === "artist" || rowKind === "album" || rowKind === "playlist"
            ? Style.space(56) : Style.space(42)))))
        radius: Style.cornerRadius
        color: actionable && catalogRow.hovered
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : (rowKind === "best" ? Style.normalFillFor(root.foreground, Color.accent) : "transparent")
        borderSpec: Border.none()

        HoverHandler { id: catalogHover }

        Item {
          visible: catalogRow.rowKind === "best"
          anchors.fill: parent
          RoundImage {
            id: bestAvatar
            visible: catalogRow.modelData.type === "artist"
            anchors.left: parent.left; anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44); height: width
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground; fontFamily: root.fontFamily
          }
          CatalogImage {
            visible: catalogRow.modelData.type !== "artist"
            anchors.left: parent.left; anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44); height: width
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground; fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            anchors.left: bestAvatar.right; anchors.leftMargin: Style.space(12)
            anchors.right: bestRadio.visible ? bestRadio.left : parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: String(catalogRow.value.name || catalogRow.value.title || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.title; font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: "Лучший результат · " + String(catalogRow.modelData.label || "").toLowerCase()
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }
          ActionButton {
            id: bestRadio
            visible: catalogRow.modelData.type === "artist"
            anchors.right: parent.right; anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            primary: true; height: Style.space(28)
            text: "Радио"; iconText: "󰐷"
            onClicked: root.controller.radioRequested("artist:" + String(catalogRow.value.id || ""),
              String(catalogRow.value.name || ""))
          }
        }

        Item {
          id: compactEntityHero
          visible: catalogRow.rowKind === "entityHeader"
          width: parent.width
          implicitHeight: Math.max(Style.space(72), entityMeta.implicitHeight)
            + (root.view === "artist" ? Style.space(39) : 0)
          height: implicitHeight
          CatalogImage {
            id: entityCover
            width: Style.space(72); height: width
            y: (Math.max(height, entityMeta.implicitHeight) - height) / 2
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground; fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            id: entityMeta
            anchors.left: entityCover.right; anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            spacing: Style.space(5)
            Text {
              textFormat: Text.PlainText
              text: root.view === "artist" ? "ИСПОЛНИТЕЛЬ" : root.view === "album" ? "АЛЬБОМ" : "ПЛЕЙЛИСТ"
              color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.space(9)
              font.letterSpacing: 1.2
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(catalogRow.value.title || catalogRow.value.name || "Каталог")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.space(17); font.bold: true
              wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Row {
              width: parent.width; spacing: 0
              Repeater {
                model: catalogRow.value.artists || []
                Text {
                  textFormat: Text.PlainText
                  id: entityArtistLink
                  required property var modelData
                  required property int index
                  text: modelData.name + (index < (catalogRow.value.artists || []).length - 1 ? ", " : "")
                  color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.space(10)
                  font.underline: entityArtistMouse.containsMouse
                  MouseArea {
                    id: entityArtistMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.artistRequested(entityArtistLink.modelData.id, String(entityArtistLink.modelData.name || ""))
                  }
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.view === "artist" ? "Популярные · Альбомы · Синглы"
                : [catalogRow.value.year || catalogRow.value.releaseDate, catalogRow.value.genre,
                  catalogRow.value.ownerName].filter(function(value) { return String(value || "") !== "" }).join(" · ")
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); elide: Text.ElideRight
            }
          }
          ActionButton {
            visible: root.view === "artist"
            y: Math.max(Style.space(72), entityMeta.implicitHeight) + Style.space(10)
            width: parent.width; height: Style.space(29)
            primary: true; text: "Радио"; iconText: "󰐷"
            onClicked: root.controller.radioRequested("artist:" + String(root.entity.id || ""),
              String(root.entity.name || root.entity.title || ""))
          }
        }

        Text {
          textFormat: Text.PlainText
          id: catalogText
          visible: ["section", "description", "error", "warning", "empty",
            "loadSearch", "loadEntity", "loadRelease", "retrySearch", "retryEntity"].indexOf(catalogRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: catalogRow.rowKind === "section" ? Style.space(3) : 0
          text: catalogRow.rowKind === "section"
            ? String(modelData.title || "") + (Number(modelData.count || 0) > 0 ? " · " + root.groupNumber(modelData.count) : "")
            : String(modelData.title || "")
          wrapMode: catalogRow.rowKind === "description" ? Text.WordWrap : Text.NoWrap
          elide: catalogRow.rowKind === "description" ? Text.ElideNone : Text.ElideRight
          horizontalAlignment: catalogRow.rowKind.indexOf("load") === 0
            || catalogRow.rowKind.indexOf("retry") === 0 ? Text.AlignHCenter : Text.AlignLeft
          color: catalogRow.rowKind === "error" ? Color.urgent
            : (catalogRow.rowKind.indexOf("load") === 0
              || catalogRow.rowKind.indexOf("retry") === 0 ? Color.accent : root.dim)
          font.family: root.fontFamily
          font.pixelSize: catalogRow.rowKind === "section" ? Style.font.caption : Style.font.bodySmall
          font.bold: catalogRow.rowKind === "section"
            || catalogRow.rowKind.indexOf("load") === 0
            || catalogRow.rowKind.indexOf("retry") === 0
          font.letterSpacing: catalogRow.rowKind === "section" ? 1.2 : 0
        }

        Row {
          z: 2
          visible: ["track", "artist", "album", "playlist"].indexOf(catalogRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(8); anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)
          RoundImage {
            visible: catalogRow.rowKind === "artist"
            width: visible ? Style.space(40) : 0; height: Style.space(40)
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground; fontFamily: root.fontFamily
          }
          CatalogImage {
            visible: catalogRow.rowKind !== "artist"
            width: visible ? (catalogRow.rowKind === "track" ? Style.space(36) : Style.space(40)) : 0
            height: width
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            width: parent.width - Style.space(52)
              - (catalogRow.rowKind === "track" ? Style.space(52) : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(catalogRow.value.title || catalogRow.value.name || "Без названия")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight
            }
            Row {
              width: parent.width; spacing: 0
              Repeater {
                model: catalogRow.value.artists || []
                Text {
                  textFormat: Text.PlainText
                  id: catalogArtistLink
                  required property var modelData
                  required property int index
                  text: modelData.name + (index < (catalogRow.value.artists || []).length - 1 ? ", " : "")
                  color: catalogArtistMouse.containsMouse ? Color.accent : root.dim
                  font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  MouseArea {
                    id: catalogArtistMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.artistRequested(catalogArtistLink.modelData.id, String(catalogArtistLink.modelData.name || ""))
                  }
                }
              }
              Text {
                textFormat: Text.PlainText
                id: catalogAlbumLink
                visible: catalogRow.rowKind === "track" && String(catalogRow.value.album || "") !== ""
                text: (catalogRow.value.artists || []).length > 0
                  ? " · " + String(catalogRow.value.album || "") : String(catalogRow.value.album || "")
                color: catalogAlbumMouse.containsMouse && String(catalogRow.value.albumId || "") !== ""
                  ? Color.accent : root.dim
                font.family: root.fontFamily; font.pixelSize: Style.font.caption
                MouseArea {
                  id: catalogAlbumMouse; anchors.fill: parent
                  enabled: String(catalogRow.value.albumId || "") !== ""
                  hoverEnabled: enabled
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.albumRequested(catalogRow.value.albumId, String(catalogRow.value.albumTitle || ""))
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: catalogRow.rowKind !== "track"
                  && (catalogRow.value.artists || []).length === 0
                text: String(catalogRow.value.artist || catalogRow.value.ownerName
                  || (catalogRow.value.genres || []).join(", ") || "")
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
          }
          Item {
            visible: catalogRow.rowKind === "track"
            width: visible ? Style.space(40) : 0; height: Style.space(26)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              visible: !catalogRow.hovered
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
              text: Number(catalogRow.value.duration || 0) > 0 ? root.formatDuration(catalogRow.value.duration) : ""
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            IconButton {
              id: catalogTrackAction
              visible: catalogRow.hovered
              width: Style.space(26); height: Style.space(26)
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              horizontalPadding: 0; verticalPadding: 0
              iconText: "󰐒"; iconSize: Style.font.icon
              tooltipText: "В плейлист…"
              foreground: hot ? Color.accent : root.dim
              onClicked: root.collectionTrackRequested(
                String(modelData.source || "search") === "entity"
                  ? "catalogEntity" : "catalogSearch",
                Number(catalogRow.value.index || 0), catalogRow.value, catalogTrackAction)
            }
          }
        }

        MouseArea {
          id: catalogMouse
          anchors.fill: parent
          anchors.rightMargin: catalogRow.rowKind === "track" ? Style.space(52) : 0
          enabled: catalogRow.actionable
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: catalogRow.rowKind === "best" ? root.openBest() : root.activateRow(modelData)
        }
      }
    }

    BorderSurface {
      z: 20
      visible: root.isSearch && root.controller.suggestionsVisible
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      height: visible ? Math.min(Style.space(152), suggestionList.contentHeight + Style.space(4)) : 0
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)
      ListView {
        id: suggestionList
        anchors.fill: parent; anchors.margins: Style.space(2)
        clip: true; model: root.controller.suggestions
        delegate: Item {
          required property var modelData
          required property int index
          width: suggestionList.width; height: Style.space(36)
          Rectangle {
            anchors.fill: parent
            color: index === root.controller.highlightedSuggestionIndex
              ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          }
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: Style.space(9); anchors.verticalCenter: parent.verticalCenter
            text: String(modelData); elide: Text.ElideRight
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onEntered: root.controller.highlightedSuggestionIndex = index
            onClicked: {
              searchField.text = String(modelData)
              root.controller.selectSuggestion(modelData)
            }
          }
        }
      }
    }
  }
}
