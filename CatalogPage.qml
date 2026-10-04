import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
  id: root
  spacing: Style.space(6)
  required property var controller
  required property var snapshot
  property color foreground: "white"
  property color dim: "gray"
  property string fontFamily: ""
  property bool returnToLibrary: false
  property bool hasVisibleError: false
  property real errorCardHeight: 0
  property var focusTarget: null
  readonly property bool searchActiveFocus: searchField.activeFocus
  readonly property real viewportY: catalogResultsList.contentY
  readonly property bool searchListLoading: snapshot.search.loading === true
    || snapshot.entity.loading === true
  readonly property var rows: buildCatalogRows()

  signal artistRequested(string id)
  signal albumRequested(string id)
  signal playlistRequested(var value)
  signal collectionTrackRequested(string source, int index, var value)
  signal entityMoreRequested()
  signal retryEntityRequested(var entity)

  function setSearchText(value) { searchField.text = String(value || "") }
  function focusSearch() { searchField.forceActiveFocus() }
  function clearSearchFocus() { searchField.focus = false }
  function scrollToBeginning() { catalogResultsList.positionViewAtBeginning() }
  function resetViewport() { catalogResultsList.contentY = 0 }
  function restoreViewport(y) { catalogResultsList.contentY = y }
  function preserveViewport(y) {
    catalogResultsList.contentY = Math.min(y,
      Math.max(0, catalogResultsList.contentHeight - catalogResultsList.height))
  }

  function activateRow(row) {
    var value = row.value || {}
    if (row.kind === "track")
      root.controller.trackPlaybackRequested(String(row.source || "search"), Number(value.index || 0))
    else if (row.kind === "artist") root.artistRequested(value.id)
    else if (row.kind === "album") root.albumRequested(value.id)
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
    if (String(entity.description || "") !== "")
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

  Row {
    visible: String(root.snapshot.view || "search") === "search"
    width: parent.width
    height: visible ? Style.space(36) : 0
    spacing: Style.space(8)
    TextField {
      id: searchField
      width: parent.width - searchButton.width - parent.spacing
      placeholderText: "Трек, исполнитель, альбом или плейлист"
      foreground: root.foreground
      font.family: root.fontFamily
      rightPadding: Style.space(34)
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
      }
      Text {
        z: 2
        visible: root.controller.suggestionLoading
        anchors.right: parent.right
        anchors.rightMargin: Style.space(9)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰦖"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        RotationAnimator on rotation {
          running: root.controller.suggestionLoading
          from: 0; to: 360
          duration: 800
          loops: Animation.Infinite
        }
      }
    }
    Button {
      id: searchButton
      iconText: "󰍉"; tooltipText: "Найти"; foreground: root.foreground
      onClicked: root.controller.submit()
    }
  }

  Row {
    visible: String(root.snapshot.view || "search") === "search"
    width: parent.width
    height: visible ? Style.space(34) : 0
    spacing: Style.space(4)
    Repeater {
      model: [
        { value: "all", label: "Все" }, { value: "track", label: "Треки" },
        { value: "artist", label: "Артисты" }, { value: "album", label: "Альбомы" },
        { value: "playlist", label: "Плейлисты" }
      ]
      Button {
        required property var modelData
        width: (parent.width - Style.space(16)) / 5
        height: Style.space(32)
        text: modelData.label
        foreground: root.controller.filter === modelData.value ? Color.accent : root.dim
        bordered: root.controller.filter === modelData.value
        onClicked: {
          root.controller.filter = modelData.value
          if (root.controller.trimmedText() !== "") root.controller.submit()
        }
      }
    }
  }

  Item {
    visible: String(root.snapshot.view || "search") !== "search"
    width: parent.width
    height: visible ? Style.space(34) : 0
    Button {
      anchors.left: parent.left
      height: parent.height
      text: root.returnToLibrary ? "Назад в медиатеку" : "Назад к поиску"
      iconText: "󰁍"
      foreground: root.foreground
      bordered: true
      onClicked: root.controller.back()
    }
  }

  Item {
    id: searchResultsViewport
    width: parent.width
    height: Math.max(Style.space(240), Style.space(424)
      - (root.hasVisibleError ? root.errorCardHeight + Style.space(12) : 0))
    clip: true

    SkeletonList {
      visible: root.searchListLoading
      anchors.fill: parent
      rowCount: 8
      foreground: root.foreground
    }

    ListView {
      id: catalogResultsList
      visible: !root.searchListLoading && !root.controller.suggestionsVisible
      anchors.fill: parent
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: height * 2
      model: root.rows
      spacing: Style.space(2)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: BorderSurface {
        id: catalogRow
        required property var modelData
        readonly property string rowKind: String(modelData.kind || "")
        readonly property var value: modelData.value || ({})
        readonly property bool actionable: ["track", "artist", "album", "playlist",
          "loadSearch", "loadEntity", "loadRelease", "retrySearch", "retryEntity"].indexOf(rowKind) >= 0
        readonly property bool hovered: catalogHover.hovered
        width: catalogResultsList.width
          - (catalogResultsList.contentHeight > catalogResultsList.height ? Style.space(8) : 0)
        height: rowKind === "entityHeader" ? Style.space(112)
          : (rowKind === "description" ? Math.max(Style.space(52), catalogText.implicitHeight + Style.space(18))
          : (rowKind === "section" ? Style.space(30)
          : (rowKind === "track" || rowKind === "artist" || rowKind === "album" || rowKind === "playlist"
            ? Style.space(58) : Style.space(42))))
        radius: Style.cornerRadius
        color: actionable && catalogRow.hovered
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : (rowKind === "entityHeader" ? Style.normalFillFor(root.foreground, Color.accent) : "transparent")
        borderSpec: rowKind === "entityHeader"
          ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none()

        HoverHandler { id: catalogHover }

        Row {
          visible: catalogRow.rowKind === "entityHeader"
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)
          CatalogImage {
            width: Style.space(88); height: width
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            width: parent.width - Style.space(98)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(catalogRow.value.title || catalogRow.value.name || "Каталог")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle; font.bold: true; elide: Text.ElideRight
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
                  color: entityArtistMouse.containsMouse ? Color.accent : root.dim
                  font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    id: entityArtistMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.artistRequested(entityArtistLink.modelData.id)
                  }
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: [catalogRow.value.year || catalogRow.value.releaseDate,
                catalogRow.value.genre, catalogRow.value.ownerName].filter(function(value) {
                  return String(value || "") !== ""
                }).join(" · ")
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.caption; elide: Text.ElideRight
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          id: catalogText
          visible: ["section", "description", "error", "warning", "empty",
            "loadSearch", "loadEntity", "loadRelease", "retrySearch", "retryEntity"].indexOf(catalogRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter
          text: catalogRow.rowKind === "section"
            ? String(modelData.title || "") + (Number(modelData.count || 0) > 0 ? " · " + modelData.count : "")
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
          font.letterSpacing: catalogRow.rowKind === "section" ? .8 : 0
        }

        Row {
          z: 2
          visible: ["track", "artist", "album", "playlist"].indexOf(catalogRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(9); anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(9)
          CatalogImage {
            width: Style.space(40); height: width
            requestedSource: String(catalogRow.value.artUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            width: parent.width - Style.space(49)
              - (catalogRow.rowKind === "track" ? Style.space(35) : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(catalogRow.value.title || catalogRow.value.name || "Без названия")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
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
                    onClicked: root.artistRequested(catalogArtistLink.modelData.id)
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
                  onClicked: root.albumRequested(catalogRow.value.albumId)
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
          Button {
            visible: catalogRow.rowKind === "track" && catalogRow.hovered
            width: catalogRow.rowKind === "track" ? Style.space(26) : 0
            height: Style.space(26)
            anchors.verticalCenter: parent.verticalCenter
            horizontalPadding: 0; verticalPadding: 0
            iconText: "󰐒"; iconSize: Style.font.icon
            tooltipText: "Добавить в плейлист"
            foreground: root.dim
            onClicked: root.collectionTrackRequested(
              String(modelData.source || "search") === "entity"
                ? "catalogEntity" : "catalogSearch",
              Number(catalogRow.value.index || 0), catalogRow.value)
          }
        }

        MouseArea {
          id: catalogMouse
          anchors.fill: parent
          anchors.rightMargin: catalogRow.rowKind === "track" ? Style.space(36) : 0
          enabled: catalogRow.actionable
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activateRow(modelData)
        }
      }
    }

    BorderSurface {
      z: 20
      visible: String(root.snapshot.view || "search") === "search"
        && root.controller.suggestionsVisible
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      height: visible ? Math.min(Style.space(152), suggestionList.contentHeight + Style.space(4)) : 0
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
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
  Item { width: 1; height: Style.space(8) }
}
