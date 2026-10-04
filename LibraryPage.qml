import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
  id: root
  spacing: Style.space(6)
  required property var controller
  property var preferences: ({})
  property color foreground: "white"
  property color dim: "gray"
  property string fontFamily: ""
  property bool panelOpened: false
  property bool settingsOpen: false
  property bool settingsRunning: false
  property var focusTarget: null
  property bool waveOptionsOpen: false
  readonly property real viewportY: libraryList.contentY
  readonly property bool stationSearchActiveFocus: stationSearchField.activeFocus
  readonly property bool stationSearchVisible: stationSearchField.visible

  signal preferenceRequested(string key, var value)
  signal waveRequested()
  signal collectionTrackRequested(int index, var value)

  function preference(key, fallback) {
    var values = preferences || {}
    return values[key] === undefined ? fallback : values[key]
  }
  function clearStationFocus() { stationSearchField.focus = false }
  function resetViewport() { libraryList.contentY = 0 }
  function preserveViewport(y) {
    libraryList.contentY = Math.min(y, Math.max(0, libraryList.contentHeight - libraryList.height))
  }

  BorderSurface {
    width: parent.width; height: Style.space(48); radius: Style.cornerRadius
    color: waveMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
      : Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
      text: "󰝚   Моя волна"; color: root.foreground; font.family: root.fontFamily
      font.pixelSize: Style.font.body; font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
      text: root.waveOptionsOpen ? "󰅃" : "󰅀"
      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body
    }
    MouseArea {
      id: waveMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: root.waveOptionsOpen = !root.waveOptionsOpen
    }
  }

  Column {
    visible: root.waveOptionsOpen
    width: parent.width
    spacing: Style.space(7)

    Dropdown {
      x: Style.space(8); width: parent.width - Style.space(16)
      label: "Настроение"
      value: String(root.preference("waveMood", "all"))
      foreground: root.foreground; fontFamily: root.fontFamily
      options: [
        { value: "all", label: "Любое" },
        { value: "fun", label: "Весёлое" },
        { value: "active", label: "Энергичное" },
        { value: "calm", label: "Спокойное" },
        { value: "sad", label: "Грустное" }
      ]
      onChanged: function(value) { root.preferenceRequested("waveMood", value) }
    }
    Dropdown {
      x: Style.space(8); width: parent.width - Style.space(16)
      label: "Подбор треков"
      value: String(root.preference("waveDiversity", "default"))
      foreground: root.foreground; fontFamily: root.fontFamily
      options: [
        { value: "default", label: "Сбалансированный" },
        { value: "favorite", label: "Больше любимого" },
        { value: "popular", label: "Популярное" },
        { value: "discover", label: "Больше нового" }
      ]
      onChanged: function(value) { root.preferenceRequested("waveDiversity", value) }
    }
    Dropdown {
      x: Style.space(8); width: parent.width - Style.space(16)
      label: "Язык"
      value: String(root.preference("waveLanguage", "any"))
      foreground: root.foreground; fontFamily: root.fontFamily
      options: [
        { value: "any", label: "Любой" },
        { value: "russian", label: "Русская музыка" },
        { value: "not-russian", label: "Зарубежная музыка" }
      ]
      onChanged: function(value) { root.preferenceRequested("waveLanguage", value) }
    }
    Button {
      x: Style.space(8); width: parent.width - Style.space(16)
      text: root.settingsRunning ? "Сохраняем настройки…" : "Запустить Мою волну"
      iconText: "󰐊"; foreground: root.foreground; bordered: true
      enabled: !root.settingsRunning; opacity: enabled ? 1 : .5
      onClicked: {
        root.waveOptionsOpen = false
        root.waveRequested()
      }
    }
  }

  Item {
    id: libraryViewport
    width: parent.width
    height: Style.space(360)
    clip: true

    TextField {
      id: stationSearchField
      visible: root.controller.stationMode
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
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
      anchors.top: stationSearchField.visible ? stationSearchField.bottom : parent.top
      anchors.topMargin: stationSearchField.visible ? Style.space(6) : 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      rowCount: 7
      foreground: root.foreground
    }

    ListView {
      id: libraryList
      property bool stationPageScheduled: false
      visible: !root.controller.loading
      anchors.top: stationSearchField.visible ? stationSearchField.bottom : parent.top
      anchors.topMargin: stationSearchField.visible ? Style.space(6) : 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: height * 2
      model: root.controller.rows
      spacing: Style.space(2)
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
        readonly property bool actionable: ["collection", "navigation", "back", "retry", "loadMore",
          "track", "artist", "album", "playlist", "station"].indexOf(rowKind) >= 0
        readonly property bool hovered: libraryHover.hovered
        width: libraryList.width
          - (libraryList.contentHeight > libraryList.height ? Style.space(8) : 0)
        height: rowKind === "section" ? Style.space(30)
          : (entityRow || rowKind === "collection" || rowKind === "navigation"
            ? Style.space(58) : Style.space(42))
        radius: Style.cornerRadius
        opacity: libraryRow.value.available === false ? .45 : 1
        color: actionable && libraryRow.value.available !== false && libraryRow.hovered
          ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
        borderSpec: Border.none()

        HoverHandler { id: libraryHover }

        Text {
          textFormat: Text.PlainText
          visible: ["section", "error", "warning", "empty", "back", "retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter
          text: (libraryRow.rowKind === "back"
            ? String(libraryRow.modelData.icon || "") + "  " : "")
            + String(libraryRow.modelData.title || "")
          color: libraryRow.rowKind === "error" ? Color.urgent
            : (["back", "retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0 ? Color.accent : root.dim)
          horizontalAlignment: ["back", "retry", "loadMore", "empty"].indexOf(libraryRow.rowKind) >= 0
            ? Text.AlignHCenter : Text.AlignLeft
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: libraryRow.rowKind === "section" ? Style.font.caption : Style.font.bodySmall
          font.bold: libraryRow.rowKind === "section"
            || ["back", "retry", "loadMore"].indexOf(libraryRow.rowKind) >= 0
          font.letterSpacing: libraryRow.rowKind === "section" ? .8 : 0
        }

        Row {
          z: 2
          visible: libraryRow.rowKind === "collection" || libraryRow.rowKind === "navigation"
            || libraryRow.entityRow
          anchors.left: parent.left; anchors.right: parent.right
          anchors.margins: Style.space(9); anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(9)

          CatalogImage {
            visible: libraryRow.entityRow
            width: visible ? Style.space(40) : 0; height: width
            requestedSource: String(libraryRow.value.artUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Text {
            textFormat: Text.PlainText
            visible: !libraryRow.entityRow
            width: visible ? Style.space(40) : 0
            anchors.verticalCenter: parent.verticalCenter
            text: String(libraryRow.modelData.icon || "󰁔")
            horizontalAlignment: Text.AlignHCenter
            color: Color.accent; font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }
          Column {
            width: parent.width - Style.space(49)
              - (libraryRow.rowKind === "track" ? Style.space(35) : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(libraryRow.entityRow
                ? (libraryRow.value.title || libraryRow.value.name || "Без названия")
                : libraryRow.modelData.title || "")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: {
                if (!libraryRow.entityRow) return String(libraryRow.modelData.subtitle || "")
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
          Button {
            visible: libraryRow.rowKind === "track" && libraryRow.hovered
            width: libraryRow.rowKind === "track" ? Style.space(26) : 0
            height: Style.space(26)
            anchors.verticalCenter: parent.verticalCenter
            horizontalPadding: 0; verticalPadding: 0
            iconText: "󰐒"; iconSize: Style.font.icon
            tooltipText: "Добавить в плейлист"
            foreground: root.dim
            onClicked: root.collectionTrackRequested(
              Number(libraryRow.value.trackIndex || 0), libraryRow.value)
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
}
