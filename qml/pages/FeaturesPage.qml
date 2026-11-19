import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "../components"

Item {
  id: root
  required property var panel
  property bool wide: false
  property var snapshot: ({})
  property var spec: ({})
  readonly property var entity: snapshot.entity || ({})
  property bool pendingAction: false
  property bool uncertainAction: false
  property int pendingRevision: -1
  readonly property bool busy: pendingAction || uncertainAction || snapshot.busy === true || snapshot.loading === true
  readonly property string view: String(spec.view || "overview")
  readonly property var viewport: list
  property var pendingNavigation: null
  function confirmNavigation(callback) { pendingNavigation=callback; ask({op:"discard"}, "Закрыть форму без сохранения?") }
  readonly property real viewportY: Math.max(0, list.contentY - list.originY + (list.headerItem ? list.headerItem.height : 0))
  property string scrollIdentity: ""
  property real initialViewport: 0
  readonly property var titleInput: list.headerItem ? list.headerItem.titleInput : null
  readonly property var descriptionInput: list.headerItem ? list.headerItem.descriptionInput : null
  readonly property var queryInput: list.headerItem ? list.headerItem.queryInput : null
  readonly property bool editorFocused: (titleInput && titleInput.activeFocus) || (descriptionInput && descriptionInput.activeFocus) || (queryInput && queryInput.activeFocus)
  property string formIdentity: ""
  property string originalTitle: ""
  property string originalDescription: ""
  property string visibilityValue: "private"
  property bool dirty: false
  property var confirmation: null
  property string confirmationText: ""
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property real pad: Style.space(wide ? 28 : 16)

  function preserveViewport(y) {
    if (Number(y || 0) <= 0) list.positionViewAtBeginning()
    else list.contentY = list.originY - (list.headerItem ? list.headerItem.height : 0) + Number(y)
  }
  function request(value) {
    if (busy || !snapshot.identity) return
    var copy = JSON.parse(JSON.stringify(value)); copy.identity = snapshot.identity
    if (entity.editable) copy.playlistRevision = entity.playlistRevision
    pendingRevision = Number(snapshot.revision || 0)
    pendingAction = true
    if (!panel.intent("featureAction", JSON.stringify(copy))) pendingAction = false
    else actionDeadline.restart()
  }
  function activate(value) {
    if (value.view) panel.openFeature(value)
    else if (value.op === "stream") ask(value, "Включить поток вместо текущей музыки?")
    else request(value)
  }
  function ask(value, text) { confirmation = value; confirmationText = text; Qt.callLater(function(){confirmButton.forceActiveFocus()}) }
  function handleEscape() {
    if (confirmation) { confirmation = null; return true }
    if (dirty) { ask({op:"discard"}, "Закрыть форму без сохранения?"); return true }
    return false
  }
  function save() {
    var value = {op:"savePlaylist", title:titleInput.text, description:descriptionInput.text, visibility:visibilityValue}
    if (visibilityValue === "public" && entity.visibility !== "public") ask(value, "Сделать плейлист публичным?")
    else request(value)
  }
  function initializeForm() {
    if (!titleInput || !descriptionInput || !entity.editable || snapshot.loading || formIdentity === snapshot.identity) return
    formIdentity = snapshot.identity
    originalTitle = String(entity.title || "")
    originalDescription = String(entity.description || "")
    titleInput.text = originalTitle; descriptionInput.text = originalDescription
    visibilityValue = String(entity.visibility || "private"); dirty = false
  }
  onEntityChanged: Qt.callLater(initializeForm)
  onTitleInputChanged: Qt.callLater(initializeForm)
  Timer {id:viewportInit;interval:32;onTriggered:{list.forceLayout();root.preserveViewport(root.initialViewport)}}
  Timer {
    id:actionDeadline; interval:25000
    onTriggered:{root.pendingAction=false;root.uncertainAction=true}
  }
  onSnapshotChanged: {
    if (Number(snapshot.revision || 0) > pendingRevision && snapshot.busy !== true) {
      pendingAction=false; uncertainAction=false; actionDeadline.stop()
    }
    Qt.callLater(initializeForm)
    if (snapshot.identity && scrollIdentity !== snapshot.identity) {
      scrollIdentity = snapshot.identity
      initialViewport=Number(panel && panel.activeRoute ? panel.activeRoute.scrollY || 0 : 0)
      viewportInit.restart()
    }
    if (snapshot.message === "Готово" && !snapshot.error && !snapshot.busy) dirty = false
  }
  onVisibleChanged: if (!visible) { pendingAction=false; uncertainAction=false; actionDeadline.stop(); confirmation = null; if(queryInput) queryInput.focus = false; if(titleInput) titleInput.focus = false; if(descriptionInput) descriptionInput.focus = false }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
  component Action: IconButton {
    focusable: true; bordered: true
    enabled: !root.busy
    fontFamily: root.ff; fontSize: Style.font.bodySmall
    foreground: root.fg
  }
  component Toggle: IconButton {
    property bool known: false
    property bool isOn: false
    width: Style.space(32); height: width; horizontalPadding: 0
    iconSize: Style.space(18); focusable: true
    foreground: isOn ? Commons.Color.accent : root.fg
    enabled: known && !root.busy; opacity: enabled ? 1 : .4
  }
  // Иконка строки: без рамки, как в остальных списках.
  component RowIcon: IconButton {
    width: Style.space(30); height: width; horizontalPadding: 0
    iconSize: Style.space(16); focusable: true
    enabled: !root.busy; foreground: panel.dim
  }

  ListView {
    id: list
    objectName: "featuresList"
    anchors.fill: parent
    anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
    anchors.topMargin: Style.space(14); anchors.bottomMargin: Style.space(14)
    clip: true; spacing: Style.space(6)
    boundsBehavior: Flickable.StopAtBounds
    model: root.snapshot.rows || []
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    header: Column {
      property alias titleInput: titleField
      property alias descriptionInput: descriptionField
      property alias queryInput: queryField
      Component.onCompleted: root.initializeForm()
      width: list.width; spacing: Style.space(12)
      Label { width: parent.width; text: String(root.snapshot.title || root.spec.title || "Загружаем…"); font.bold: true; font.pixelSize: Style.space(root.wide ? 24 : 20) }
      Label { visible: root.view === "similar"; width: parent.width; text: String(root.spec.title || ""); color: panel.dim }
      Column {
        visible: root.view === "podcasts"; width: parent.width; spacing: Style.space(8)
        BoundedTextField {
          id: queryField; objectName: "podcastSearch"
          width: parent.width; placeholderText: "Шоу или выпуск"; font.family: root.ff
          text: String(root.spec.query || "")
          onAccepted: root.panel.openFeature({view:"podcasts", query:text, episodes:root.spec.episodes === true})
        }
        Flow {
          width: parent.width; spacing: Style.space(8)
          Action { text:"Шоу"; selected:root.spec.episodes !== true; onClicked:root.panel.openFeature({view:"podcasts", query:queryField.text, episodes:false}) }
          Action { text:"Выпуски"; selected:root.spec.episodes === true; onClicked:root.panel.openFeature({view:"podcasts", query:queryField.text, episodes:true}) }
          Action { text:"Найти"; enabled:!root.busy && queryField.text.trim().length > 0; onClicked:root.panel.openFeature({view:"podcasts", query:queryField.text, episodes:root.spec.episodes === true}) }
        }
      }
      Flow {
        visible: root.view === "entity" && !root.snapshot.loading
        width: parent.width; spacing: Style.space(8)
        // Те же иконки, что в карточках каталога и Медиатеки.
        Toggle {
          objectName:"featureFavorite"
          known:root.entity.favoriteKnown === true; isOn:root.entity.favorite === true
          iconText:isOn ? "󰋑" : "󰋕"
          tooltipText:!known ? "Статус избранного неизвестен" : (isOn ? "Убрать из избранного" : "Добавить в избранное")
          onClicked:root.request({op:"favorite", value:!isOn})
        }
        Toggle {
          objectName:"featurePin"
          known:root.entity.pinnedKnown === true; isOn:root.entity.pinned === true
          iconText:isOn ? "󰐃" : "󰤱"
          tooltipText:!known ? "Статус закрепления неизвестен" : (isOn ? "Открепить" : "Закрепить в медиатеке")
          onClicked:root.request({op:"pin", value:!isOn})
        }
        Action {
          visible:root.entity.entityType === "album" || root.entity.entityType === "playlist"
          text:"Похожая музыка"; iconText:"󰁗"
          onClicked:root.panel.openFeature({view:"similar", type:root.entity.entityType, id:root.entity.id, uuid:root.entity.uuid, title:root.snapshot.title})
        }
        Action {
          visible:root.entity.entityType === "artist"; enabled:!root.busy && root.entity.blockKnown === true
          text:root.entity.blocked ? "Вернуть в рекомендации" : "Не рекомендовать"
          onClicked:root.ask({op:"block", value:root.entity.blocked !== true}, root.entity.blocked ? "Вернуть исполнителя в рекомендации?" : "Не рекомендовать этого исполнителя?")
        }
      }
      Label { visible:!!root.entity.statusWarning; text:String(root.entity.statusWarning || ""); width:parent.width; color:panel.dim }
      Column {
        visible:root.entity.editable === true; width:parent.width; spacing:Style.space(10)
        Label { text:"НАЗВАНИЕ"; color:panel.dim; font.pixelSize:Style.font.caption }
        BoundedTextField {
          id:titleField; objectName:"playlistTitleEdit"; width:parent.width; font.family:root.ff
          onTextEdited:root.dirty = true
        }
        Label { text:"ОПИСАНИЕ"; color:panel.dim; font.pixelSize:Style.font.caption }
        BoundedTextField {
          id:descriptionField; objectName:"playlistDescriptionEdit"; width:parent.width; font.family:root.ff
          onTextEdited:root.dirty = true
        }
        Flow {
          width:parent.width; spacing:Style.space(8)
          Action { text:"Только вы"; selected:root.visibilityValue === "private"; onClicked:{root.visibilityValue="private"; root.dirty=true} }
          Action { text:"Публичный"; selected:root.visibilityValue === "public"; onClicked:{root.visibilityValue="public"; root.dirty=true} }
          Action { text:"Сохранить"; enabled:!root.busy && titleField.text.trim().length > 0; onClicked:root.save() }
          Action { text:"Удалить плейлист"; foreground:Commons.Color.urgent; onClicked:root.ask({op:"deletePlaylist"}, "Удалить плейлист из аккаунта? Действие необратимо.") }
        }
        Label { text:"ПОРЯДОК ТРЕКОВ · ↑ / ↓ сохраняют перемещение"; width:parent.width; color:panel.dim; font.pixelSize:Style.font.caption }
      }
      Column {
        visible:root.view === "quality"; width:parent.width; spacing:Style.space(12)
        Repeater {
          model:[{key:"economy",title:"Экономия"},{key:"best",title:"Лучшее доступное"},{key:"lossless",title:"Lossless"}]
          Action {
            required property var modelData
            width:parent.width; text:modelData.title
            selected:root.panel.preference("audioQuality", "best") === modelData.key
            onClicked:root.panel.setPreference("audioQuality",modelData.key)
          }
        }
        Label { width:parent.width; text:"Сейчас: " + String(root.panel.data.audioFormat || "формат ещё не определён") }
        Label { width:parent.width; color:panel.dim; text:"Lossless зависит от подписки и доступности файла. Если он недоступен, используется лучший доступный формат. Новый выбор применяется при следующем запуске трека." }
      }
      Flow {
        visible:root.view === "streams"; width:parent.width; spacing:Style.space(8)
        Action { text:"Остановить поток"; enabled:!root.busy && !!root.panel.data.streamActive; onClicked:root.panel.session.action("stop") }
        Action { text:"Вернуться к музыке"; enabled:!root.busy && !!root.panel.data.streamActive; onClicked:root.panel.intent("resumeMusic") }
      }
      Label { visible:root.snapshot.loading === true; width:parent.width; text:"Загружаем…"; color:panel.dim }
      Label { visible:root.snapshot.busy === true; width:parent.width; text:"Выполняем действие…"; color:panel.dim }
      Label { visible:!!root.snapshot.error; width:parent.width; text:String(root.snapshot.error || ""); color:Commons.Color.urgent }
      Label { visible:!!root.snapshot.warning; width:parent.width; text:String(root.snapshot.warning || ""); color:panel.dim }
      Action {
        visible:root.uncertainAction || !!root.snapshot.error
        text:"Обновить состояние"; enabled:!root.pendingAction && root.snapshot.busy !== true && root.snapshot.loading !== true
        onClicked:{root.uncertainAction=false; if(root.dirty) root.confirmNavigation(function(){root.formIdentity="";root.panel.reloadFeature()}); else {root.formIdentity=""; root.panel.reloadFeature()}}
      }
      Label { visible:root.uncertainAction; width:parent.width; text:"Результат неизвестен. Обновите состояние перед повторным действием."; color:Commons.Color.urgent }
      Label { visible:!!root.snapshot.message; width:parent.width; text:String(root.snapshot.message || ""); color:Commons.Color.accent }
      Label {
        visible:!root.busy && !root.snapshot.error && list.count === 0 && root.view !== "quality"
          && (root.view === "pins" || !root.snapshot.message)
        width:parent.width
        text:root.view === "pins" ? "Здесь появится музыка, которую вы закрепите кнопкой с булавкой." : "Здесь пока ничего нет"
        color:panel.dim
      }
      Item { width:1; height:Style.space(4) }
    }
    delegate: Rectangle {
      id:row
      required property var modelData
      required property int index
      // Основное действие строки: трек — играть, сущность — открыть, действие — выполнить.
      readonly property bool opens: root.entity.editable !== true && (!modelData.trailing || root.view === "pins")
      readonly property bool pinnedWave: root.view === "pins" && modelData.entityType === "action"
      width:list.width; height:Style.space(root.wide ? 52 : 48)
      enabled:modelData.available !== false
      opacity:enabled ? 1 : .45
      radius:Style.cornerRadius
      color:rowHover.hovered && row.opens ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"
      HoverHandler { id:rowHover }
      function primary() {
        if (row.modelData.action) root.activate(row.modelData.action)
        else if (row.modelData.entityType === "track") root.request({op:"play", index:row.index})
        else if (row.modelData.entityType === "album") root.panel.openCatalogAlbum(row.modelData.id,row.modelData.title)
        else if (row.modelData.entityType === "artist") root.panel.openCatalogArtist(row.modelData.id,row.modelData.title)
        else if (row.modelData.entityType === "playlist") root.panel.openCatalogPlaylist(row.modelData)
      }
      MouseArea {
        anchors.fill:parent; anchors.rightMargin:controls.width + Style.space(8)
        enabled:row.opens && !root.busy; cursorShape:Qt.PointingHandCursor
        onClicked:row.primary()
      }
      CatalogImage {
        id:cover; x:Style.space(6); anchors.verticalCenter:parent.verticalCenter
        width:Style.space(root.wide ? 36 : 32); height:width
        requestedSource:row.pinnedWave ? "" : String(row.modelData.artUrl || "")
        foreground:root.fg; fontFamily:root.ff
      }
      LucideIcon {
        anchors.centerIn: cover
        visible: row.pinnedWave
        glyph: "󰐷"; size: Style.space(18); color: panel.dim; fontFamily: root.ff
      }
      Column {
        anchors.left:cover.right; anchors.leftMargin:Style.space(12); anchors.verticalCenter:parent.verticalCenter
        width:Math.max(0, parent.width - x - controls.width - Style.space(16)); spacing:Style.space(3)
        Label { width:parent.width; text:String(row.modelData.title || row.modelData.name || "Без названия"); wrapMode:Text.NoWrap; elide:Text.ElideRight; font.pixelSize:Style.space(12) }
        Label { width:parent.width; text:String(row.modelData.subtitle || row.modelData.artist || ""); wrapMode:Text.NoWrap; elide:Text.ElideRight; color:panel.dim; font.pixelSize:Style.space(10) }
      }
      Row {
        id:controls; anchors.right:parent.right; anchors.rightMargin:Style.space(4); anchors.verticalCenter:parent.verticalCenter; spacing:Style.space(4)
        RowIcon { visible:root.entity.editable === true; iconText:"󰅃"; tooltipText:"Выше"; enabled:!root.busy && row.index > 0; onClicked:root.request({op:"move", from:row.index, to:row.index-1}) }
        RowIcon { visible:root.entity.editable === true; iconText:"󰅀"; tooltipText:"Ниже"; enabled:!root.busy && row.index+1 < list.count; onClicked:root.request({op:"move", from:row.index, to:row.index+1}) }
        RowIcon {
          visible:row.modelData.entityType === "track" && !root.entity.editable && rowHover.hovered
          iconText:"󰐒"; tooltipText:"В плейлист…"
          onClicked:root.panel.openCollectionTrack("feature", row.index, row.modelData, false, "", "", this)
        }
        Action {
          visible:!row.opens && !!row.modelData.trailing && !!row.modelData.action
          text:"Включить"
          onClicked:root.activate(row.modelData.action)
        }
        Action {
          visible:!!row.modelData.trailing
          text:String((row.modelData.trailing || {}).title || "Вернуть")
          enabled:!root.busy && (!(root.view === "pins" || root.view === "wave") || !root.snapshot.error)
          onClicked:root.request(row.modelData.trailing)
        }
        Text {
          visible:row.opens && row.modelData.entityType === "track" && !rowHover.hovered && Number(row.modelData.duration || 0) > 0
          anchors.verticalCenter:parent.verticalCenter
          text:root.panel.formatTime(row.modelData.duration); color:panel.dim
          font.family:root.ff; font.pixelSize:Style.space(10)
        }
        RowIcon {
          visible:row.opens && (row.modelData.entityType !== "track" || rowHover.hovered)
          readonly property bool plays: row.modelData.entityType === "track"
            || (root.view === "pins" && !!row.modelData.action)
          iconText:plays ? "󰐊" : "󰅂"
          tooltipText:plays ? "Играть" : "Открыть"
          onClicked:row.primary()
        }
      }
    }
    footer: Action {
      width:list.width; visible:root.snapshot.hasMore === true
      height:visible ? implicitHeight : 0
      text:"Загрузить ещё"; onClicked:root.request({op:"more"})
    }
  }
  Rectangle {
    anchors.fill:parent; visible:root.confirmation !== null; z:20; color:"#99000000"
    MouseArea { anchors.fill:parent; onClicked:root.confirmation=null }
    Rectangle {
      width:root.wide ? Math.min(parent.width - Style.space(32), Style.space(420)) : parent.width
      height:confirmColumn.implicitHeight + Style.space(40)
      anchors.right:parent.right; anchors.bottom:parent.bottom
      color:Commons.Color.popups.background; border.width:1; border.color:Commons.Color.accent
      MouseArea { anchors.fill:parent }
      Column {
        id:confirmColumn; anchors.left:parent.left; anchors.right:parent.right; anchors.top:parent.top; anchors.margins:Style.space(20); spacing:Style.space(18)
        Label { width:parent.width; text:root.confirmationText; font.bold:true }
        Row {
          spacing:Style.space(12)
          Action {
            id:confirmButton
            text:"Подтвердить"
            onClicked:{
              var action=root.confirmation; root.confirmation=null
              if (action.op === "discard") {root.dirty=false; var next=root.pendingNavigation; root.pendingNavigation=null; if(next) next(); else root.panel.popRoute()}
              else {action.confirmed=true; root.request(action)}
            }
          }
          Action { text:"Отмена"; onClicked:root.confirmation=null }
        }
      }
    }
  }
}
