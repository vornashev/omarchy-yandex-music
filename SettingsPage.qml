import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Settings: two columns in the wide layout, one dense column in the compact one.
Item {
  id: root

  required property var panel
  property bool wide: false
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property real gutter: wide ? Style.space(28) : Style.space(16)
  readonly property real columnWidth: wide ? (width - gutter * 2 - Style.space(32)) / 2
    : width - gutter * 2
  readonly property alias flick: flick

  function pref(key, fallback) { return panel.preference(key, fallback) }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    topPadding: Style.space(10); bottomPadding: Style.space(4)
    color: Qt.lighter(Color.accent, 1.0)
    opacity: .85
    font.family: root.ff; font.pixelSize: Style.font.caption
    font.bold: true; font.letterSpacing: 1.2
  }
  component ToggleRow: SettingRow {
    id: toggleRow
    property string key: ""
    property bool fallback: true
    property bool compact: false
    foreground: root.fg; dim: root.dim; fontFamily: root.ff
    minHeight: compact ? Style.space(32) : Style.space(38)
    ToggleSwitch {
      trackHeight: Style.space(18)
      cursorRing: false
      checked: Boolean(root.pref(toggleRow.key, toggleRow.fallback))
      foreground: root.fg
      onToggled: panel.setPreference(toggleRow.key, !checked)
    }
  }
  component SelectRow: SettingRow {
    id: selectRow
    property string key: ""
    property string fallback: ""
    property var options: []
    property real selectWidth: Style.space(wide ? 190 : 120)
    foreground: root.fg; dim: root.dim; fontFamily: root.ff
    minHeight: wide ? Style.space(43) : Style.space(35)
    MusicSelect {
      width: selectRow.selectWidth
      options: selectRow.options
      value: String(root.pref(selectRow.key, selectRow.fallback))
      defaultValue: selectRow.fallback
      busy: panel.settingsBusy
      foreground: root.fg; dim: root.dim; fontFamily: root.ff
      onChanged: function(next) { panel.setPreference(selectRow.key, next) }
    }
  }
  component ChipToggle: BorderSurface {
    id: chip
    property string key: ""
    property string label: ""
    readonly property bool on: Boolean(root.pref(key, true))
    height: Style.space(30)
    radius: Style.cornerRadius
    color: on ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
    borderSpec: Border.controlSpec(on ? "selected" : "normal", root.fg, Color.accent)
    Row {
      anchors.centerIn: parent
      spacing: Style.space(7)
      LucideIcon {
        visible: chip.on
        glyph: "󰄬"; color: Color.accent
        fontFamily: root.ff; size: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        text: chip.label; color: chip.on ? root.fg : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
      }
    }
    MouseArea {
      anchors.fill: parent; cursorShape: Qt.PointingHandCursor
      onClicked: panel.setPreference(chip.key, !chip.on)
    }
  }

  readonly property var layoutOptions: [
    // { value: "mini", label: "Mini" }, // Отложено до будущего обновления.
    { value: "compact", label: "Компакт" }, { value: "wide", label: "Широкий" }]
  readonly property var qualityOptions: [{ value: "best", label: wide ? "Лучшее доступное" : "Лучшее" },
    { value: "economy", label: wide ? "Экономия трафика" : "Экономия" }]
  readonly property var shapeOptions: [{ value: "square", label: "Квадратная" },
    { value: "rounded", label: "Скруглённая" }, { value: "circle", label: "Круглая" }]
  readonly property var titleOptions: [{ value: "truncate", label: wide ? "Многоточие" : "Многоточие" },
    { value: "scroll", label: "Прокрутка" }]
  readonly property var widthOptions: [{ value: "compact", label: "Компактная" },
    { value: "normal", label: "Обычная" }, { value: "wide", label: "Широкая" }]
  readonly property var notifyOptions: [{ value: "off", label: wide ? "Выключены" : "Выкл." },
    { value: "all", label: wide ? "Показывать всегда" : "Всегда" }]

  // header
  Item {
    id: header
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: wide ? Style.space(72) : Style.space(41)
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
      anchors.leftMargin: root.wide ? root.gutter : Style.space(50)
      anchors.verticalCenter: parent.verticalCenter
      text: "Настройки"; color: root.fg; font.family: root.ff
      font.pixelSize: root.wide ? Style.font.title + Style.space(8) : Style.font.subtitle
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      visible: String(panel.data.version || "") !== ""
      anchors.right: parent.right; anchors.rightMargin: root.wide ? root.gutter : Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: (root.wide ? "backend v" : "v") + String(panel.data.version || "")
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
    }
    Rectangle {
      visible: !root.wide
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, .08)
    }
  }

  Flickable {
    id: flick
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: header.bottom; anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: (root.wide ? Math.max(wideLeft.implicitHeight, wideRight.implicitHeight)
      : compactColumn.implicitHeight) + Style.space(20)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    // ── wide ──
    Column {
      id: wideLeft
      visible: root.wide
      x: root.gutter; width: root.columnWidth
      SectionLabel { text: "ВОСПРОИЗВЕДЕНИЕ" }
      ToggleRow {
        width: parent.width; label: "Продолжать после перезапуска"
        description: "Возобновлять трек после запуска сервиса"; key: "autoResume"
      }
      SelectRow {
        width: parent.width; label: "Качество аудио"; key: "audioQuality"
        fallback: "best"; options: root.qualityOptions
      }
      SettingRow {
        width: parent.width; label: "Вид попапа"; minHeight: Style.space(43)
        foreground: root.fg; dim: root.dim; fontFamily: root.ff
        MusicSegmented {
          options: root.layoutOptions; value: String(root.pref("popupLayout", "compact"))
          foreground: root.fg; dim: root.dim; fontFamily: root.ff; cellHeight: Style.space(24)
          onChanged: function(next) { panel.setPopupLayout(next) }
        }
      }
      SectionLabel { text: "ВОССТАНОВЛЕНИЕ СЕССИИ" }
      ToggleRow { width: parent.width; label: "Очередь"; key: "restoreQueue" }
      ToggleRow { width: parent.width; label: "Позиция трека"; key: "restorePosition" }
      ToggleRow { width: parent.width; label: "Громкость"; key: "restoreVolume" }
      SectionLabel { text: "АККАУНТ" }
      Item {
        width: parent.width; height: accountRowWide.implicitHeight + Style.space(10)
        AccountRow { id: accountRowWide; width: parent.width; anchors.verticalCenter: parent.verticalCenter }
      }
    }
    Column {
      id: wideRight
      visible: root.wide
      x: root.gutter + root.columnWidth + Style.space(32); width: root.columnWidth
      SectionLabel { text: "ВЕРХНИЙ БАР" }
      ToggleRow { width: parent.width; label: "Кнопки управления"; key: "showControls" }
      ToggleRow { width: parent.width; label: "Громкость"; key: "showVolume" }
      ToggleRow { width: parent.width; label: "Время трека"; key: "showTime"; fallback: false }
      ToggleRow { width: parent.width; label: "Кнопка «Нравится»"; key: "showLike"; fallback: false }
      ToggleRow { width: parent.width; label: "Исполнитель"; key: "showArtist" }
      ToggleRow { width: parent.width; label: "Название трека"; key: "showTitle" }
      ToggleRow { width: parent.width; label: "Обложка"; key: "showCover" }
      ToggleRow { width: parent.width; label: "Линия прогресса"; key: "showProgress" }
      SelectRow { width: parent.width; label: "Форма обложки"; key: "coverShape"
        fallback: "rounded"; options: root.shapeOptions }
      SelectRow { width: parent.width; label: "Длинные названия"; key: "longTitleMode"
        fallback: "scroll"; options: root.titleOptions }
      SelectRow { width: parent.width; label: "Ширина информации"; key: "barWidth"
        fallback: "normal"; options: root.widthOptions }
      SelectRow { width: parent.width; label: "Уведомления"; key: "notifications"
        fallback: "off"; options: root.notifyOptions }
    }

    // ── compact ──
    Column {
      id: compactColumn
      visible: !root.wide
      x: root.gutter; width: root.columnWidth
      SectionLabel { text: "ВОСПРОИЗВЕДЕНИЕ"; topPadding: Style.space(6) }
      ToggleRow { width: parent.width; label: "Продолжать после перезапуска"; key: "autoResume" }
      SelectRow { width: parent.width; label: "Качество"; key: "audioQuality"
        fallback: "best"; options: root.qualityOptions }
      SettingRow {
        width: parent.width; label: "Вид попапа"; minHeight: Style.space(35)
        foreground: root.fg; dim: root.dim; fontFamily: root.ff
        MusicSegmented {
          options: root.layoutOptions; value: String(root.pref("popupLayout", "compact"))
          foreground: root.fg; dim: root.dim; fontFamily: root.ff; cellHeight: Style.space(24)
          onChanged: function(next) { panel.setPopupLayout(next) }
        }
      }
      SectionLabel { text: "ВОССТАНАВЛИВАТЬ" }
      Row {
        width: parent.width; spacing: Style.space(8)
        ChipToggle { width: (parent.width - Style.space(16)) / 3; key: "restoreQueue"; label: "Очередь" }
        ChipToggle { width: (parent.width - Style.space(16)) / 3; key: "restorePosition"; label: "Позицию" }
        ChipToggle { width: (parent.width - Style.space(16)) / 3; key: "restoreVolume"; label: "Громкость" }
      }
      SectionLabel { text: "ВЕРХНИЙ БАР" }
      BorderSurface {
        width: parent.width; height: Style.space(30)
        color: Style.normalFillFor(root.fg, Color.accent)
        borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
        radius: Style.cornerRadius
        Row {
          anchors.left: parent.left; anchors.leftMargin: Style.space(10)
          anchors.right: parent.right; anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Row {
            visible: Boolean(root.pref("showControls", true))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            LucideIcon { glyph: "󰒮"; color: root.fg; size: Style.space(11) }
            LucideIcon { glyph: "󰐊"; color: root.fg; size: Style.space(11) }
            LucideIcon { glyph: "󰒭"; color: root.fg; size: Style.space(11) }
          }
          Rectangle {
            visible: Boolean(root.pref("showCover", true))
            width: Style.space(16); height: width
            radius: String(root.pref("coverShape", "rounded")) === "circle" ? width / 2
              : (String(root.pref("coverShape", "rounded")) === "rounded" ? Style.space(3) : 0)
            color: Style.selectedFillFor(root.fg, Color.accent)
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - x
            elide: Text.ElideRight
            text: [Boolean(root.pref("showArtist", true)) ? String(panel.data.artist || "Исполнитель") : "",
              Boolean(root.pref("showTitle", true)) ? String(panel.data.title || "Трек") : ""]
              .filter(function(part) { return part !== "" }).join(" — ")
            color: root.fg; font.family: root.ff; font.pixelSize: Style.font.bodySmall
          }
        }
      }
      Row {
        width: parent.width; spacing: Style.space(24)
        Column {
          width: (parent.width - Style.space(24)) / 2
          ToggleRow { width: parent.width; label: "Кнопки"; key: "showControls"; compact: true }
          ToggleRow { width: parent.width; label: "Исполнитель"; key: "showArtist"; compact: true }
          ToggleRow { width: parent.width; label: "Обложка"; key: "showCover"; compact: true }
          ToggleRow { width: parent.width; label: "Время"; key: "showTime"; fallback: false; compact: true }
        }
        Column {
          width: (parent.width - Style.space(24)) / 2
          ToggleRow { width: parent.width; label: "Громкость"; key: "showVolume"; compact: true }
          ToggleRow { width: parent.width; label: "Название"; key: "showTitle"; compact: true }
          ToggleRow { width: parent.width; label: "Прогресс"; key: "showProgress"; compact: true }
          ToggleRow { width: parent.width; label: "Нравится"; key: "showLike"; fallback: false; compact: true }
        }
      }
      SelectRow { width: parent.width; label: "Форма обложки"; key: "coverShape"
        fallback: "rounded"; options: root.shapeOptions }
      SelectRow { width: parent.width; label: "Длинные названия"; key: "longTitleMode"
        fallback: "scroll"; options: root.titleOptions }
      SelectRow { width: parent.width; label: "Ширина информации"; key: "barWidth"
        fallback: "normal"; options: root.widthOptions }
      SelectRow { width: parent.width; label: "Уведомления"; key: "notifications"
        fallback: "off"; options: root.notifyOptions }
      SectionLabel { text: "АККАУНТ" }
      AccountRow { width: parent.width }
    }
  }

  component AccountRow: Column {
    spacing: Style.space(8)
    Item {
      width: parent.width; height: Style.space(32)
      Row {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        LucideIcon {
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰗡"; color: root.dim
          fontFamily: root.ff; size: Style.font.icon
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.wide ? "Яндекс Музыка подключена" : "Подключено"
          color: root.fg; font.family: root.ff; font.pixelSize: Style.font.bodySmall
        }
      }
      IconButton {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        visible: !panel.confirmLogout
        text: "Выйти"; foreground: Color.urgent; bordered: true
        onClicked: panel.confirmLogout = true
      }
    }
    // Confirmation gets its own rows so the buttons never cover the status text.
    Text {
      textFormat: Text.PlainText
      visible: panel.confirmLogout
      width: parent.width; wrapMode: Text.WordWrap
      text: "Токен авторизации будет удалён. Для повторного входа понадобится браузер."
      color: Color.urgent; font.family: root.ff; font.pixelSize: Style.font.caption
    }
    Row {
      visible: panel.confirmLogout
      anchors.right: parent.right
      spacing: Style.space(8)
      IconButton {
        text: "Отмена"; foreground: root.fg; bordered: true
        onClicked: panel.confirmLogout = false
      }
      IconButton {
        text: "Подтвердить выход"
        foreground: Color.urgent; bordered: true
        onClicked: {
          panel.intent("logout")
          panel.closeSettings()
        }
      }
    }
  }
}
