import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Compact layout "Now" header: 72 px hero and one-line transport.
Item {
  id: root

  required property var panel
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property alias volumeControl: volumeControl

  implicitHeight: Style.space(150)

  Item {
    id: hero
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: Style.space(100)

    Rectangle {
      id: cover
      anchors.left: parent.left; anchors.leftMargin: Style.space(16)
      anchors.top: parent.top; anchors.topMargin: Style.space(16)
      width: Style.space(72); height: width
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
      anchors.left: cover.right; anchors.leftMargin: Style.space(14)
      anchors.right: likeButton.left; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(4)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: panel.hasTrack ? String(panel.data.title) : "Яндекс Музыка"
        color: root.fg; font.family: root.ff
        font.pixelSize: Style.font.title + Style.space(2); font.bold: true
      }
      Item {
        visible: panel.hasTrack
        width: parent.width; height: visible ? Style.space(16) : 0; clip: true
        Row {
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            model: panel.data.artists || []
            Text {
              textFormat: Text.PlainText
              id: heroArtist
              required property var modelData
              required property int index
              text: modelData.name + (index < (panel.data.artists || []).length - 1 ? ", " : "")
              color: Color.accent
              font.family: root.ff; font.pixelSize: Style.font.bodySmall + Style.space(1)
              font.underline: heroArtistMouse.containsMouse
              MouseArea {
                id: heroArtistMouse; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: panel.openCatalogArtist(heroArtist.modelData.id)
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
        color: heroAlbumMouse.containsMouse && String(panel.data.albumId || "") !== ""
          ? Color.accent : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
        MouseArea {
          id: heroAlbumMouse; anchors.fill: parent
          enabled: String(panel.data.albumId || "") !== ""
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: panel.openCatalogAlbum(panel.data.albumId)
        }
      }
    }
    IconButton {
      id: likeButton
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: cover.verticalCenter
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
      iconText: panel.data.liked ? "󰋑" : "󰋕"
      tooltipText: panel.data.liked ? "Убрать из «Мне нравится» (L)" : "Добавить в «Мне нравится» (L)"
      foreground: panel.data.liked ? Color.accent : root.fg
      enabled: panel.hasTrack; opacity: enabled ? 1 : .4
      onClicked: panel.transport("toggleLike")
    }
  }

  Item {
    id: controls
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: hero.bottom; anchors.bottom: parent.bottom
    IconButton {
      id: prevButton
      anchors.left: parent.left; anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
      iconText: "󰒮"; tooltipText: "Предыдущий (P)"; foreground: root.fg
      enabled: panel.hasTrack; opacity: enabled ? 1 : .4
      onClicked: panel.transport("previousTrack")
    }
    PlayButton {
      id: playButton
      anchors.left: prevButton.right; anchors.leftMargin: Style.space(10)
      size: Style.space(36); panel: root.panel
    }
    IconButton {
      id: nextButton
      anchors.left: playButton.right; anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
      iconText: "󰒭"; tooltipText: "Следующий (N)"; foreground: root.fg
      enabled: panel.hasTrack; opacity: enabled ? 1 : .4
      onClicked: panel.transport("nextTrack")
    }
    IconButton {
      id: moreButton
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
      iconText: "󰇙"; tooltipText: "Действия и настройки"; foreground: root.fg
      onClicked: panel.openPlayerActions()
    }
    IconButton {
      id: volumeButton
      anchors.right: moreButton.left; anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(32); height: Style.space(32)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.space(18)
      iconText: panel.data.muted === true ? "󰖁" : "󰕾"
      tooltipText: "Громкость " + Math.round(Number(panel.data.volume || 0)) + "%"
      foreground: panel.data.muted === true ? root.dim : root.fg
      selected: volumePopup.opened
      onClicked: volumePopup.opened ? volumePopup.close() : volumePopup.open()

      Popup {
        id: volumePopup
        x: parent.width - width
        y: -height - Style.space(6)
        width: Style.space(220); padding: Style.space(8)
        focus: false
        background: BorderSurface {
          color: Color.popups.background
          radius: Style.cornerRadius
          borderSpec: Border.controlSpec("focus", root.fg, Color.accent)
        }
        contentItem: VolumeControl {
          id: volumeControl
          volume: Number(panel.data.volume || 0)
          muted: panel.data.muted === true
          foreground: root.fg; dim: root.dim; fontFamily: root.ff
          onMuteRequested: panel.transport("toggleMute")
          onVolumeChangeRequested: function(value) { panel.queueVolume(value) }
        }
      }
    }
    Item {
      anchors.left: nextButton.right; anchors.leftMargin: Style.space(12)
      anchors.right: volumeButton.left; anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(24)
      SeekBar {
        anchors.fill: parent
        panel: root.panel; trackHeight: Style.space(3)
        anchors.topMargin: -Style.space(2)
      }
    }
  }
}
