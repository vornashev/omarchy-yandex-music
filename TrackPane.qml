import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Очередь, текст и сведения разделяют одну область; browse живёт в CollectionPage.
Item {
  id: root

  required property var panel
  property bool wide: false
  readonly property alias queueList: queueList
  readonly property alias lyricsList: lyricsList
  readonly property alias infoFlick: infoFlick
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property color lineColor: Qt.rgba(fg.r, fg.g, fg.b, .08)
  readonly property real sideInset: wide ? Style.space(16) : Style.space(4)
  readonly property bool listVisible: !panel.currentTrackPaneOpen
  readonly property real headerBottom: contentArea.y

  readonly property var infoFacts: {
    var data = panel.trackInfoData || {}
    var facts = []
    function add(label, value) {
      var text = String(value === undefined || value === null ? "" : value).trim()
      if (text !== "") facts.push({ label: label, value: text })
    }
    var year = String(data.year || "").trim()
    if (year === "" && String(data.releaseDate || "") !== "")
      year = String(data.releaseDate).slice(0, 4)
    add("ГОД", year)
    add("ЖАНР", data.genre)
    if (Number(data.duration || 0) > 0) add("ДЛИТ.", panel.formatTime(data.duration))
    add("ЛЕЙБЛ", (data.labels || []).join(", "))
    return facts
  }
  readonly property var infoCredits: {
    var credits = (panel.trackInfoData || {}).credits || []
    var rows = []
    for (var i = 0; i < credits.length; i++) {
      var credit = credits[i] || {}
      var value = String(credit.value || "").trim()
      if (value !== "") rows.push({ label: String(credit.title || "Участник"), value: value })
    }
    return rows
  }

  function resetInfoScroll() { infoFlick.contentY = 0 }

  // ── tab strip ─────────────────────────────────────────────────────────
  Item {
    id: tabs
    visible: panel.hasTrack
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: visible ? (root.wide ? Style.space(35) : Style.space(45)) : 0

    Rectangle {
      visible: root.wide
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: root.sideInset; anchors.rightMargin: root.sideInset
      anchors.bottom: parent.bottom
      height: 1; color: root.lineColor
    }

    Row {
      anchors.left: parent.left; anchors.leftMargin: root.sideInset
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: root.wide ? 0 : -Style.space(1)
      spacing: root.wide ? Style.space(24) : Style.space(6)
      Repeater {
        model: [
          { label: root.wide ? "ОЧЕРЕДЬ" : "Очередь", pane: 0 },
          { label: root.wide ? "ТЕКСТ" : "Текст", pane: 1 },
          { label: root.wide ? "О ТРЕКЕ" : "О треке", pane: 2 }
        ]
        Item {
          id: tab
          required property var modelData
          readonly property bool selected: (modelData.pane === 0 && !panel.currentTrackPaneOpen)
            || (modelData.pane === 1 && panel.lyricsOpen)
            || (modelData.pane === 2 && panel.trackInfoOpen)
          width: tabLabel.implicitWidth + (root.wide ? 0 : Style.space(20))
          height: root.wide ? Style.space(35) : Style.space(25)

          Rectangle {
            visible: !root.wide
            anchors.fill: parent
            color: tab.selected ? Style.selectedFillFor(root.fg, Color.accent)
              : (tabMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
          }
          Text {
            id: tabLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.label
            color: tab.selected ? root.fg : root.dim
            font.family: root.ff
            font.pixelSize: root.wide ? Style.font.bodySmall : Style.font.bodySmall
            font.bold: tab.selected
            font.letterSpacing: root.wide ? 1 : 0
          }
          Rectangle {
            visible: root.wide
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: Style.space(2); color: Color.accent
            opacity: tab.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            id: tabMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: panel.selectCurrentTrackPane(tab.modelData.pane)
          }
        }
      }
    }

    Text {
      visible: !root.wide
      textFormat: Text.PlainText
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: root.countText()
      color: panel.lyricsOpen && panel.lyricsData.synced ? Color.accent : root.dim
      font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
  }

  function countText() {
    if (panel.trackInfoOpen) return panel.trackInfoLoading ? "…" : ""
    if (panel.lyricsOpen)
      return panel.lyricsLoading ? "…" : (panel.lyricsData.synced ? "LRC"
        : (panel.lyricsData.available ? "TEXT" : ""))
    var loaded = panel.queueDisplay.length
    var total = Number(panel.data.queueTotal === undefined ? -1 : panel.data.queueTotal)
    if (total > loaded) return loaded + (root.wide ? " / " : "/") + total
    if (loaded > 0) return String(loaded)
    return ""
  }

  // Источник очереди открывает коллекцию без изменения воспроизведения.
  Item {
    id: header
    readonly property bool shown: panel.hasTrack || panel.queueListLoading || panel.queueDisplay.length > 0
    visible: shown && !panel.currentTrackPaneOpen
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: tabs.bottom
    anchors.topMargin: visible ? Style.space(8) : 0
    height: visible ? Style.space(26) : 0

    Text {
      textFormat: Text.PlainText
      visible: !panel.queueListLoading
      anchors.left: parent.left
      anchors.leftMargin: root.sideInset + Style.space(12)
      anchors.right: countLabel.left; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: panel.data.queueSourceKind ? "Из: " + String(panel.data.queueSourceName || "") + " ↗" : "Очередь"
      elide: Text.ElideRight
      color: panel.data.queueSourceKind ? Color.accent : root.dim
      font.family: root.ff; font.pixelSize: Style.font.bodySmall
      MouseArea {
        anchors.fill: parent
        enabled: String(panel.data.queueSourceKind || "") !== ""
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.openQueueSource()
      }
    }
    Text {
      id: countLabel
      textFormat: Text.PlainText
      visible: root.wide && !panel.queueListLoading
      anchors.right: parent.right; anchors.rightMargin: root.sideInset + Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: root.countText()
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
    Rectangle {
      visible: panel.queueListLoading
      anchors.left: parent.left; anchors.leftMargin: root.sideInset + Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * .4; height: Style.space(7); radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .1)
    }
  }

  Item {
    id: contentArea
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: header.visible ? header.bottom : tabs.bottom
    anchors.topMargin: header.visible ? Style.space(4) : (root.wide ? 0 : Style.space(2))
    anchors.bottom: lyricsFooter.visible ? lyricsFooter.top : parent.bottom
    clip: true

    Text {
      textFormat: Text.PlainText
      visible: !panel.hasTrack && !panel.queueListLoading && panel.queueDisplay.length === 0
      anchors.centerIn: parent
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
      text: "Выберите плейлист в медиатеке или найдите трек"
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }

    SkeletonList {
      visible: root.listVisible && panel.queueListLoading
      anchors.fill: parent
      rowCount: 7
      foreground: root.fg
    }

    // Виртуализированная очередь, независимая от открытых коллекций.
    ListView {
      id: queueList
      objectName: "queueList"
      visible: root.listVisible && !panel.queueListLoading && panel.queueDisplay.length > 0
      anchors.fill: parent
      anchors.leftMargin: root.sideInset; anchors.rightMargin: root.sideInset
      clip: true
      model: panel.queueDisplay
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: Math.max(0, height)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: BorderSurface {
        id: queueRow
        required property var modelData
        readonly property bool isCurrent: Number(panel.data.queueIndex || 0) - 1 === Number(modelData.index)
        readonly property bool hovered: queueHover.hovered
        readonly property real coverSize: root.wide ? Style.space(36) : Style.space(32)
        width: queueList.width - (queueList.contentHeight > queueList.height ? Style.space(8) : 0)
        height: root.wide ? Style.space(52) : Style.space(48)
        radius: Style.cornerRadius
        color: isCurrent ? Style.selectedFillFor(root.fg, Color.accent)
          : (hovered ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
        borderSpec: Border.none()

        HoverHandler { id: queueHover }

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left; anchors.leftMargin: Style.space(6)
          width: Style.space(20); anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: queueRow.isCurrent ? "▶" : String(modelData.index + 1)
          color: queueRow.isCurrent ? Color.accent : root.dim
          font.family: root.ff; font.pixelSize: queueRow.isCurrent ? Style.font.caption : Style.font.bodySmall
        }
        CatalogImage {
          id: rowCover
          anchors.left: parent.left; anchors.leftMargin: Style.space(34)
          anchors.verticalCenter: parent.verticalCenter
          width: queueRow.coverSize; height: width
          requestedSource: String(modelData.artUrl || "")
          foreground: root.fg; fontFamily: root.ff
          fillMode: Image.PreserveAspectCrop
        }
        Column {
          z: 1
          anchors.left: rowCover.right; anchors.leftMargin: Style.space(12)
          anchors.right: durationSlot.left; anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            width: parent.width; text: modelData.title; elide: Text.ElideRight
            color: queueRow.isCurrent ? Color.accent : root.fg; font.family: root.ff
            font.pixelSize: Style.font.body; font.bold: true
          }
          Item {
            width: parent.width; height: Style.space(14); clip: true
            Row {
              anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
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
                  font.family: root.ff; font.pixelSize: Style.font.caption
                  MouseArea {
                    id: queueArtistMouse; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openCatalogArtist(queueArtistLink.modelData.id)
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
                font.family: root.ff; font.pixelSize: Style.font.caption
                MouseArea {
                  id: queueAlbumMouse; anchors.fill: parent
                  enabled: String(queueRow.modelData.albumId || "") !== ""
                  hoverEnabled: enabled
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: panel.openCatalogAlbum(queueRow.modelData.albumId)
                }
              }
            }
          }
        }
        Item {
          id: durationSlot
          z: 2
          anchors.right: parent.right; anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40); height: Style.space(26)
          Text {
            textFormat: Text.PlainText
            visible: !queueRow.hovered
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
            text: panel.formatTime(modelData.duration)
            color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
          }
          IconButton {
            id: queueTrackAction
            visible: queueRow.hovered
            width: Style.space(26); height: Style.space(26)
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            horizontalPadding: 0; verticalPadding: 0
            iconText: "󰐒"
            iconSize: Style.font.icon
            tooltipText: "В плейлист…"
            foreground: hot ? Color.accent : root.dim
            onClicked: panel.openCollectionTrack(
              "queue", Number(modelData.index), modelData, false, "", "", queueTrackAction)
          }
        }
        MouseArea {
          anchors.fill: parent
          anchors.rightMargin: Style.space(52)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!queueRow.isCurrent) panel.transport("playQueueTrack", modelData.index)
          }
        }
      }

    }

    // ── lyrics ──────────────────────────────────────────────────────────
    SkeletonList {
      visible: panel.lyricsOpen && panel.lyricsLoading
      anchors.fill: parent
      rowCount: 6
      foreground: root.fg
    }
    Column {
      visible: panel.lyricsOpen && !panel.lyricsLoading
        && (!panel.lyricsData.available || panel.lyricsLines.length === 0)
      anchors.centerIn: parent
      width: parent.width - Style.space(32)
      spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: String(panel.lyricsData.error || "") !== ""
          ? String(panel.lyricsData.error) : "Текст этой песни недоступен"
        color: String(panel.lyricsData.error || "") !== "" ? Color.urgent : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
      }
      IconButton {
        visible: String(panel.lyricsData.error || "") !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Повторить"; iconText: "󰑐"; bordered: true
        foreground: root.fg
        enabled: !panel.lyricsRefreshing
        onClicked: panel.refreshLyrics(true)
      }
    }
    ListView {
      id: lyricsList
      visible: panel.lyricsOpen && !panel.lyricsLoading
        && panel.lyricsData.available && panel.lyricsLines.length > 0
      anchors.fill: parent
      anchors.topMargin: Style.space(10)
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: root.wide ? Style.space(16) : Style.space(16)
      clip: true
      model: panel.lyricsLines
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: Math.max(0, height)
      spacing: root.wide ? Style.space(6) : Style.space(4)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      onMovementStarted: panel.pauseLyricsAutoScroll()
      onMovementEnded: panel.resumeLyricsAutoScrollLater()

      delegate: Item {
        id: lyricRow
        required property var modelData
        required property int index
        readonly property bool isCurrent: index === panel.lyricsCurrentIndex
        readonly property bool canSeek: panel.lyricsData.synced && Number(modelData.time) >= 0
        readonly property int distance: panel.lyricsCurrentIndex < 0 ? 0
          : Math.abs(index - panel.lyricsCurrentIndex)
        width: lyricsList.width - (lyricsList.contentHeight > lyricsList.height ? Style.space(8) : 0)
        height: String(modelData.text || "") === "" ? Style.space(14)
          : Math.max(Style.space(28), lyricText.implicitHeight + Style.space(10))
        Text {
          id: lyricText
          textFormat: Text.PlainText
          anchors.left: parent.left; anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: String(lyricRow.modelData.text || "")
          wrapMode: Text.WordWrap
          color: lyricRow.isCurrent ? Color.accent : root.fg
          opacity: !panel.lyricsData.synced || lyricRow.isCurrent ? 1
            : (lyricRow.distance <= 1 ? .9 : (lyricRow.distance <= 3 ? .6 : .35))
          font.family: root.ff
          font.pixelSize: lyricRow.isCurrent ? Style.font.subtitle + Style.space(root.wide ? 3 : 2)
            : Style.font.subtitle
          font.bold: lyricRow.isCurrent
          Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        MouseArea {
          anchors.fill: parent
          enabled: lyricRow.canSeek
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: panel.seekToLyric(lyricRow.modelData.time)
        }
      }
      footer: Text {
        textFormat: Text.PlainText
        width: lyricsList.width
        height: visible ? contentHeight + Style.space(20) : 0
        visible: (panel.lyricsData.writers || []).length > 0
        topPadding: Style.space(10)
        wrapMode: Text.WordWrap
        text: "Авторы текста: " + (panel.lyricsData.writers || []).join(", ")
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }

    // ── track info ──────────────────────────────────────────────────────
    SkeletonList {
      visible: panel.trackInfoOpen && panel.trackInfoLoading
      anchors.fill: parent
      rowCount: 6
      foreground: root.fg
    }
    Column {
      visible: panel.trackInfoOpen && !panel.trackInfoLoading && panel.trackInfoRows.length === 0
      anchors.centerIn: parent
      width: parent.width - Style.space(32)
      spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: String(panel.trackInfoData.error || "") !== ""
          ? String(panel.trackInfoData.error) : "Подробные сведения недоступны"
        color: String(panel.trackInfoData.error || "") !== "" ? Color.urgent : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
      }
      IconButton {
        visible: String(panel.trackInfoData.error || "") !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Повторить"; iconText: "󰑐"; bordered: true
        foreground: root.fg
        enabled: !panel.trackInfoRefreshing
        onClicked: panel.refreshTrackInfo(true)
      }
    }
    Flickable {
      id: infoFlick
      visible: panel.trackInfoOpen && !panel.trackInfoLoading && panel.trackInfoRows.length > 0
      anchors.fill: parent
      anchors.topMargin: Style.space(10)
      anchors.leftMargin: Style.space(16); anchors.rightMargin: Style.space(16)
      contentWidth: width
      contentHeight: infoColumn.implicitHeight + Style.space(12)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: infoColumn
        width: infoFlick.width - (infoFlick.contentHeight > infoFlick.height ? Style.space(8) : 0)
        spacing: Style.space(12)

        Row {
          visible: root.infoFacts.length > 0
          width: parent.width
          Repeater {
            model: root.infoFacts
            Item {
              id: fact
              required property var modelData
              required property int index
              width: infoColumn.width / root.infoFacts.length
              height: Style.space(52)
              Rectangle {
                visible: fact.index > 0
                width: 1; height: parent.height; color: root.lineColor
              }
              Column {
                anchors.fill: parent; anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                topPadding: Style.space(10)
                Text {
                  textFormat: Text.PlainText
                  text: fact.modelData.label; color: root.dim
                  font.family: root.ff; font.pixelSize: Style.font.caption
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width; elide: Text.ElideRight
                  text: fact.modelData.value; color: root.fg
                  font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true
                }
              }
            }
          }
        }

        Rectangle {
          visible: String(panel.trackInfoData.album || "") !== ""
          width: parent.width; height: Style.space(56)
          color: albumMouse.containsMouse && String(panel.trackInfoData.albumId || "") !== ""
            ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
          CatalogImage {
            id: infoCover
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44); height: width
            requestedSource: String(panel.data.artUrl || "")
            foreground: root.fg; fontFamily: root.ff
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            anchors.left: infoCover.right; anchors.leftMargin: Style.space(12)
            anchors.right: albumArrow.left; anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: String(panel.trackInfoData.album || "")
              color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width; elide: Text.ElideRight
              text: Number(panel.trackInfoData.trackNumber || 0) > 0
                ? "Трек " + Number(panel.trackInfoData.trackNumber)
                  + (Number(panel.trackInfoData.discNumber || 0) > 1
                    ? " · диск " + Number(panel.trackInfoData.discNumber) : "")
                : "Альбом"
              color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
            }
          }
          LucideIcon {
            id: albumArrow
            visible: String(panel.trackInfoData.albumId || "") !== ""
            anchors.right: parent.right; anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰁜"; color: root.dim
            fontFamily: root.ff; size: Style.font.body
          }
          MouseArea {
            id: albumMouse
            anchors.fill: parent
            enabled: String(panel.trackInfoData.albumId || "") !== ""
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.openCatalogAlbum(panel.trackInfoData.albumId)
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.infoCredits.length > 0
          text: "УЧАСТНИКИ"; color: root.dim
          font.family: root.ff; font.pixelSize: Style.font.caption
          font.bold: true; font.letterSpacing: 1
        }
        Column {
          visible: root.infoCredits.length > 0
          width: parent.width
          Repeater {
            model: root.infoCredits
            Item {
              id: creditRow
              required property var modelData
              width: infoColumn.width
              height: Math.max(Style.space(33), creditValue.implicitHeight + Style.space(14))
              Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: root.lineColor
              }
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: Style.space(root.wide ? 140 : 110); elide: Text.ElideRight
                text: creditRow.modelData.label; color: root.dim
                font.family: root.ff; font.pixelSize: Style.font.bodySmall
              }
              Text {
                id: creditValue
                textFormat: Text.PlainText
                anchors.left: parent.left; anchors.leftMargin: Style.space(root.wide ? 140 : 110)
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: creditRow.modelData.value; color: root.fg
                font.family: root.ff; font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: String(panel.trackInfoData.description || "").trim() !== ""
          width: parent.width; wrapMode: Text.WordWrap
          lineHeight: 1.3
          text: String(panel.trackInfoData.description || "").trim()
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
        }

        Column {
          visible: String(panel.trackInfoData.error || "") !== ""
          width: parent.width; spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: String(panel.trackInfoData.error || "")
            color: Color.urgent; font.family: root.ff; font.pixelSize: Style.font.caption
          }
          IconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Повторить"; iconText: "󰑐"; bordered: true
            foreground: root.fg
            enabled: !panel.trackInfoRefreshing
            onClicked: panel.refreshTrackInfo(true)
          }
        }
      }
    }
  }

  Item {
    id: lyricsFooter
    visible: root.wide && panel.lyricsOpen && !panel.lyricsLoading
      && panel.lyricsData.available && panel.lyricsLines.length > 0
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: visible ? Style.space(34) : 0
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left; anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: panel.lyricsData.synced ? "LRC · синхронизировано" : "Текст без синхронизации"
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
    }
    Text {
      textFormat: Text.PlainText
      visible: panel.lyricsData.synced
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: "клик по строке — перемотка"
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
    }
  }
}
