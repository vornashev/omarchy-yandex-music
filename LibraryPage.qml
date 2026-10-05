import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Главная медиатеки, разделы и настройки Волны; переходами управляет родитель.
Item {
  id: root
  required property var controller
  property bool wide: false
  property var preferences: ({})
  property color foreground: "white"
  property color dim: "gray"
  property string fontFamily: ""
  property bool panelOpened: false
  property bool settingsOpen: false
  property bool settingsRunning: false
  property var focusTarget: null
  property bool waveOptionsOpen: false
  property bool waveActive: false
  property bool wavePlaying: false
  property bool waveLoading: false
  property int likesTotal: -1
  readonly property bool homeActive: panelOpened && visible && !settingsOpen
    && !waveOptionsOpen && controller && controller.view === "home"
  readonly property var viewport: waveOptionsOpen ? waveOptionsFlick
    : (controller.view === "home" ? homeFlick : libraryList)
  readonly property real viewportY: Math.max(0, viewport.contentY - (viewport.originY || 0))
  readonly property bool stationSearchActiveFocus: stationSearchField.activeFocus
  readonly property bool stationSearchVisible: stationSearchField.visible
  readonly property real pad: wide ? Style.space(28) : Style.space(16)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .08)
  readonly property var personalOptions: [
    { personalId: "daily", title: "Плейлист дня", subtitle: "Персональная подборка", glyph: "󰲸" },
    { personalId: "missedLikes", title: "Тайник", subtitle: "Редкие находки", glyph: "󰎈" },
    { personalId: "recentTracks", title: "Премьера", subtitle: "Новые релизы", glyph: "󰔵" },
    { personalId: "neverHeard", title: "Дежавю", subtitle: "Давно не слушали", glyph: "󰋚" },
    { personalId: "podcasts", title: "Подкасты недели", subtitle: "Новые выпуски", glyph: "󰐹" }]
  readonly property var moreSections: [
    { section: "albums", glyph: "󰀥", title: "Альбомы" },
    { section: "artists", glyph: "󰠃", title: "Исполнители" },
    { section: "playlists", glyph: "󰲸", title: "Плейлисты" },
    { section: "stations", glyph: "󰐹", title: "Станции" }]
  readonly property var moodOptions: [
    { value: "all", label: "Любое", glyph: "󰁗" }, { value: "active", label: "Бодрое", glyph: "󱐋" },
    { value: "calm", label: "Спокойное", glyph: "󰌪" }, { value: "fun", label: "Весёлое", glyph: "󰇵" },
    { value: "sad", label: "Грустное", glyph: "󰖗" }]
  readonly property var diversityOptions: [
    { value: "default", label: "Как обычно", sub: "Баланс", glyph: "󰒟" },
    { value: "favorite", label: "Любимое", sub: "Больше любимого", glyph: "󰋕" },
    { value: "discover", label: "Незнакомое", sub: "Новые открытия", glyph: "󰆋" },
    { value: "popular", label: "Популярное", sub: "Хиты и тренды", glyph: "󰔵" }]
  readonly property var languageOptions: [
    { value: "any", label: "Любой" }, { value: "russian", label: "Русский" },
    { value: "not-russian", label: wide ? "Иностранный" : "Иностр." },
    { value: "without-words", label: "Без слов" }]

  signal preferenceRequested(string key, var value)
  signal waveRequested()
  signal wavePlaybackRequested()
  signal waveOptionsRequested()
  signal collectionTrackRequested(int index, var value, var anchor)

  function preference(key, fallback) {
    var values = preferences || {}
    return values[key] === undefined ? fallback : values[key]
  }
  function optionLabel(list, value, fallback) {
    for (var i = 0; i < list.length; i++) if (list[i].value === value) return list[i].label
    return fallback
  }
  function personalItem(id) {
    var items = controller.personalItems || []
    for (var i = 0; i < items.length; i++) if (items[i].personalId === id) return items[i]
    return null
  }
  function clearStationFocus() { stationSearchField.focus = false }
  onHomeActiveChanged: if (homeActive) controller.requestHome()
  Component.onCompleted: if (homeActive) controller.requestHome()
  function resetViewport() { preserveViewport(0) }
  function preserveViewport(y) {
    var surface = viewport
    if (surface === libraryList) surface.forceLayout()
    surface.contentY = (surface.originY || 0) + Math.max(0, Math.min(Number(y) || 0,
      Math.max(0, surface.contentHeight - surface.height)))
  }

  readonly property string waveSummary: optionLabel(moodOptions, String(preference("waveMood", "all")), "Любое")
    + " · " + optionLabel(diversityOptions, String(preference("waveDiversity", "default")), "Как обычно")
    + " · " + optionLabel(languageOptions, String(preference("waveLanguage", "any")), "Любой")

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
    font.bold: true; font.letterSpacing: 1.2
  }
  component HubCard: Rectangle {
    id: card
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool primary: false
    property bool trailing: !root.wide
    signal clicked()
    height: Style.space(primary ? 60 : root.wide ? 52 : 44)
    color: primary ? Style.selectedFillFor(root.foreground, Color.accent)
      : cardMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
      : root.wide ? Style.normalFillFor(root.foreground, Color.accent) : "transparent"
    Rectangle { visible: card.primary; width: Style.space(2); height: parent.height; color: Color.accent }
    Rectangle {
      id: cardIcon
      x: Style.space(card.primary ? 14 : root.wide ? 12 : 4)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(card.primary ? 20 : 36); height: width
      color: card.primary ? "transparent" : Style.selectedFillFor(root.foreground, Color.accent)
      LucideIcon { anchors.centerIn: parent; glyph: card.glyph; color: Color.accent; fontFamily: root.fontFamily; size: Style.space(card.primary ? 18 : 16) }
    }
    Column {
      anchors.left: cardIcon.right; anchors.leftMargin: Style.space(12)
      anchors.right: parent.right; anchors.rightMargin: Style.space(card.trailing ? 32 : 12)
      anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
      Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: card.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: card.primary }
      Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: card.subtitle; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    LucideIcon {
      visible: card.trailing; anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
      glyph: card.primary ? "󰐊" : "󰅂"; color: card.primary ? Color.accent : root.dim; fontFamily: root.fontFamily; size: Style.space(16)
    }
    MouseArea { id: cardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.clicked() }
  }

  component WaveChoice: BorderSurface {
    id: choice
    property string label: ""
    property string glyph: ""
    property bool selected: false
    signal clicked()
    height: Style.space(28)
    color: selected ? Style.selectedFillFor(root.foreground, Color.accent)
      : choiceMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
    borderSpec: Border.controlSpec(selected ? "selected" : "normal", root.foreground, Color.accent)
    opacity: root.settingsRunning ? .5 : 1
    Row {
      anchors.centerIn: parent; spacing: Style.space(6)
      LucideIcon { visible: choice.glyph !== ""; glyph: choice.glyph; color: choice.selected ? Color.accent : root.dim; size: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
      Text { textFormat: Text.PlainText; text: choice.label; color: choice.selected ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { id: choiceMouse; anchors.fill: parent; hoverEnabled: true; enabled: !root.settingsRunning; cursorShape: Qt.PointingHandCursor; onClicked: if (!choice.selected) choice.clicked() }
  }

  // Home loads only generated-playlist metadata. Track pages remain on demand.
  Flickable {
    id: homeFlick
    visible: !root.waveOptionsOpen && root.controller.view === "home"
    anchors.fill: parent
    contentWidth: width
    contentHeight: homeColumn.implicitHeight + Style.space(root.wide ? 40 : 28)
    clip: true; boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    Column {
      id: homeColumn
      x: root.pad; y: Style.space(root.wide ? 20 : 14)
      width: homeFlick.width - root.pad * 2
      spacing: Style.space(root.wide ? 14 : 8)

      Rectangle {
        visible: root.wide
        width: parent.width; height: visible ? Style.space(200) : 0
        color: Style.normalFillFor(root.foreground, Color.accent)
        Rectangle { width: Style.space(2); height: parent.height; color: Color.accent }
        Item {
          id: inlineWaveHero
          width: Style.space(250); height: parent.height
          IconButton {
            id: waveOrb
            x: Style.space(20); y: Style.space(24)
            width: Style.space(60); height: width; radius: width / 2
            horizontalPadding: 0; verticalPadding: 0
            iconText: root.waveActive ? (root.wavePlaying ? "󰏤" : "󰐊") : "󰐷"
            iconSize: Style.space(22); foreground: Color.accent; bordered: true
            background: Style.selectedFillFor(root.foreground, Color.accent)
            enabled: !root.waveLoading
            tooltipText: root.waveActive ? (root.wavePlaying ? "Пауза" : "Продолжить") : "Запустить Мою волну"
            onClicked: root.waveActive ? root.wavePlaybackRequested() : root.waveRequested()
          }
          Column {
            anchors.left: waveOrb.right; anchors.leftMargin: Style.space(14)
            anchors.right: parent.right; anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: waveOrb.verticalCenter; spacing: Style.space(5)
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: "Моя волна"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: root.waveLoading ? "подключаем…" : root.waveActive ? (root.wavePlaying ? "играет сейчас" : "на паузе") : "под ваш вкус"; color: root.waveActive ? Color.accent : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Text {
            textFormat: Text.PlainText
            x: Style.space(20); y: Style.space(101); width: parent.width - Style.space(40)
            text: "Поток под ваш вкус. Лайки и пропуски его настраивают."
            wrapMode: Text.WordWrap; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          IconButton {
            x: Style.space(20); y: Style.space(150); width: parent.width - Style.space(40); height: Style.space(34)
            text: root.waveActive ? "Перезапустить" : "Запустить"; iconText: "󰐊"; fontSize: Style.font.caption
            foreground: Color.accent; bordered: true; enabled: !root.waveLoading && !root.settingsRunning
            onClicked: root.waveRequested()
          }
        }
        Column {
          anchors.left: inlineWaveHero.right; anchors.leftMargin: Style.space(8)
          anchors.right: parent.right; anchors.rightMargin: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
          Repeater {
            model: [{key:"waveMood", title:"НАСТРОЕНИЕ", options:root.moodOptions, fallback:"all"},
              {key:"waveDiversity", title:"ПОДБОР", options:root.diversityOptions, fallback:"default"},
              {key:"waveLanguage", title:"ЯЗЫК", options:root.languageOptions, fallback:"any"}]
            Column {
              id: waveGroup
              required property var modelData
              width: parent.width; spacing: Style.space(6)
              SectionLabel { text: modelData.title }
              Row {
                width: parent.width; spacing: Style.space(6)
                Repeater {
                  model: modelData.options
                  WaveChoice {
                    required property var modelData
                    width: (parent.width - parent.spacing * (waveGroup.modelData.options.length - 1)) / waveGroup.modelData.options.length
                    label: modelData.label; glyph: String(modelData.glyph || "")
                    selected: String(root.preference(waveGroup.modelData.key, waveGroup.modelData.fallback)) === modelData.value
                    onClicked: root.preferenceRequested(waveGroup.modelData.key, modelData.value)
                  }
                }
              }
            }
          }
        }
      }

      HubCard {
        visible: !root.wide; width: parent.width
        primary: true; glyph: "󰐷"; title: "Моя волна"
        subtitle: "Настроение: " + root.optionLabel(root.moodOptions, String(root.preference("waveMood", "all")), "Любое").toLowerCase() + " · Enter"
        onClicked: root.waveOptionsRequested()
      }

      Column {
        width: parent.width; spacing: Style.space(8)
        SectionLabel { topPadding: root.wide ? 0 : Style.space(6); text: "ВАША МУЗЫКА" }
        Grid {
          id: ownGrid
          width: parent.width; columns: root.wide ? 3 : 1
          columnSpacing: root.wide ? Style.space(10) : 0; rowSpacing: Style.space(8)
          readonly property real cellWidth: root.wide ? (width - columnSpacing * 2) / 3 : width
          HubCard {
            width: ownGrid.cellWidth; glyph: "󰋕"; title: "Мне нравится"
            subtitle: root.likesTotal >= 0 ? root.likesTotal + " треков" : "Любимые треки"
            onClicked: root.controller.activate({kind:"collection",command:"likes"})
          }
          Repeater {
            model: root.controller.ownPlaylists || []
            HubCard {
              required property var modelData
              width: ownGrid.cellWidth; glyph: "󰲸"; title: String(modelData.title || "Плейлист")
              subtitle: Number(modelData.count || 0) + " треков"
              onClicked: root.controller.activate({kind:"collection",command:"playlist",argument:String(modelData.kind || "")})
            }
          }
          HubCard {
            visible: root.wide; width: ownGrid.cellWidth; glyph: "󰋚"; title: "Недавно слушали"; subtitle: "История"
            onClicked: root.controller.openSection("history")
          }
        }
      }

      Column {
        width: parent.width; spacing: Style.space(8)
        Row {
          width: parent.width; spacing: Style.space(8)
          SectionLabel { topPadding: root.wide ? 0 : Style.space(6); text: "ДЛЯ ВАС"; width: parent.width - refreshPersonal.width - parent.spacing }
          IconButton {
            id: refreshPersonal
            iconText: "󰑐"; tooltipText: "Обновить подборки"
            text: root.controller.loading ? "Загружаем…" : String(root.controller.snapshot.error || root.controller.snapshot.warning || "") !== "" ? "Повторить" : ""
            fontSize: Style.font.caption
            horizontalPadding: Style.space(4); verticalPadding: 0; foreground: root.dim
            enabled: !root.controller.loading; onClicked: root.controller.requestHome(true)
          }
        }
        Row {
          width: parent.width; spacing: Style.space(root.wide ? 14 : 10)
          Repeater {
            model: root.wide ? root.personalOptions : root.personalOptions.slice(0, 4)
            Item {
              id: personalCard
              required property var modelData
              readonly property var value: root.personalItem(modelData.personalId)
              readonly property bool available: value !== null && value.available !== false && value.generationReady !== false
              width: (parent.width - parent.spacing * (root.wide ? 4 : 3)) / (root.wide ? 5 : 4)
              height: Style.space(root.wide ? 135 : 99)
              opacity: available || root.controller.loading ? 1 : .45
              Rectangle {
                id: personalCover
                width: parent.width; height: Style.space(root.wide ? 96 : 80)
                color: personalMouse.containsMouse && personalCard.available ? Style.hoverFillFor(root.foreground, Color.accent) : Style.selectedFillFor(root.foreground, Color.accent)
                LucideIcon { anchors.centerIn: parent; glyph: personalCard.modelData.glyph; size: Style.space(root.wide ? 28 : 22); color: root.dim; fontFamily: root.fontFamily }
                CatalogImage { anchors.fill: parent; requestedSource: personalCard.value ? String(personalCard.value.artUrl || "") : ""; foreground: root.foreground; fontFamily: root.fontFamily; fillMode: Image.PreserveAspectCrop }
              }
              Text {
                textFormat: Text.PlainText
                anchors.top: personalCover.bottom; anchors.topMargin: Style.space(6)
                width: parent.width; elide: Text.ElideRight; text: personalCard.modelData.title
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(root.wide ? 11 : 10)
              }
              Text {
                textFormat: Text.PlainText
                visible: root.wide; anchors.top: personalCover.bottom; anchors.topMargin: Style.space(27)
                width: parent.width; elide: Text.ElideRight
                text: personalCard.value && personalCard.value.subtitle ? personalCard.value.subtitle
                  : personalCard.available ? personalCard.modelData.subtitle : root.controller.loading ? "Загружаем…" : "Недоступно"
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(9)
              }
              MouseArea {
                id: personalMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: personalCard.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (personalCard.available) root.controller.activate({kind:"playlist",value:personalCard.value})
              }
            }
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: String(root.controller.snapshot.error || root.controller.snapshot.warning || "") !== ""
          width: parent.width; wrapMode: Text.WordWrap
          text: String(root.controller.snapshot.error || root.controller.snapshot.warning || "")
          color: root.controller.snapshot.error ? Color.urgent : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }

      Column {
        width: parent.width; spacing: Style.space(8)
        SectionLabel { topPadding: root.wide ? 0 : Style.space(6); text: root.wide ? "ЕЩЁ В МЕДИАТЕКЕ" : "ЕЩЁ" }
        Row {
          visible: root.wide; width: parent.width; spacing: Style.space(8)
          Repeater {
            model: root.moreSections
            IconButton {
              required property var modelData
              width: (parent.width - parent.spacing * 3) / 4; height: Style.space(31)
              iconText: modelData.glyph; text: modelData.title; fontSize: Style.font.caption
              foreground: root.dim; bordered: true; leftAlign: true
              onClicked: root.controller.openSection(modelData.section)
            }
          }
        }
        HubCard {
          visible: !root.wide; width: parent.width; glyph: "󰋚"; title: "Недавно слушали"; subtitle: "Треки и контексты из истории"
          onClicked: root.controller.openSection("history")
        }
        Item {
          visible: !root.wide; width: parent.width; height: visible ? Style.space(44) : 0
          Rectangle {
            x: Style.space(4); anchors.verticalCenter: parent.verticalCenter; width: Style.space(36); height: width
            color: Style.selectedFillFor(root.foreground, Color.accent)
            LucideIcon { anchors.centerIn: parent; glyph: "󰀥"; size: Style.space(16); color: Color.accent }
          }
          Column {
            x: Style.space(52); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
            Row {
              spacing: Style.space(4)
              Repeater {
                model: [{title:"Альбомы",section:"albums"},{title:"Исполнители",section:"artists"}]
                Text {
                  required property var modelData
                  required property int index
                  textFormat: Text.PlainText
                  text: (index === 0 ? "" : "· ") + modelData.title; color: albumArtistMouse.containsMouse ? Color.accent : root.foreground
                  font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  MouseArea { id: albumArtistMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.controller.openSection(parent.modelData.section) }
                }
              }
            }
            Text { textFormat: Text.PlainText; text: "Любимое"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          IconButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26); height: width; horizontalPadding: 0; verticalPadding: 0
            iconText: "󰲸"; tooltipText: "Сохранённые плейлисты"; foreground: root.dim
            onClicked: root.controller.openSection("playlists")
          }
        }
        HubCard {
          visible: !root.wide; width: parent.width; glyph: "󰐹"; title: "Станции"; subtitle: "Жанры, эпохи, настроения"
          onClicked: root.controller.openSection("stations")
        }
      }
    }
  }

  // ── section (loaded lazily) ───────────────────────────────────────────
  Item {
    id: sectionView
    visible: !root.waveOptionsOpen && root.controller.view !== "home"
    anchors.fill: parent

    Item {
      id: historyHero
      visible: root.wide && root.controller.section === "history"
      anchors.top: parent.top
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      height: visible ? Style.space(104) : 0
      Rectangle {
        id: historyCover
        width: Style.space(104); height: width
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.foreground, Color.accent)
        LucideIcon {
          anchors.centerIn: parent
          name: "history"; color: Color.accent; size: Style.space(36)
        }
      }
      Column {
        anchors.left: historyCover.right; anchors.leftMargin: Style.space(20)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        SectionLabel { text: "РАЗДЕЛ"; color: Color.accent }
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: "Недавно слушали"; color: root.foreground
          font.family: root.fontFamily; font.pixelSize: Style.space(26)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: "Треки и плейлисты из истории · "
            + (root.controller.snapshot.items || []).length + " из "
            + Number(root.controller.snapshot.total || 0)
          color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
      }
    }

    TextField {
      id: stationSearchField
      visible: root.controller.stationMode
      anchors.top: historyHero.bottom; anchors.topMargin: visible ? Style.space(14) : 0
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      height: visible ? Style.space(36) : 0
      placeholderText: "Найти радиостанцию"
      foreground: root.foreground
      font.family: root.fontFamily
      text: root.controller.stationQuery
      onTextEdited: {
        root.controller.setStationQuery(text)
        libraryList.positionViewAtBeginning()
      }
      onVisibleChanged: {
        if (visible) {
          Qt.callLater(function() {
            if (stationSearchField.visible && root.panelOpened && root.visible && !root.settingsOpen)
              stationSearchField.forceActiveFocus()
          })
        } else {
          focus = false
          Qt.callLater(function() {
            if (root.panelOpened && !root.settingsOpen && root.focusTarget)
              root.focusTarget.forceActiveFocus()
          })
        }
      }
      Keys.onEscapePressed: {
        if (text !== "") {
          root.controller.setStationQuery("")
          libraryList.positionViewAtBeginning()
        } else {
          focus = false
          if (root.focusTarget) root.focusTarget.forceActiveFocus()
        }
      }
    }

    SkeletonList {
      visible: root.controller.loading
      anchors.top: stationSearchField.visible ? stationSearchField.bottom : historyHero.bottom
      anchors.topMargin: Style.space(historyHero.visible ? 18 : 14)
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      rowCount: 7
      foreground: root.foreground
    }

    ListView {
      id: libraryList
      property bool stationPageScheduled: false
      visible: !root.controller.loading
      anchors.top: stationSearchField.visible ? stationSearchField.bottom : historyHero.bottom
      anchors.topMargin: Style.space(historyHero.visible ? 18 : 14)
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: Math.max(0, height * 2)
      model: root.controller.rows
      spacing: root.controller.section === "history" ? 0 : Style.space(2)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      function requestStationPageNearEnd() {
        if (stationPageScheduled || !root.controller.stationMode
            || !root.controller.hasMore) return
        var remaining = contentHeight - (contentY + height)
        if (remaining > Style.space(116)) return
        stationPageScheduled = true
        Qt.callLater(function() {
          stationPageScheduled = false
          var currentRemaining = contentHeight - (contentY + height)
          if (root.controller.stationMode && root.controller.hasMore
              && currentRemaining <= Style.space(116))
            root.controller.requestMore()
        })
      }

      onContentYChanged: requestStationPageNearEnd()
      onContentHeightChanged: requestStationPageNearEnd()
      onHeightChanged: requestStationPageNearEnd()
      onMovementEnded: requestStationPageNearEnd()

      delegate: BorderSurface {
        id: libraryRow
        required property var modelData
        readonly property string rowKind: String(modelData.kind || "")
        readonly property var value: modelData.value || ({})
        readonly property bool entityRow: ["track", "artist", "album", "playlist", "station"].indexOf(rowKind) >= 0
        readonly property bool actionable: ["retry", "loadMore",
          "track", "artist", "album", "playlist", "station"].indexOf(rowKind) >= 0
        readonly property bool hovered: libraryHover.hovered
        width: libraryList.width
          - (libraryList.contentHeight > libraryList.height ? Style.space(8) : 0)
        height: rowKind === "track" ? Style.space(root.wide ? 52 : 48)
          : entityRow ? Style.space(56) : Style.space(40)
        visible: height > 0
        radius: Style.cornerRadius
        opacity: libraryRow.value.available === false ? .45 : 1
        color: actionable && libraryRow.value.available !== false && libraryRow.hovered
          ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
        borderSpec: Border.none()

        HoverHandler { id: libraryHover }

        Text {
          textFormat: Text.PlainText
          visible: ["error", "warning", "empty", "retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter
          text: String(libraryRow.modelData.title || "")
          color: libraryRow.rowKind === "error" ? Color.urgent
            : (["retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0 ? Color.accent : root.dim)
          horizontalAlignment: ["retry", "loadMore", "empty"].indexOf(libraryRow.rowKind) >= 0
            ? Text.AlignHCenter : Text.AlignLeft
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          font.bold: ["retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0
        }

        Row {
          z: 2
          visible: libraryRow.entityRow
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(9); anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          CatalogImage {
            width: Style.space(40); height: width
            requestedSource: String(libraryRow.value.artUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Column {
            width: parent.width - Style.space(52)
              - (libraryRow.rowKind === "track" ? Style.space(35) : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(libraryRow.value.title || libraryRow.value.name || "Без названия")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: {
                var details = String(libraryRow.value.artist || libraryRow.value.ownerName
                  || libraryRow.value.subtitle || (libraryRow.value.genres || []).join(", ") || "")
                if (details === "" && Number(libraryRow.value.trackCount || 0) > 0)
                  details = Number(libraryRow.value.trackCount) + " треков"
                var date = String(libraryRow.value.historyDate || "")
                return details + (date !== "" ? (details !== "" ? " · " : "") + date : "")
              }
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.caption; elide: Text.ElideRight
            }
          }
          Item {
            visible: libraryRow.rowKind === "track"
            width: visible ? Style.space(26) : 0
            height: Style.space(26)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              visible: !libraryRow.hovered
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
              text: {
                var seconds = Math.max(0, Math.round(Number(libraryRow.value.duration || 0)))
                return seconds > 0 ? Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0") : ""
              }
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            IconButton {
              id: libraryTrackAction
              visible: libraryRow.hovered
              anchors.fill: parent
              horizontalPadding: 0; verticalPadding: 0
              iconText: "󰐒"; iconSize: Style.font.icon
              tooltipText: "В плейлист…"
              foreground: hot ? Color.accent : root.dim
              onClicked: root.collectionTrackRequested(
                Number(libraryRow.value.trackIndex || 0), libraryRow.value, libraryTrackAction)
            }
          }
        }

        MouseArea {
          id: libraryMouse
          anchors.fill: parent
          anchors.rightMargin: libraryRow.rowKind === "track" ? Style.space(36) : 0
          enabled: libraryRow.actionable
            && libraryRow.value.available !== false
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.controller.activate(libraryRow.modelData)
        }
      }
    }
  }

  // ── My Wave ───────────────────────────────────────────────────────────
  Item {
    id: wavePage
    visible: root.waveOptionsOpen
    anchors.fill: parent

    Flickable {
      id: waveOptionsFlick
      anchors.fill: parent
      anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
      anchors.topMargin: Style.space(root.wide ? 0 : 14)
      contentWidth: width
      contentHeight: waveLayout.height + Style.space(root.wide ? 24 : 14)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Item {
        id: waveLayout
        width: waveOptionsFlick.width
        height: root.wide
          ? Math.max(Style.space(380), waveOptionsFlick.height - Style.space(24))
          : Style.space(270 + 20 + 24) + waveColumn.implicitHeight + waveNote.height

        Rectangle {
          id: waveHero
          objectName: "waveHero"
          width: root.wide ? Style.space(280) : parent.width
          height: root.wide ? parent.height : Style.space(270)
          color: Style.normalFillFor(root.foreground, Color.accent)

          Canvas {
            anchors.fill: parent
            property color accent: Color.accent
            onAccentChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              var glow = ctx.createRadialGradient(width / 2, height * .32, 0,
                width / 2, height * .32, width * .7)
              glow.addColorStop(0, Qt.rgba(accent.r, accent.g, accent.b, .16))
              glow.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0))
              ctx.fillStyle = glow
              ctx.fillRect(0, 0, width, height)
            }
          }
          Item {
            id: orbWrap
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.topMargin: Style.space(24)
            anchors.bottom: waveTitle.top; anchors.bottomMargin: Style.space(14)
            Rectangle {
              anchors.centerIn: parent
              width: Style.space(root.wide ? 150 : 88); height: width; radius: width / 2
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .2)
              Canvas {
                anchors.centerIn: parent
                width: Style.space(root.wide ? 104 : 64); height: width
                property color accent: Color.accent
                onAccentChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.clearRect(0, 0, width, height)
                  var glow = ctx.createRadialGradient(width / 2, height / 2, 0,
                    width / 2, height / 2, width / 2)
                  glow.addColorStop(0, accent)
                  glow.addColorStop(.75, Qt.rgba(accent.r, accent.g, accent.b, .22))
                  glow.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0))
                  ctx.fillStyle = glow
                  ctx.fillRect(0, 0, width, height)
                }
                LucideIcon {
                  anchors.centerIn: parent
                  glyph: "󰐹"; color: Color.background
                  size: Style.space(root.wide ? 34 : 26)
                }
              }
            }
          }
          Text {
            id: waveTitle
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: Style.space(24); anchors.rightMargin: Style.space(24)
            anchors.bottom: waveDescription.top; anchors.bottomMargin: Style.space(14)
            textFormat: Text.PlainText
            text: "Моя волна"; color: root.foreground
            font.family: root.fontFamily; font.pixelSize: Style.space(22); font.bold: true
          }
          Text {
            id: waveDescription
            anchors.left: waveTitle.left; anchors.right: waveTitle.right
            anchors.bottom: waveStart.top; anchors.bottomMargin: Style.space(14)
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            text: "Бесконечный поток, который подстраивается под лайки и пропуски."
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(11)
          }
          IconButton {
            id: waveStart
            objectName: "waveStart"
            anchors.left: waveTitle.left; anchors.right: waveTitle.right
            anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(24)
            height: Style.space(36)
            text: root.settingsRunning ? "Сохраняем…" : root.waveLoading ? "Подключаем…" : "Запустить  ⏎"
            iconText: "󰐊"; iconSize: Style.space(14); fontSize: Style.space(12)
            fontFamily: root.fontFamily
            foreground: Color.background; background: Color.accent
            focusable: true
            enabled: !root.settingsRunning && !root.waveLoading
            onClicked: root.waveRequested()
          }
        }

        Item {
          id: waveSettings
          x: root.wide ? waveHero.width + Style.space(28) : 0
          y: root.wide ? 0 : waveHero.height + Style.space(20)
          width: root.wide ? parent.width - x : parent.width
          height: root.wide ? parent.height : waveColumn.implicitHeight + Style.space(24) + waveNote.height

          Column {
            id: waveColumn
            width: parent.width
            spacing: Style.space(12)

            SectionLabel { text: "НАСТРОЕНИЕ"; font.pixelSize: Style.space(10) }
            Row {
              width: parent.width; spacing: Style.space(8)
              Repeater {
                model: root.moodOptions
                OptionTile {
                  required property var modelData
                  width: (waveColumn.width - Style.space(8) * 4) / 5
                  height: Style.space(root.wide ? 71 : 62)
                  glyph: modelData.glyph; title: modelData.label
                  selected: String(root.preference("waveMood", "all")) === modelData.value
                  busy: root.settingsRunning
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  onClicked: root.preferenceRequested("waveMood", modelData.value)
                }
              }
            }
            SectionLabel { text: "ПОДБОР ТРЕКОВ"; font.pixelSize: Style.space(10) }
            Flow {
              width: parent.width; spacing: Style.space(8)
              Repeater {
                model: root.diversityOptions
                OptionTile {
                  required property var modelData
                  vertical: false
                  width: (waveColumn.width - Style.space(8)) / 2
                  height: Style.space(root.wide ? 56 : 48)
                  glyph: modelData.glyph; title: modelData.label; subtitle: modelData.sub
                  selected: String(root.preference("waveDiversity", "default")) === modelData.value
                  busy: root.settingsRunning
                  foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                  onClicked: root.preferenceRequested("waveDiversity", modelData.value)
                }
              }
            }
            SectionLabel { text: "ЯЗЫК"; font.pixelSize: Style.space(10) }
            MusicSegmented {
              width: parent.width
              equalWidth: true; cellHeight: Style.space(34)
              options: root.languageOptions
              value: String(root.preference("waveLanguage", "any"))
              busy: root.settingsRunning
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              onChanged: function(next) { root.preferenceRequested("waveLanguage", next) }
            }
          }
          Item {
            id: waveNote
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: noteText.implicitHeight
            LucideIcon {
              anchors.left: parent.left; anchors.top: parent.top
              glyph: "󰋽"; color: root.dim; size: Style.space(12)
            }
            Text {
              id: noteText
              anchors.left: parent.left; anchors.leftMargin: Style.space(20)
              anchors.right: parent.right
              textFormat: Text.PlainText; wrapMode: Text.WordWrap
              text: "Настройки применяются только к «Моей волне», не к радио по треку"
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10)
            }
          }
        }
      }
    }
  }
}
