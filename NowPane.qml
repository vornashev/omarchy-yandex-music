import QtQuick
import qs.Commons
import qs.Ui

// Wide layout: cover, track details, transport and volume of the current track.
Item {
  id: root

  required property var panel
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property real inset: Style.space(28)
  readonly property real coverSize: Math.max(Style.space(120), Math.min(width - inset * 2,
    height - inset * 2 - Style.space(66 + 25 + 48 + 28 + 18 * 4)))
  readonly property alias volumeControl: volumeControl

  Column {
    anchors.fill: parent
    anchors.margins: root.inset
    spacing: Style.space(18)

    Rectangle {
      id: cover
      width: root.coverSize; height: width
      anchors.horizontalCenter: parent.horizontalCenter
      color: Style.selectedFillFor(root.fg, Color.accent)
      clip: true
      CatalogImage {
        anchors.fill: parent
        requestedSource: String(panel.data.artUrl || "")
        foreground: root.fg; fontFamily: root.ff
        fillMode: Image.PreserveAspectCrop
      }
      LucideIcon {
        visible: String(panel.data.artUrl || "") === ""
        anchors.centerIn: parent
        glyph: "󰝚"; color: root.dim
        fontFamily: root.ff; size: Style.font.displayLarge
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: panel.hasTrack ? String(panel.data.title) : "Яндекс Музыка"
        color: root.fg; font.family: root.ff
        font.pixelSize: Style.font.title + Style.space(6); font.bold: true
      }
      Item {
        visible: panel.hasTrack
        width: parent.width; height: visible ? Style.space(18) : 0; clip: true
        Row {
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            model: panel.data.artists || []
            Text {
              textFormat: Text.PlainText
              id: nowArtist
              required property var modelData
              required property int index
              text: modelData.name + (index < (panel.data.artists || []).length - 1 ? ", " : "")
              color: Color.accent
              font.family: root.ff; font.pixelSize: Style.font.subtitle
              font.underline: nowArtistMouse.containsMouse
              MouseArea {
                id: nowArtistMouse; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: panel.openCatalogArtist(nowArtist.modelData.id)
              }
            }
          }
        }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: panel.hasTrack ? String(panel.data.album || panel.data.queueName || "")
          : (panel.authenticated ? "Выберите музыку" : "Автономный плеер")
        color: nowAlbumMouse.containsMouse && String(panel.data.albumId || "") !== ""
          ? Color.accent : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
        MouseArea {
          id: nowAlbumMouse; anchors.fill: parent
          enabled: String(panel.data.albumId || "") !== ""
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: panel.openCatalogAlbum(panel.data.albumId)
        }
      }
    }

    SeekBar { width: parent.width; panel: root.panel }

    Item {
      width: parent.width; height: Style.space(48)
      IconButton {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32); height: Style.space(32)
        horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
        iconText: panel.data.liked ? "󰋑" : "󰋕"
        tooltipText: panel.data.liked ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
        foreground: panel.data.liked ? Color.accent : root.fg
        enabled: panel.hasTrack; opacity: enabled ? 1 : .4
        onClicked: panel.transport("toggleLike")
      }
      Row {
        anchors.centerIn: parent
        spacing: Style.space(14)
        IconButton {
          width: Style.space(32); height: Style.space(32); anchors.verticalCenter: parent.verticalCenter
          horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
          iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.fg
          enabled: panel.hasTrack; opacity: enabled ? 1 : .4
          onClicked: panel.transport("previousTrack")
        }
        PlayButton { size: Style.space(48); panel: root.panel }
        IconButton {
          width: Style.space(32); height: Style.space(32); anchors.verticalCenter: parent.verticalCenter
          horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
          iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.fg
          enabled: panel.hasTrack; opacity: enabled ? 1 : .4
          onClicked: panel.transport("nextTrack")
        }
      }
      IconButton {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32); height: Style.space(32)
        horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
        iconText: "󰇙"; tooltipText: "Действия и настройки"; foreground: root.fg
        onClicked: panel.openPlayerActions()
      }
    }

    VolumeControl {
      id: volumeControl
      width: parent.width
      volume: Number(panel.data.volume || 0)
      muted: panel.data.muted === true
      foreground: root.fg; dim: root.dim; fontFamily: root.ff
      onMuteRequested: panel.transport("toggleMute")
      onVolumeChangeRequested: function(value) { panel.queueVolume(value) }
    }
  }
}
