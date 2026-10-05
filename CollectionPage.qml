import QtQuick
import QtQuick.Controls
import qs.Commons

// Коллекция никогда не подменяет очередь до явного выбора трека или кнопки.
Item {
  id: root
  required property var panel
  property bool wide: false
  readonly property var snapshot: panel.browseDisplay || ({})
  readonly property var tracks: panel.libraryDisplay || []
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property real scrollY: list.contentY
  property real pendingScroll: 0
  property bool restoringViewport: false
  signal artistRequested(string id, string name)
  signal albumRequested(string id, string title)
  signal collectionTrackRequested(int index, var value, var anchor)

  function preserveViewport(y) {
    pendingScroll = Math.max(0, Number(y || 0))
    restoringViewport = true
    restoreTimer.restart()
  }
  function loadMore() {
    if (visible && !restoringViewport && !panel.busy && snapshot.libraryHasMore === true
        && snapshot.libraryLoadingMore !== true && !snapshot.libraryError
        && list.contentY + list.height >= list.contentHeight - Style.space(100))
      panel.intent("loadMoreLibraryTracks")
  }
  function metadataText() {
    var total = Number(snapshot.libraryTotal === undefined ? -1 : snapshot.libraryTotal)
    var duration = Number(snapshot.libraryDuration === undefined ? -1 : snapshot.libraryDuration)
    var text = total >= 0 ? total + " треков" : ""
    if (duration >= 0) text += (text ? " · " : "") + Math.floor(duration / 3600)
      + " ч " + Math.floor(duration % 3600 / 60) + " мин"
    return text
  }
  Timer {
    id: restoreTimer; interval: 0
    onTriggered: {
      list.contentY = Math.min(root.pendingScroll, Math.max(0, list.contentHeight - list.height))
      root.restoringViewport = false
    }
  }

  Item {
    id: hero
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    anchors.leftMargin: Style.space(root.wide ? 28 : 16)
    anchors.rightMargin: Style.space(root.wide ? 28 : 16)
    anchors.topMargin: Style.space(root.wide ? 0 : 14)
    height: Style.space(root.wide ? 119 : 72)
    Rectangle {
      id: cover
      width: Style.space(root.wide ? 112 : 72); height: width
      anchors.verticalCenter: parent.verticalCenter
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.lighter(Color.accent, 1.25) }
        GradientStop { position: 1; color: Qt.darker(Color.accent, 1.3) }
      }
      CatalogImage {
        anchors.fill: parent
        visible: String(root.snapshot.libraryArtUrl || "") !== ""
        requestedSource: String(root.snapshot.libraryArtUrl || "")
        foreground: root.fg; fontFamily: root.ff
        fillMode: Image.PreserveAspectCrop
      }
      LucideIcon {
        anchors.centerIn: parent
        visible: String(root.snapshot.libraryArtUrl || "") === ""
        name: root.snapshot.libraryBrowseKind === "likes" ? "heart" : "list-music"
        color: root.fg; size: Style.space(root.wide ? 36 : 28)
      }
    }
    Column {
      anchors.left: cover.right; anchors.leftMargin: Style.space(root.wide ? 20 : 14)
      anchors.right: parent.right
      y: root.wide ? 0 : (parent.height - height) / 2
      spacing: Style.space(root.wide ? 8 : 5)
      Text {
        textFormat: Text.PlainText
        text: "ПЛЕЙЛИСТ"; color: Color.accent
        font.family: root.ff; font.pixelSize: Style.space(root.wide ? 10 : 9); font.letterSpacing: 1.5
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: String(root.snapshot.libraryBrowseName || (root.snapshot.libraryBrowseKind === "likes" ? "Мне нравится" : "Коллекция"))
        color: root.fg; font.family: root.ff; font.pixelSize: Style.space(root.wide ? 26 : 17); font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: root.metadataText(); color: root.dim
        font.family: root.ff; font.pixelSize: Style.space(root.wide ? 11 : 10)
      }
    }
  }

  Row {
    id: buttons
    x: root.wide ? hero.x + cover.width + Style.space(20) : hero.x
    y: root.wide ? hero.y + Style.space(90) : hero.y + hero.height + Style.space(10)
    spacing: Style.space(8)
    height: Style.space(29)
    Repeater {
      model: [{ label: "Слушать", icon: "play", mode: "order" },
              { label: "Перемешать", icon: "shuffle", mode: "shuffle" }]
      Rectangle {
        id: playAction
        required property var modelData
        width: root.wide ? Style.space(modelData.mode === "order" ? 96 : 103) : (hero.width - buttons.spacing) / 2
        height: buttons.height
        color: modelData.mode === "order" ? Color.accent : "transparent"
        border.width: modelData.mode === "order" ? 0 : 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .12)
        opacity: playMouse.enabled ? 1 : .45
        Row {
          anchors.centerIn: parent; spacing: Style.space(5)
          LucideIcon {
            name: playAction.modelData.icon; size: Style.space(12)
            color: playAction.modelData.mode === "order" ? Color.background : root.fg
          }
          Text {
            textFormat: Text.PlainText
            text: playAction.modelData.label
            color: playAction.modelData.mode === "order" ? Color.background : root.fg
            font.family: root.ff; font.pixelSize: Style.space(11)
          }
        }
        MouseArea {
          id: playMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          enabled: !panel.busy && root.snapshot.libraryLoading !== true && root.tracks.length > 0
          onClicked: panel.transport("playLibraryCollection", playAction.modelData.mode)
        }
      }
    }
  }

  ListView {
    id: list
    anchors.left: hero.left; anchors.right: hero.right
    anchors.top: root.wide ? hero.bottom : buttons.bottom
    anchors.topMargin: Style.space(root.wide ? 18 : 10)
    anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(14)
    clip: true; boundsBehavior: Flickable.StopAtBounds
    model: root.tracks
    cacheBuffer: Math.max(0, height)
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    onContentYChanged: root.loadMore()
    onMovementEnded: root.loadMore()
    delegate: Rectangle {
      id: row
      required property var modelData
      width: list.width; height: Style.space(root.wide ? 48 : 44)
      color: hover.hovered ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
      HoverHandler { id: hover }
      MouseArea {
        anchors.fill: parent; anchors.rightMargin: Style.space(42)
        enabled: !panel.busy; cursorShape: Qt.PointingHandCursor
        onClicked: panel.transport("playLibraryTrack", Number(row.modelData.index))
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left; width: Style.space(22); anchors.verticalCenter: parent.verticalCenter
        text: Number(row.modelData.index) + 1; horizontalAlignment: Text.AlignHCenter
        color: root.dim; font.family: root.ff; font.pixelSize: Style.space(10)
      }
      CatalogImage {
        id: rowCover
        anchors.left: parent.left; anchors.leftMargin: Style.space(30); anchors.verticalCenter: parent.verticalCenter
        width: Style.space(root.wide ? 36 : 32); height: width
        requestedSource: String(row.modelData.artUrl || "")
        foreground: root.fg; fontFamily: root.ff; fillMode: Image.PreserveAspectCrop
      }
      Column {
        anchors.left: rowCover.right; anchors.leftMargin: Style.space(12)
        anchors.right: actionSlot.left; anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: String(row.modelData.title || ""); color: root.fg
          font.family: root.ff; font.pixelSize: Style.space(12)
        }
        Item {
          width: parent.width; height: Style.space(14); clip: true
          Row {
            Repeater {
              model: row.modelData.artists || []
              Text {
                id: artistLink
                required property var modelData
                required property int index
                textFormat: Text.PlainText
                text: String(modelData.name || "") + (index < (row.modelData.artists || []).length - 1 ? ", " : "")
                color: artistMouse.containsMouse ? Color.accent : root.dim
                font.family: root.ff; font.pixelSize: Style.space(10)
                MouseArea {
                  id: artistMouse; anchors.fill: parent; hoverEnabled: true
                  enabled: String(artistLink.modelData.id || "") !== ""
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.artistRequested(String(artistLink.modelData.id), String(artistLink.modelData.name || ""))
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              visible: String(row.modelData.album || "") !== ""
              text: " · " + String(row.modelData.album || "")
              color: albumMouse.containsMouse ? Color.accent : root.dim
              font.family: root.ff; font.pixelSize: Style.space(10)
              MouseArea {
                id: albumMouse; anchors.fill: parent; hoverEnabled: true
                enabled: String(row.modelData.albumId || "") !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: root.albumRequested(String(row.modelData.albumId), String(row.modelData.album || ""))
              }
            }
          }
        }
      }
      Item {
        id: actionSlot
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40); height: Style.space(28)
        Text {
          textFormat: Text.PlainText
          visible: !hover.hovered; anchors.centerIn: parent
          text: panel.formatTime(row.modelData.duration)
          color: root.dim; font.family: root.ff; font.pixelSize: Style.space(10)
        }
        IconButton {
          id: trackAction
          anchors.fill: parent; visible: hover.hovered; enabled: !panel.busy
          horizontalPadding: 0; verticalPadding: 0
          iconText: root.snapshot.libraryEditable === true ? "󰇘" : "󰐒"
          foreground: root.dim; iconSize: Style.space(16); tooltipText: "В плейлист…"
          onClicked: root.collectionTrackRequested(Number(row.modelData.index), row.modelData, trackAction)
        }
      }
    }
    footer: Text {
      textFormat: Text.PlainText
      width: list.width; height: visible ? Style.space(32) : 0
      visible: root.snapshot.libraryLoadingMore === true
      text: "Загружаем ещё…"; color: root.dim
      font.family: root.ff; font.pixelSize: Style.space(11); horizontalAlignment: Text.AlignHCenter
    }
  }
  SkeletonList {
    visible: root.snapshot.libraryLoading === true && root.tracks.length === 0
    anchors.fill: list; foreground: root.fg; rowCount: 7
  }
  Text {
    textFormat: Text.PlainText
    visible: root.snapshot.libraryLoading !== true && (root.tracks.length === 0 || !!root.snapshot.libraryError)
    anchors.centerIn: list; width: list.width; wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    text: String(root.snapshot.libraryError || "Плейлист пока пуст")
    color: root.dim; font.family: root.ff; font.pixelSize: Style.space(12)
  }
}
