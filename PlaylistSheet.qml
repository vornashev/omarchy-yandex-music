import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Rectangle {
  id: root
  required property var controller
  property bool wide: false
  property color foreground: Color.foreground
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, .55)
  property string fontFamily: Style.font.family
  property int selectedIndex: -1
  readonly property bool recommendations: controller.mode === "recommendations"
  readonly property bool terminal: controller.mode === "result"
  readonly property bool locked: controller.busy || controller.checkingMemberships
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .08)
  readonly property int containedCount: {
    var count = 0
    for (var i = 0; i < controller.ownPlaylists.length; i++)
      if (controller.playlistContains(String(controller.ownPlaylists[i].kind || ""))) count++
    return count
  }
  signal dismissed()
  color: Qt.lighter(Color.background, 1.12)
  border.width: Style.spacing.hairline
  border.color: wide ? Qt.rgba(foreground.r, foreground.g, foreground.b, .2) : "transparent"
  clip: true
  focus: true

  function activate() {
    selectedIndex = -1
    forceActiveFocus()
  }
  function cancel() {
    if (controller.busy) return
    if (controller.mode === "create" || controller.mode === "delete") {
      controller.mode = "track"
      forceActiveFocus()
    } else dismissed()
  }
  function selectNext(delta) {
    if (locked || controller.mode !== "track") return
    var count = controller.ownPlaylists.length
    var current = selectedIndex < 0 ? (delta > 0 ? -1 : count + 1) : selectedIndex
    for (var i = 0; i <= count; i++) {
      current = (current + delta + count + 1) % (count + 1)
      if (current === count || (!controller.playlistContains(String(controller.ownPlaylists[current].kind || ""))
          && controller.membershipError === "")) {
        selectedIndex = current
        if (current < count) playlistList.positionViewAtIndex(current, ListView.Contain)
        return
      }
    }
  }
  function activateSelection() {
    if (locked || terminal || recommendations || controller.mode === "delete") return
    if (controller.mode === "create") controller.submitCreate()
    else if (selectedIndex === controller.ownPlaylists.length) controller.beginCreate()
    else if (selectedIndex >= 0) controller.requestAdd(String(controller.ownPlaylists[selectedIndex].kind || ""))
  }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { cancel(); event.accepted = true }
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      selectNext(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateSelection(); event.accepted = true
    } else if (event.key === Qt.Key_Delete && !locked && !terminal) {
      controller.beginDelete(); event.accepted = true
    }
  }
  Connections {
    target: root.controller
    function onModeChanged() {
      if (root.controller.mode === "create") {
        titleField.text = root.controller.draftTitle
        Qt.callLater(function() {
          if (root.controller.mode === "create" && root.visible) titleField.forceActiveFocus()
        })
      }
    }
  }
  MouseArea { anchors.fill: parent }
  Rectangle { width: parent.width; height: Style.spacing.hairline; color: Color.accent; visible: !root.wide }

  Item {
    id: header
    width: parent.width; height: Style.space(76)
    Rectangle {
      x: Style.space(16); anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40); height: width; color: root.lineColor
      LucideIcon { anchors.centerIn: parent; glyph: "󰝚"; size: Style.space(18); color: root.dim }
      CatalogImage {
        anchors.fill: parent
        requestedSource: String(root.controller.target.artUrl || "")
        foreground: root.foreground; fontFamily: root.fontFamily
        fillMode: Image.PreserveAspectCrop
      }
    }
    Column {
      x: Style.space(68); anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(124); spacing: Style.space(3)
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.recommendations ? "РЕКОМЕНДАЦИИ" : "В ПЛЕЙЛИСТ"
        color: root.dim; font.family: root.fontFamily
        font.pixelSize: Style.space(9); font.bold: true; font.letterSpacing: 1
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: root.recommendations ? root.controller.playlistTitle : String(root.controller.target.title || "Трек")
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; elide: Text.ElideRight
        text: String(root.controller.target.artist || "")
        color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }
    IconButton {
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28); height: width
      horizontalPadding: 0; verticalPadding: 0
      iconText: "󰅖"; foreground: root.dim; bordered: true
      tooltipText: "Закрыть · Esc"; enabled: !root.controller.busy
      onClicked: root.dismissed()
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Style.spacing.hairline; color: root.lineColor }
  }

  Item {
    id: section
    anchors.top: header.bottom
    width: parent.width; height: visible ? Style.space(30) : 0
    visible: !root.recommendations && !root.terminal
    Text {
      textFormat: Text.PlainText
      x: Style.space(16); anchors.verticalCenter: parent.verticalCenter
      text: "ВАШИ ПЛЕЙЛИСТЫ"; color: root.dim
      font.family: root.fontFamily; font.pixelSize: Style.space(9); font.letterSpacing: .7
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right; anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: root.controller.checkingMemberships ? "проверяем…"
        : root.controller.busy ? "сохраняем…"
        : root.containedCount + " из " + root.controller.ownPlaylists.length + " уже содержит"
      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9)
    }
  }

  ListView {
    id: playlistList
    anchors.top: section.bottom; anchors.bottom: newPlaylist.top
    width: parent.width; clip: true
    visible: !root.recommendations && !root.terminal
    model: root.controller.ownPlaylists
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    delegate: Rectangle {
      id: playlistRow
      required property var modelData
      required property int index
      readonly property string kind: String(modelData.kind || "")
      readonly property bool containsTrack: root.controller.playlistContains(kind)
      readonly property bool available: !root.locked && root.controller.mode === "track"
        && root.controller.membershipError === "" && !containsTrack
      width: playlistList.width; height: Style.space(52)
      color: rowMouse.containsMouse || root.selectedIndex === index
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent"
      opacity: root.locked ? .45 : 1
      Rectangle {
        x: Style.space(16); anchors.verticalCenter: parent.verticalCenter
        width: Style.space(36); height: width; color: root.lineColor
        LucideIcon { anchors.centerIn: parent; glyph: "󰐒"; size: Style.space(16); color: root.dim }
        CatalogImage {
          anchors.fill: parent
          requestedSource: String(playlistRow.modelData.artUrl || "")
          foreground: root.foreground; fontFamily: root.fontFamily; fillMode: Image.PreserveAspectCrop
        }
      }
      Column {
        x: Style.space(64); anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(120); spacing: Style.space(2)
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: String(playlistRow.modelData.title || "Плейлист")
          color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: (playlistRow.containsTrack
            ? (root.controller.lastSuccessfulKind === playlistRow.kind ? "✓ добавлено · " : "✓ уже здесь · ") : "")
            + Number(playlistRow.modelData.count || 0) + " треков"
          color: playlistRow.containsTrack ? Color.accent : root.dim
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }
      Rectangle {
        anchors.right: parent.right; anchors.rightMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28); height: width
        color: playlistRow.containsTrack ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .15)
          : rowMouse.containsMouse && playlistRow.available ? Color.accent : "transparent"
        border.width: Style.spacing.hairline
        border.color: playlistRow.containsTrack ? Color.accent : root.lineColor
        LucideIcon {
          anchors.centerIn: parent; glyph: playlistRow.containsTrack ? "󰄬" : "󰐕"
          size: Style.space(14)
          color: rowMouse.containsMouse && playlistRow.available ? Color.background : playlistRow.containsTrack ? Color.accent : root.dim
        }
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent; hoverEnabled: true
        cursorShape: playlistRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (playlistRow.available) {
          root.selectedIndex = playlistRow.index
          root.controller.requestAdd(playlistRow.kind)
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.controller.ownPlaylists.length === 0
      anchors.centerIn: parent; text: "Пока нет своих плейлистов"
      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
  }

  Item {
    id: newPlaylist
    anchors.bottom: deletion.top
    width: parent.width
    visible: !root.recommendations && !root.terminal
    height: !visible ? 0 : Style.space(root.controller.mode === "create" ? 96 : 56)
    Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.lineColor }
    IconButton {
      visible: root.controller.mode !== "create"
      x: Style.space(16); anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36); height: width
      horizontalPadding: 0; verticalPadding: 0
      iconText: "󰐕"; foreground: Color.accent; bordered: true
      enabled: !root.locked && root.controller.membershipError === ""; onClicked: root.controller.beginCreate()
    }
    Column {
      visible: root.controller.mode !== "create"
      x: Style.space(64); anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(80); spacing: Style.space(2)
      Text { textFormat: Text.PlainText; text: "Новый плейлист"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
      Text { textFormat: Text.PlainText; text: "приватный · трек добавится сразу"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    MouseArea {
      anchors.fill: parent; visible: root.controller.mode !== "create"
      enabled: !root.locked && root.controller.membershipError === ""
      cursorShape: Qt.PointingHandCursor; onClicked: root.controller.beginCreate()
    }
    Column {
      visible: root.controller.mode === "create"
      x: Style.space(16); y: Style.space(10); width: parent.width - Style.space(32); spacing: Style.space(8)
      Text { textFormat: Text.PlainText; text: "НОВЫЙ ПРИВАТНЫЙ ПЛЕЙЛИСТ"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9); font.letterSpacing: .6 }
      Row {
        width: parent.width; spacing: Style.space(8)
        TextField {
          id: titleField
          width: parent.width - createButton.width - parent.spacing; height: Style.space(34)
          placeholderText: "Название плейлиста"; foreground: root.foreground; font.family: root.fontFamily
          enabled: !root.locked
          onTextEdited: root.controller.draftTitle = text
          Keys.onReturnPressed: root.controller.submitCreate()
          Keys.onEnterPressed: root.controller.submitCreate()
          Keys.onEscapePressed: root.cancel()
        }
        IconButton {
          id: createButton
          text: "Создать"; height: Style.space(34); foreground: Color.accent; bordered: true
          enabled: !root.locked && String(root.controller.draftTitle || "").trim() !== ""
          onClicked: root.controller.submitCreate()
        }
      }
      Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: "Enter — создать и добавить трек · Esc — отмена"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9) }
    }
  }

  Column {
    id: deletion
    anchors.bottom: notices.top
    width: parent.width
    visible: root.controller.target.canDelete === true && !root.recommendations && !root.terminal
    height: visible ? implicitHeight : 0
    spacing: Style.space(8)
    Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.lineColor }
    Text {
      textFormat: Text.PlainText
      x: Style.space(16); width: parent.width - Style.space(32); elide: Text.ElideRight
      text: "ОТКРЫТ «" + String(root.controller.target.playlistTitle || "Плейлист").toUpperCase() + "»"
      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9)
    }
    IconButton {
      visible: root.controller.mode !== "delete"
      x: Style.space(16); width: parent.width - Style.space(32); height: Style.space(34)
      iconText: "󰆴"; text: "Убрать трек из этого плейлиста"; fontSize: Style.font.caption
      foreground: Color.urgent; leftAlign: true; bordered: true
      enabled: !root.locked; onClicked: root.controller.beginDelete()
    }
    Column {
      visible: root.controller.mode === "delete"
      x: Style.space(16); width: parent.width - Style.space(32); spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        width: parent.width; wrapMode: Text.WordWrap
        text: "Убрать «" + String(root.controller.target.title || "Трек") + "» (позиция " + (Number(root.controller.target.index) + 1) + ")?"
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width; wrapMode: Text.WordWrap
        text: "Если трек есть в плейлисте дважды, уберётся только эта копия."
        color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
      Row {
        spacing: Style.space(8)
        IconButton { text: "Отмена"; foreground: root.foreground; bordered: true; focusable: true; enabled: !root.controller.busy; onClicked: { root.controller.mode = "track"; root.forceActiveFocus() } }
        IconButton { text: "Убрать"; foreground: Color.urgent; bordered: true; focusable: true; enabled: !root.controller.busy; onClicked: root.controller.confirmDelete() }
      }
    }
    Item { width: 1; height: Style.space(8) }
  }

  Column {
    id: notices
    anchors.bottom: footer.top
    width: parent.width
    spacing: Style.space(4)
    visible: root.controller.message !== "" || root.controller.error !== "" || root.controller.membershipError !== ""
    height: visible ? implicitHeight : 0
    Repeater {
      model: [ { text: root.controller.message, error: false },
        { text: root.controller.error || root.controller.membershipError, error: true } ]
      delegate: Rectangle {
        required property var modelData
        visible: modelData.text !== ""
        width: notices.width; height: visible ? Math.max(Style.space(36), noticeText.implicitHeight + Style.space(20)) : 0
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .04)
        LucideIcon { x: Style.space(16); y: Style.space(11); glyph: modelData.error ? "󰀦" : "󰄬"; size: Style.space(14); color: modelData.error ? Color.urgent : Color.accent }
        Text {
          id: noticeText
          textFormat: Text.PlainText
          x: Style.space(40); y: Style.space(10)
          width: parent.width - Style.space(retryButton.visible ? 120 : 56)
          wrapMode: Text.WordWrap; text: modelData.text
          color: modelData.error ? Color.urgent : Color.accent
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
        IconButton {
          id: retryButton
          visible: modelData.error && (root.controller.membershipError !== "" || root.controller.canRetryLastMutation)
          anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
          text: "Повторить"; foreground: Color.urgent; fontSize: Style.font.caption
          horizontalPadding: Style.space(4); enabled: !root.locked
          onClicked: root.controller.membershipError !== "" ? root.controller.retryMemberships() : root.controller.retryLastMutation()
        }
      }
    }
  }

  ListView {
    anchors.top: header.bottom; anchors.bottom: notices.top
    width: parent.width; clip: true; visible: root.recommendations
    model: root.controller.recommendations
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    delegate: Item {
      required property var modelData
      width: ListView.view.width; height: Style.space(52)
      CatalogImage { x: Style.space(16); anchors.verticalCenter: parent.verticalCenter; width: Style.space(36); height: width; requestedSource: String(modelData.artUrl || ""); foreground: root.foreground; fillMode: Image.PreserveAspectCrop }
      Column {
        x: Style.space(64); anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(120)
        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: String(modelData.title || "Трек"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: String(modelData.artist || ""); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }
      IconButton { anchors.right: parent.right; anchors.rightMargin: Style.space(16); anchors.verticalCenter: parent.verticalCenter; width: Style.space(28); height: width; horizontalPadding: 0; verticalPadding: 0; iconText: "󰐕"; foreground: Color.accent; tooltipText: "Добавить"; enabled: !root.controller.busy; onClicked: root.controller.addRecommendation(modelData) }
    }
    Text { textFormat: Text.PlainText; anchors.centerIn: parent; visible: root.controller.recommendations.length === 0; text: root.controller.busy ? "Подбираем треки…" : "Новых рекомендаций пока нет"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
  }
  Text {
    textFormat: Text.PlainText
    visible: root.terminal; anchors.centerIn: parent
    text: "Выберите трек заново для следующего действия"
    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
  Item {
    id: footer
    anchors.bottom: parent.bottom; width: parent.width; height: Style.space(32)
    Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.lineColor }
    Text { textFormat: Text.PlainText; x: Style.space(16); anchors.verticalCenter: parent.verticalCenter; text: root.recommendations || root.terminal ? "" : "↑↓ выбрать · Enter добавить"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9) }
    Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.rightMargin: Style.space(16); anchors.verticalCenter: parent.verticalCenter; text: "Esc закрыть"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9) }
  }
}
