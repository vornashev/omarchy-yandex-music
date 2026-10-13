import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Settings (design p2voD/GiP8C/o7ky4): «Основные» and «Верхний бар» tabs.
// Wide splits each tab into two columns; compact stacks one dense column.
// The bar tab starts with a clickable preview of the top-bar player.
Item {
  id: root

  required property var panel
  property bool wide: false
  property string tab: "general"
  // Bar element hovered in the list or the preview; both highlight it.
  property string hotKey: ""
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property color accentFill: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, .08)
  readonly property real gutter: wide ? Style.space(28) : Style.space(16)
  readonly property real columnGap: Style.space(32)
  readonly property real columnWidth: wide ? (width - gutter * 2 - columnGap) / 2 : width - gutter * 2
  readonly property alias flick: flick

  function pref(key, fallback) { return panel.preference(key, fallback) }
  function elementByKey(key) {
    for (var i = 0; i < elements.length; i++) if (elements[i].key === key) return elements[i]
    return null
  }
  function on(key) {
    var item = elementByKey(key)
    return Boolean(pref(key, item ? item.fallback : true))
  }
  function toggle(key) { panel.setPreference(key, !on(key)) }
  function selectTab(name) {
    if (tab === name) return
    tab = name
    hotKey = ""
    flick.contentY = 0
  }

  // Top-bar elements in their on-screen order, left to right.
  readonly property var elements: [
    { key: "showControls", icon: "skip-forward", label: "Кнопки плеера", short: "Кнопки",
      note: "назад · пауза · далее", fallback: true },
    { key: "showCover", icon: "image", label: "Обложка", short: "Обложка",
      note: "клик открывает попап", fallback: true },
    { key: "showArtist", icon: "user-round", label: "Исполнитель", short: "Исполнитель", note: "", fallback: true },
    { key: "showTitle", icon: "type", label: "Название трека", short: "Название", note: "", fallback: true },
    { key: "showLike", icon: "heart", label: "Кнопка «Нравится»", short: "Нравится", note: "", fallback: false },
    { key: "showTime", icon: "clock-3", label: "Время трека", short: "Время", note: "", fallback: false },
    { key: "showBarLyrics", icon: "captions", label: "Субтитры", short: "Субтитры",
      note: "синхронный текст песни", fallback: false },
    { key: "showVolume", icon: "volume-2", label: "Громкость", short: "Громкость",
      note: "колесо мыши меняет", fallback: true },
    { key: "showProgress", icon: "minus", label: "Линия прогресса", short: "Прогресс",
      note: "под всем плеером", fallback: true }]

  readonly property var layoutOptions: [
    // { value: "mini", label: "Mini" }, // Отложено до будущего обновления.
    { value: "compact", label: "Компакт", icon: "panel-left" },
    { value: "wide", label: "Широкий", icon: "columns-3" }]
  readonly property var qualityOptions: [
    { value: "best", label: wide ? "Лучшее доступное" : "Лучшее", icon: "audio-lines" },
    { value: "economy", label: wide ? "Экономия трафика" : "Экономия", icon: "gauge" }]
  readonly property var shapeOptions: wide
    ? [{ value: "square", label: "Квадрат", shape: "square" },
      { value: "rounded", label: "Скругл.", shape: "rounded" },
      { value: "circle", label: "Круг", shape: "circle" }]
    : [{ value: "square", label: "Квадр." }, { value: "rounded", label: "Скругл." },
      { value: "circle", label: "Круг" }]
  readonly property var titleOptions: [{ value: "truncate", label: wide ? "Многоточие" : "Обрезать" },
    { value: "scroll", label: wide ? "Прокрутка" : "Бегущая" }]
  readonly property var notifyOptions: [{ value: "off", label: "Выключены" },
    { value: "all", label: wide ? "Показывать всегда" : "Всегда" }]
  readonly property var restoreOptions: [
    { key: "restoreQueue", label: "Очередь", icon: "list-music" },
    { key: "restorePosition", label: "Позицию", icon: "timer" },
    { key: "restoreVolume", label: "Громкость", icon: "volume-2" }]

  readonly property string previewArtist: String(panel.data.artist || "") || "Исполнитель"
  readonly property string previewTitle: String(panel.data.title || "") || "Трек"
  readonly property string previewLyric: {
    var index = panel.lyricsCurrentIndex
    var line = index >= 0 && index < panel.lyricsLines.length
      ? String(panel.lyricsLines[index].text || "").trim() : ""
    return line !== "" ? line : "Текст песни"
  }
  readonly property real previewProgress: panel.hasTrack
    ? Math.max(0, Math.min(1, panel.displayPosition / Math.max(1, Number(panel.data.duration || 1)))) : .3

  // ── building blocks ────────────────────────────────────────────────────
  component SectionLabel: Item {
    id: section
    property alias text: sectionTitle.text
    property string note: ""
    property real topGap: 0
    property real bottomGap: root.wide ? Style.space(6) : 0
    width: parent ? parent.width : 0
    height: topGap + sectionTitle.implicitHeight + bottomGap
    Text {
      id: sectionTitle
      y: section.topGap
      textFormat: Text.PlainText
      color: Color.accent
      font.family: root.ff; font.pixelSize: Style.font.caption
      font.bold: true; font.letterSpacing: Style.space(1.6)
    }
    Text {
      visible: section.note !== ""
      anchors.right: parent.right; anchors.verticalCenter: sectionTitle.verticalCenter
      textFormat: Text.PlainText
      text: section.note; color: root.dim
      font.family: root.ff; font.pixelSize: Style.font.caption
    }
  }
  component PrefSwitch: ToggleSwitch {
    trackHeight: Style.space(16)
    cursorRing: false
    foreground: root.fg
    busy: panel.settingsBusy
  }
  component ToggleRow: SettingRow {
    id: toggleRow
    property string key: ""
    property bool fallback: true
    width: parent ? parent.width : 0
    divider: false
    minHeight: Style.space(32)
    foreground: root.fg; dim: root.dim; fontFamily: root.ff
    PrefSwitch {
      checked: Boolean(root.pref(toggleRow.key, toggleRow.fallback))
      onToggled: panel.setPreference(toggleRow.key, !checked)
    }
  }
  component Field: Column {
    id: field
    property string label: ""
    property string note: ""
    property string key: ""
    property string fallback: ""
    property var options: []
    property int cellHeight: root.wide ? Style.space(25) : Style.space(23)
    // Optional override; by default the value is stored as a plain preference.
    property var pickHandler: null
    width: parent ? parent.width : 0
    spacing: Style.space(6)
    Item {
      width: parent.width; height: fieldLabel.implicitHeight
      Text {
        id: fieldLabel
        textFormat: Text.PlainText
        width: parent.width - (fieldNote.visible ? fieldNote.implicitWidth + Style.space(8) : 0)
        elide: Text.ElideRight
        text: field.label; color: root.fg
        font.family: root.ff; font.pixelSize: root.wide ? Style.font.body : Style.font.bodySmall
      }
      Text {
        id: fieldNote
        visible: field.note !== ""
        anchors.right: parent.right; anchors.verticalCenter: fieldLabel.verticalCenter
        textFormat: Text.PlainText
        text: field.note; color: root.dim
        font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }
    MusicSegmented {
      width: parent.width
      equalWidth: true
      options: field.options
      value: String(root.pref(field.key, field.fallback))
      busy: panel.settingsBusy
      cellHeight: field.cellHeight
      fontSize: root.wide ? Style.font.bodySmall : Style.font.caption
      foreground: root.fg; dim: root.dim; fontFamily: root.ff
      onChanged: function(next) {
        if (field.pickHandler) field.pickHandler(next)
        else panel.setPreference(field.key, next)
      }
    }
  }

  // Bar area width: label on the left, «− 260 px +» stepper on the right.
  // Clicks change a local pending value at once; the preference is written
  // after a short pause so rapid clicks and press-and-hold are never dropped.
  component WidthRow: Item {
    id: widthRow
    property string label: ""
    property string description: ""
    property string key: ""
    property string controlName: ""
    property int fallback: 0
    property int minimum: 100
    property int maximum: 500
    property bool active: true
    readonly property int stored: {
      var value = Number(root.pref(key, fallback))
      return isFinite(value) && value > 0 ? value : fallback
    }
    property int pending: -1
    readonly property int value: pending >= 0 ? pending : stored
    width: parent ? parent.width : 0
    height: Math.max(widthTexts.implicitHeight, stepper.height) + Style.space(4)

    onStoredChanged: if (stored === pending) pending = -1
    function step(delta) {
      if (!active) return
      var next = Math.max(minimum, Math.min(maximum, Math.round((value + delta) / 10) * 10))
      if (next === value) return
      pending = next
      commitTimer.restart()
    }
    Timer {
      id: commitTimer
      interval: 450
      onTriggered: {
        if (widthRow.pending < 0) return
        if (panel.settingsBusy) { restart(); return }
        panel.setPreference(widthRow.key, widthRow.pending)
      }
    }
    Timer {
      id: repeatTimer
      property int delta: 0
      interval: 380; repeat: true
      onTriggered: { interval = 70; widthRow.step(delta) }
    }

    Column {
      id: widthTexts
      anchors.left: parent.left
      anchors.right: stepper.left; anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      opacity: widthRow.active ? 1 : .5
      Behavior on opacity { NumberAnimation { duration: 120 } }
      Text {
        width: parent.width; elide: Text.ElideRight
        textFormat: Text.PlainText
        text: widthRow.label; color: root.fg
        font.family: root.ff; font.pixelSize: root.wide ? Style.font.body : Style.font.bodySmall
      }
      Text {
        width: parent.width; elide: Text.ElideRight
        textFormat: Text.PlainText
        text: widthRow.description; color: root.dim
        font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }
    BorderSurface {
      id: stepper
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: Style.space(root.wide ? 136 : 128); height: Style.space(root.wide ? 28 : 26)
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.fg, Color.accent)
      borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
      opacity: widthRow.active ? 1 : .4
      Behavior on opacity { NumberAnimation { duration: 120 } }

      Repeater {
        model: [{ delta: -10, icon: "minus", name: "Minus", tip: "Уже" },
          { delta: 10, icon: "plus", name: "Plus", tip: "Шире" }]
        Item {
          id: stepButton
          required property var modelData
          readonly property bool enabledStep: widthRow.active && (modelData.delta < 0
            ? widthRow.value > widthRow.minimum : widthRow.value < widthRow.maximum)
          objectName: widthRow.controlName + modelData.name
          x: modelData.delta < 0 ? 0 : stepper.width - width
          width: stepper.height + Style.space(2); height: stepper.height
          Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: Math.max(0, stepper.radius - 1)
            color: stepMouse.pressed && stepButton.enabledStep ? root.accentFill
              : (stepMouse.containsMouse && stepButton.enabledStep
                ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
          }
          LucideIcon {
            anchors.centerIn: parent
            name: stepButton.modelData.icon
            color: !stepButton.enabledStep ? Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .4)
              : (stepMouse.containsMouse ? Color.accent : root.fg)
            size: Style.space(13)
          }
          MouseArea {
            id: stepMouse
            anchors.fill: parent; hoverEnabled: true
            enabled: widthRow.active
            cursorShape: stepButton.enabledStep ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: {
              widthRow.step(stepButton.modelData.delta)
              repeatTimer.delta = stepButton.modelData.delta
              repeatTimer.interval = 380
              repeatTimer.restart()
            }
            onReleased: repeatTimer.stop()
            onCanceled: repeatTimer.stop()
          }
        }
      }
      Rectangle {
        x: stepper.height + Style.space(2); width: 1
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: Style.space(6)
        color: root.hairline
      }
      Rectangle {
        x: stepper.width - stepper.height - Style.space(2) - 1; width: 1
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: Style.space(6)
        color: root.hairline
      }
      Row {
        anchors.centerIn: parent
        spacing: Style.space(4)
        Text {
          objectName: widthRow.controlName + "Value"
          anchors.baseline: unitText.baseline
          textFormat: Text.PlainText
          text: String(widthRow.value)
          color: widthRow.pending >= 0 ? Color.accent : root.fg
          font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true
          Behavior on color { ColorAnimation { duration: 160 } }
        }
        Text {
          id: unitText
          textFormat: Text.PlainText
          text: "px"; color: root.dim
          font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }
      // The wheel over the value steps too; it never reaches the page Flickable.
      MouseArea {
        x: stepper.height + Style.space(2); width: stepper.width - x * 2; height: parent.height
        enabled: widthRow.active
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          if (wheel.angleDelta.y !== 0) widthRow.step(wheel.angleDelta.y > 0 ? 10 : -10)
        }
      }
    }
  }

  // One row of the wide «Элементы бара» list.
  component ElementRow: Item {
    id: elementRow
    required property var modelData
    required property int index
    readonly property bool checked: root.on(modelData.key)
    readonly property bool hot: root.hotKey === modelData.key
    width: parent ? parent.width : 0
    height: Style.space(30)
    Rectangle {
      anchors.fill: parent
      color: elementRow.hot ? root.accentFill : "transparent"
    }
    LucideIcon {
      id: elementIcon
      anchors.left: parent.left; anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      name: elementRow.modelData.icon
      color: elementRow.checked ? root.fg : root.dim
      size: Style.space(14)
    }
    Row {
      anchors.left: elementIcon.right; anchors.leftMargin: Style.space(10)
      anchors.right: elementSwitch.left; anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      clip: true
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: elementRow.modelData.label
        color: elementRow.checked ? root.fg : root.dim
        font.family: root.ff; font.pixelSize: Style.font.body
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: elementRow.modelData.note !== ""
        textFormat: Text.PlainText
        text: elementRow.modelData.note; color: root.dim
        font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }
    PrefSwitch {
      id: elementSwitch
      anchors.right: parent.right; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      interactive: false
      checked: elementRow.checked
    }
    Rectangle {
      visible: elementRow.index < root.elements.length - 1
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: 1; color: root.hairline
    }
    MouseArea {
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: root.hotKey = containsMouse ? elementRow.modelData.key
        : (root.hotKey === elementRow.modelData.key ? "" : root.hotKey)
      onClicked: if (!panel.settingsBusy) root.toggle(elementRow.modelData.key)
    }
  }

  // Selectable tile: compact bar elements and the restore-on-start chips.
  component Tile: BorderSurface {
    id: tile
    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool stacked: false
    signal activated()
    radius: Style.cornerRadius
    color: tile.checked ? root.accentFill
      : (tileMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
    borderSpec: Border.controlSpec(tile.checked ? "selected" : "normal", root.fg, Color.accent)
    Row {
      visible: !tile.stacked
      anchors.left: parent.left; anchors.leftMargin: Style.space(8)
      anchors.right: parent.right; anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(7)
      LucideIcon {
        id: tileIcon
        anchors.verticalCenter: parent.verticalCenter
        name: tile.icon; color: tile.checked ? Color.accent : root.dim
        size: Style.space(13)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - tileIcon.width - parent.spacing; elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tile.label; color: tile.checked ? root.fg : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
      }
    }
    Item {
      visible: tile.stacked
      anchors.fill: parent; anchors.margins: Style.space(10)
      LucideIcon {
        anchors.left: parent.left; anchors.top: parent.top
        name: tile.icon; color: tile.checked ? Color.accent : root.dim
        size: Style.space(15)
      }
      LucideIcon {
        anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: Style.space(1)
        name: tile.checked ? "square-check" : "square"
        color: tile.checked ? Color.accent : root.dim
        size: Style.space(13)
      }
      Text {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tile.label; color: tile.checked ? root.fg : root.dim
        font.family: root.ff; font.pixelSize: Style.font.body
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!panel.settingsBusy) tile.activated()
    }
  }

  component RestoreChips: Row {
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    Repeater {
      model: root.restoreOptions
      Tile {
        required property var modelData
        width: (parent.width - Style.space(16)) / 3
        height: root.wide ? Style.space(59) : Style.space(52)
        stacked: true
        icon: modelData.icon; label: modelData.label
        checked: Boolean(root.pref(modelData.key, true))
        onActivated: panel.setPreference(modelData.key, !checked)
      }
    }
  }

  component AccountCard: BorderSurface {
    width: parent ? parent.width : 0
    height: accountColumn.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
    Column {
      id: accountColumn
      x: Style.space(12); y: Style.space(12)
      width: parent.width - Style.space(24)
      spacing: Style.space(10)
      Item {
        width: parent.width
        height: Math.max(accountText.implicitHeight, logoutButton.implicitHeight)
        LucideIcon {
          id: accountIcon
          anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
          name: "circle-check"; color: Color.accent; size: Style.space(16)
        }
        Column {
          id: accountText
          anchors.left: accountIcon.right; anchors.leftMargin: Style.space(12)
          anchors.right: logoutButton.left; anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          Text {
            width: parent.width; elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.wide ? "Яндекс Музыка подключена" : "Подключено"
            color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width; elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "Выход удалит токен авторизации"
            color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
          }
        }
        IconButton {
          id: logoutButton
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          visible: !panel.confirmLogout
          width: visible ? implicitWidth : 0
          text: "Выйти"; foreground: Color.urgent; bordered: true
          fontSize: Style.font.bodySmall
          onClicked: panel.confirmLogout = true
        }
      }
      // Confirmation gets its own rows so the buttons never cover the status text.
      Text {
        visible: panel.confirmLogout
        width: parent.width; wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "Токен авторизации будет удалён. Для повторного входа понадобится браузер."
        color: Color.urgent; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Row {
        visible: panel.confirmLogout
        anchors.right: parent.right
        spacing: Style.space(8)
        IconButton {
          text: "Отмена"; foreground: root.fg; bordered: true
          fontSize: Style.font.bodySmall
          onClicked: panel.confirmLogout = false
        }
        IconButton {
          text: "Подтвердить выход"; foreground: Color.urgent; bordered: true
          fontSize: Style.font.bodySmall
          onClicked: {
            panel.intent("logout")
            panel.closeSettings()
          }
        }
      }
    }
  }

  // Preview slot: hidden elements stay dimmed in wide and vanish in compact.
  component PreviewSlot: BorderSurface {
    id: slot
    property string key: ""
    readonly property real pad: Style.space(root.wide ? 6 : 4)
    default property alias content: slotRow.data
    readonly property bool checked: root.on(key)
    readonly property bool hot: root.hotKey === key
    visible: checked || root.wide
    opacity: checked ? 1 : .3
    clip: true
    implicitWidth: slotRow.implicitWidth + pad * 2
    implicitHeight: slotRow.implicitHeight + Style.space(root.wide ? 8 : 6)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: Math.min(implicitWidth, Style.space(28))
    Layout.alignment: Qt.AlignVCenter
    radius: Style.cornerRadius
    color: hot ? root.accentFill
      : (slotMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
    borderSpec: hot ? Border.controlSpec("selected", root.fg, Color.accent) : Border.none()
    Row {
      id: slotRow
      x: slot.pad
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(root.wide ? 6 : 5)
    }
    MouseArea {
      id: slotMouse
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: root.hotKey = containsMouse ? slot.key
        : (root.hotKey === slot.key ? "" : root.hotKey)
      onClicked: if (!panel.settingsBusy) root.toggle(slot.key)
    }
  }
  // Text slot that the preview layout may shrink, eliding its text.
  component PreviewTextSlot: PreviewSlot {
    id: textSlot
    property alias text: slotText.text
    property alias textColor: slotText.color
    property real cap: Style.space(140)
    implicitWidth: Math.min(slotText.implicitWidth, cap) + pad * 2
    Layout.fillWidth: true
    Layout.maximumWidth: implicitWidth
    PreviewText { id: slotText; maxWidth: textSlot.width - textSlot.pad * 2 }
  }
  component PreviewText: Text {
    property real maxWidth: Style.space(200)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: Math.max(0, Math.min(implicitWidth, maxWidth))
    elide: Text.ElideRight
    textFormat: Text.PlainText
    color: root.fg; font.family: root.ff
    font.pixelSize: root.wide ? Style.font.bodySmall : Style.font.caption
  }

  component BarPreview: BorderSurface {
    id: strip
    readonly property real iconSize: Style.space(root.wide ? 13 : 11)
    readonly property bool progressOn: root.on("showProgress")
    width: parent ? parent.width : 0
    height: root.wide ? Style.space(40) : Style.space(34)
    radius: Style.cornerRadius
    clip: true
    color: Style.normalFillFor(root.fg, Color.accent)
    borderSpec: Border.controlSpec("normal", root.fg, Color.accent)

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(root.wide ? 10 : 8)
      anchors.rightMargin: Style.space(root.wide ? 10 : 8)
      spacing: Style.space(root.wide ? 6 : 4)
      PreviewSlot {
        key: "showControls"
        LucideIcon { name: "skip-back"; color: root.fg; size: strip.iconSize }
        LucideIcon { name: panel.playing ? "pause" : "play"; color: root.fg; size: strip.iconSize }
        LucideIcon { name: "skip-forward"; color: root.fg; size: strip.iconSize }
      }
      PreviewSlot {
        key: "showCover"
        BorderSurface {
          id: previewCover
          readonly property string shape: String(root.pref("coverShape", "rounded"))
          width: Style.space(root.wide ? 20 : 18); height: width
          radius: shape === "circle" ? width / 2 : (shape === "square" ? 0 : Style.space(4))
          color: Style.normalFillFor(root.fg, Color.accent)
          Rectangle {
            id: previewCoverMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            radius: previewCover.radius
            color: "white"
          }
          Image {
            anchors.fill: parent
            source: String(panel.data.artUrl || "")
            visible: source !== ""
            fillMode: Image.PreserveAspectCrop; asynchronous: true
            layer.enabled: true; layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true; maskSource: previewCoverMask
              maskThresholdMin: .3; maskSpreadAtMin: .3
            }
          }
        }
      }
      PreviewTextSlot {
        key: "showArtist"; text: root.previewArtist; textColor: root.dim
        cap: Style.space(root.wide ? 110 : 70)
      }
      PreviewTextSlot {
        key: "showTitle"; text: root.previewTitle
        cap: Style.space(root.wide ? 140 : 80)
      }
      PreviewSlot {
        key: "showLike"
        LucideIcon { name: "heart"; color: root.fg; size: strip.iconSize }
      }
      PreviewSlot {
        key: "showTime"
        PreviewText {
          text: panel.formatTime(panel.displayPosition) + " / " + panel.formatTime(panel.data.duration)
          color: root.dim
        }
      }
      PreviewSlot {
        id: lyricSlot
        key: "showBarLyrics"
        // Natural width comes from the text so the layout can shrink it to fit.
        implicitWidth: (root.wide ? strip.iconSize + Style.space(6) : 0) + lyricText.implicitWidth + pad * 2
        Layout.fillWidth: true
        Layout.maximumWidth: implicitWidth
        Layout.minimumWidth: Style.space(40)
        LucideIcon {
          visible: root.wide
          anchors.verticalCenter: parent.verticalCenter
          name: "captions"; color: lyricSlot.hot ? Color.accent : root.fg; size: strip.iconSize
        }
        PreviewText {
          id: lyricText
          text: root.previewLyric
          maxWidth: lyricSlot.width - lyricSlot.pad * 2 - (root.wide ? strip.iconSize + Style.space(6) : 0)
        }
      }
      Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
      PreviewSlot {
        key: "showVolume"
        LucideIcon { name: "volume-2"; color: root.fg; size: strip.iconSize }
        Rectangle {
          visible: root.wide
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44); height: Style.space(3)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .12)
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, Number(panel.data.volume || 0) / 100))
            height: parent.height; color: root.fg
          }
        }
      }
    }
    Rectangle {
      anchors.left: parent.left; anchors.leftMargin: 1
      anchors.bottom: parent.bottom; anchors.bottomMargin: 1
      visible: strip.progressOn || root.wide
      opacity: strip.progressOn ? 1 : .3
      width: Math.max(Style.space(4), (parent.width - 2) * root.previewProgress)
      height: Style.space(root.hotKey === "showProgress" ? 3 : 2)
      color: Color.accent
    }
  }
  component PreviewHint: Row {
    spacing: Style.space(6)
    LucideIcon {
      anchors.verticalCenter: parent.verticalCenter
      name: "mouse-pointer-click"; color: root.dim; size: Style.space(root.wide ? 12 : 11)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "клик по элементу — скрыть или показать"
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
    }
  }

  // ── header ─────────────────────────────────────────────────────────────
  Item {
    id: header
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    anchors.topMargin: root.wide ? Style.space(24) : 0
    height: root.wide ? Style.space(26) : Style.space(41)
    IconButton {
      visible: !root.wide
      anchors.left: parent.left; anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(30); height: Style.space(28)
      horizontalPadding: 0; verticalPadding: 0; iconSize: Style.font.icon
      iconText: "󰁍"; tooltipText: "Вернуться"; foreground: root.fg
      onClicked: panel.closeSettings()
    }
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: root.wide ? root.gutter : Style.space(42)
      anchors.verticalCenter: parent.verticalCenter
      text: "Настройки"; color: root.fg; font.family: root.ff
      font.pixelSize: root.wide ? Style.font.title + Style.space(6) : Style.font.subtitle
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      visible: String(panel.data.version || "") !== ""
      anchors.right: parent.right; anchors.rightMargin: root.gutter
      anchors.verticalCenter: parent.verticalCenter
      text: (root.wide ? "backend v" : "v") + String(panel.data.version || "")
      color: root.dim; font.family: root.ff
      font.pixelSize: root.wide ? Style.font.bodySmall : Style.font.caption
    }
    Rectangle {
      visible: !root.wide
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: 1; color: root.hairline
    }
  }

  // ── tabs ───────────────────────────────────────────────────────────────
  Item {
    id: tabs
    objectName: "settingsTabs"
    anchors.left: parent.left; anchors.leftMargin: root.gutter
    anchors.right: parent.right; anchors.rightMargin: root.gutter
    anchors.top: header.bottom; anchors.topMargin: root.wide ? Style.space(14) : 0
    height: root.wide ? Style.space(25) : Style.space(35)
    Rectangle {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: 1; color: root.hairline
    }
    Row {
      anchors.fill: parent
      spacing: root.wide ? Style.space(24) : 0
      Repeater {
        model: [{ value: "general", label: "Основные", icon: "sliders-horizontal" },
          { value: "bar", label: "Верхний бар", icon: "panel-top" }]
        Item {
          id: tabItem
          required property var modelData
          readonly property bool selected: root.tab === modelData.value
          objectName: "settingsTab-" + modelData.value
          width: root.wide ? tabContent.implicitWidth + Style.space(4) : tabs.width / 2
          height: tabs.height
          Row {
            id: tabContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top; anchors.topMargin: root.wide ? 0 : Style.space(10)
            spacing: Style.space(7)
            LucideIcon {
              anchors.verticalCenter: parent.verticalCenter
              name: tabItem.modelData.icon
              color: tabItem.selected ? Color.accent : (tabMouse.containsMouse ? root.fg : root.dim)
              size: Style.space(13)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: tabItem.modelData.label
              color: tabItem.selected || tabMouse.containsMouse ? root.fg : root.dim
              font.family: root.ff; font.pixelSize: Style.font.body
              font.bold: tabItem.selected
            }
          }
          Rectangle {
            visible: tabItem.selected
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: Style.space(2); color: Color.accent
          }
          MouseArea {
            id: tabMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectTab(tabItem.modelData.value)
          }
        }
      }
    }
  }

  Flickable {
    id: flick
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: tabs.bottom; anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: content.y + content.height + Style.space(20)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Item {
      id: content
      x: root.gutter; y: root.wide ? Style.space(14) : Style.space(10)
      width: root.width - root.gutter * 2
      height: root.wide
        ? (root.tab === "bar" ? wideBar.implicitHeight : wideGeneral.height)
        : (root.tab === "bar" ? compactBar.implicitHeight : compactGeneral.implicitHeight)

      // ── wide · general ──
      Item {
        id: wideGeneral
        visible: root.wide && root.tab === "general"
        width: parent.width
        height: Math.max(wideGeneralLeft.implicitHeight, wideGeneralRight.implicitHeight) + Style.space(6)
        Column {
          id: wideGeneralLeft
          y: Style.space(6)
          width: root.columnWidth
          spacing: Style.space(14)
          SectionLabel { text: "ВОСПРОИЗВЕДЕНИЕ" }
          ToggleRow {
            label: "Продолжать после перезапуска"
            description: "Возобновлять трек после запуска сервиса"; key: "autoResume"
          }
          Field {
            label: "Качество аудио"; key: "audioQuality"; fallback: "best"
            options: root.qualityOptions; cellHeight: Style.space(29)
          }
          Field {
            label: "Вид попапа"; key: "popupLayout"; fallback: "compact"
            options: root.layoutOptions; cellHeight: Style.space(29)
            pickHandler: function(next) { panel.setPopupLayout(next) }
          }
        }
        Column {
          id: wideGeneralRight
          x: root.columnWidth + root.columnGap; y: Style.space(6)
          width: root.columnWidth
          spacing: Style.space(14)
          SectionLabel { text: "ВОССТАНАВЛИВАТЬ ПРИ ЗАПУСКЕ" }
          RestoreChips {}
          SectionLabel { text: "АККАУНТ" }
          AccountCard {}
        }
      }

      // ── wide · bar ──
      Column {
        id: wideBar
        visible: root.wide && root.tab === "bar"
        width: parent.width
        spacing: Style.space(14)
        Column {
          width: parent.width
          spacing: Style.space(8)
          Item {
            width: parent.width; height: wideHint.implicitHeight
            SectionLabel { text: "ПРЕДПРОСМОТР"; bottomGap: 0 }
            PreviewHint { id: wideHint; anchors.right: parent.right }
          }
          BarPreview { objectName: "settingsBarPreview" }
        }
        Item {
          width: parent.width
          height: Math.max(wideElements.implicitHeight, wideLook.implicitHeight)
          Column {
            id: wideElements
            width: root.columnWidth
            SectionLabel { text: "ЭЛЕМЕНТЫ БАРА"; note: "слева направо" }
            Repeater { model: root.elements; ElementRow {} }
          }
          Column {
            id: wideLook
            x: root.columnWidth + root.columnGap
            width: root.columnWidth
            spacing: Style.space(8)
            SectionLabel { text: "ВИД" }
            Field { label: "Форма обложки"; key: "coverShape"; fallback: "rounded"; options: root.shapeOptions }
            Field { label: "Длинные названия"; key: "longTitleMode"; fallback: "scroll"; options: root.titleOptions }
            WidthRow {
              controlName: "wideInfoWidth"
              label: "Ширина названия"; description: "исполнитель и название трека"
              key: "barInfoWidth"; fallback: 230; minimum: 100; maximum: 500
            }
            WidthRow {
              controlName: "wideLyricsWidth"
              label: "Ширина субтитров"
              description: active ? "область текста песни" : "включите субтитры в элементах"
              key: "barLyricsWidth"; fallback: 400; minimum: 120; maximum: 1200
              active: root.on("showBarLyrics")
            }
            SectionLabel { text: "ПОВЕДЕНИЕ"; topGap: Style.space(6); bottomGap: 0 }
            ToggleRow {
              label: "Управление кликами по тексту"
              description: "ЛКМ пауза · ПКМ далее · СКМ назад"
              key: "barMouseControls"; fallback: false
            }
            Field { label: "Уведомления о треке"; key: "notifications"; fallback: "off"; options: root.notifyOptions }
          }
        }
      }

      // ── compact · general ──
      Column {
        id: compactGeneral
        visible: !root.wide && root.tab === "general"
        width: parent.width
        spacing: Style.space(10)
        SectionLabel { text: "ВОСПРОИЗВЕДЕНИЕ" }
        ToggleRow {
          label: "Продолжать после перезапуска"
          description: "Возобновлять трек после запуска"; key: "autoResume"
        }
        Field {
          label: "Качество аудио"; key: "audioQuality"; fallback: "best"
          options: root.qualityOptions; cellHeight: Style.space(27)
        }
        Field {
          label: "Вид попапа"; key: "popupLayout"; fallback: "compact"
          options: root.layoutOptions; cellHeight: Style.space(27)
          pickHandler: function(next) { panel.setPopupLayout(next) }
        }
        SectionLabel { text: "ВОССТАНАВЛИВАТЬ ПРИ ЗАПУСКЕ"; topGap: Style.space(4) }
        RestoreChips {}
        SectionLabel { text: "АККАУНТ"; topGap: Style.space(4) }
        AccountCard {}
      }

      // ── compact · bar ──
      Column {
        id: compactBar
        visible: !root.wide && root.tab === "bar"
        width: parent.width
        spacing: Style.space(10)
        BarPreview { objectName: "settingsBarPreviewCompact" }
        PreviewHint {}
        SectionLabel { text: "ЭЛЕМЕНТЫ"; note: "слева направо" }
        Grid {
          width: parent.width
          columns: 3
          spacing: Style.space(6)
          Repeater {
            model: root.elements
            Tile {
              required property var modelData
              width: (parent.width - Style.space(12)) / 3
              height: Style.space(31)
              icon: modelData.icon; label: modelData.short
              checked: root.on(modelData.key)
              onActivated: root.toggle(modelData.key)
            }
          }
        }
        SectionLabel { text: "ВИД" }
        Row {
          width: parent.width
          spacing: Style.space(12)
          Field {
            width: (parent.width - Style.space(12)) / 2
            label: "Обложка"; key: "coverShape"; fallback: "rounded"; options: root.shapeOptions
          }
          Field {
            width: (parent.width - Style.space(12)) / 2
            label: "Длинные названия"; key: "longTitleMode"; fallback: "scroll"; options: root.titleOptions
          }
        }
        WidthRow {
          controlName: "compactInfoWidth"
          label: "Ширина названия"; description: "исполнитель и название трека"
          key: "barInfoWidth"; fallback: 230; minimum: 100; maximum: 500
        }
        WidthRow {
          controlName: "compactLyricsWidth"
          label: "Ширина субтитров"
          description: active ? "область текста песни" : "включите субтитры в элементах"
          key: "barLyricsWidth"; fallback: 400; minimum: 120; maximum: 1200
          active: root.on("showBarLyrics")
        }
        SectionLabel { text: "ПОВЕДЕНИЕ" }
        ToggleRow {
          label: "Клики по тексту"
          description: "ЛКМ пауза · ПКМ далее · СКМ назад"
          key: "barMouseControls"; fallback: false
        }
        Field { label: "Уведомления о треке"; key: "notifications"; fallback: "off"; options: root.notifyOptions }
      }
    }
  }
}
