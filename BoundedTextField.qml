import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

// TextEdit's plain-text canPaste checks MIME formats, unlike TextInput's
// payload-reading clipboard-change handler in affected Qt versions. Never call
// native paste(): all external selection reads go through the bounded helper.
FocusScope {
  id: root
  property alias text: editor.text
  property alias font: editor.font
  property alias cursorPosition: editor.cursorPosition
  readonly property alias selectionStart: editor.selectionStart
  readonly property alias selectionEnd: editor.selectionEnd
  property string placeholderText: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real leftPadding: Style.spacing.controlPaddingX
  property real rightPadding: Style.spacing.controlPaddingX
  property string pasteError: ""
  readonly property bool pasteBusy: clipboard.running
  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus"
    : (hover.hovered ? "hover-cursor" : "normal"), foreground, accent)
  property int revision: 0
  property var pasteTarget: null
  signal textEdited()
  signal accepted()

  implicitHeight: Style.space(30)
  implicitWidth: Style.space(180)
  activeFocusOnTab: true

  function select(start, end) { editor.select(start, end) }
  function selectAll() { editor.selectAll() }
  function requestPaste(primary) {
    if (clipboard.running || !activeFocus || !visible || !enabled) return
    pasteError = ""
    pasteTarget = { revision: revision, start: editor.selectionStart,
      end: editor.selectionEnd, cursor: editor.cursorPosition }
    clipboard.command = ["python3", "-B",
      decodeURIComponent(String(Qt.resolvedUrl("bin/read-clipboard.py")).replace(/^file:\/\//, ""))]
    if (primary) clipboard.command = clipboard.command.concat(["--primary"])
    clipboard.running = true
  }
  function completePaste(code, output) {
    var target = pasteTarget
    pasteTarget = null
    if (!target || !activeFocus || !visible || !enabled || target.revision !== revision
        || target.start !== editor.selectionStart || target.end !== editor.selectionEnd
        || target.cursor !== editor.cursorPosition) return
    if (code !== 0) {
      pasteError = "Не удалось вставить: буфер недоступен, больше 16 КиБ или чтение дольше 1 с"
      return
    }
    var value
    try { value = JSON.parse(output) } catch (_) { return }
    if (typeof value !== "string") return
    value = value.replace(/[\r\n\t\u2028\u2029]/g, " ")
    if (!value.length) return
    editor.remove(target.start, target.end)
    editor.insert(target.start, value)
    editor.cursorPosition = target.start + value.length
    root.textEdited()
  }
  onActiveFocusChanged: { revision++; if (!activeFocus) pasteError = "" }
  onVisibleChanged: revision++
  onEnabledChanged: revision++

  Keys.onPressed: function(event) {
    if (event.matches(StandardKey.Paste)
        || (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)
            && (event.modifiers & Qt.ShiftModifier))) {
      event.accepted = true
      requestPaste(false)
    } else if (event.key === Qt.Key_Menu
        || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
      event.accepted = true
      menu.popup()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      event.accepted = true
      accepted()
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // Do not insert tabs into a single-line editor.
      event.accepted = true
      nextItemInFocusChain(event.key !== Qt.Key_Backtab).forceActiveFocus(Qt.TabFocusReason)
    }
  }

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root.activeFocus, hover.hovered, root.foreground, root.accent)
    borderSpec: root.borderSpec
    radius: Style.cornerRadius
  }
  HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
  Flickable {
    id: scroll
    anchors.fill: parent
    anchors.leftMargin: root.leftPadding
    anchors.rightMargin: root.rightPadding
    anchors.topMargin: Style.spacing.inputPaddingY
    anchors.bottomMargin: Style.spacing.inputPaddingY
    clip: true
    interactive: false
    contentWidth: editor.width
    contentHeight: height
    function revealCursor() {
      var rect = editor.cursorRectangle
      contentX = Math.max(0, Math.min(Math.max(0, contentWidth - width),
        rect.x < contentX ? rect.x : Math.max(contentX, rect.x + rect.width - width)))
    }
    TextEdit {
      id: editor
      width: Math.max(scroll.width, contentWidth + 2)
      height: scroll.height
      focus: true
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      verticalAlignment: TextEdit.AlignVCenter
      selectByMouse: true
      persistentSelection: true
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
      Keys.forwardTo: [root]
      onTextChanged: { root.revision++; root.pasteError = ""; scroll.revealCursor() }
      onTextEdited: root.textEdited()
      onCursorRectangleChanged: scroll.revealCursor()
      onCursorPositionChanged: root.revision++
      onSelectionStartChanged: root.revision++
      onSelectionEndChanged: root.revision++
    }
    Text {
      anchors.fill: parent
      textFormat: Text.PlainText
      visible: editor.text === "" && editor.preeditText === ""
      text: root.placeholderText
      color: Qt.darker(root.foreground, 1.6)
      font: editor.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    // Consume primary-selection and context-menu buttons before TextEdit.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.IBeamCursor
      onPressed: function(mouse) {
        root.forceActiveFocus()
        if (mouse.button === Qt.MiddleButton)
          editor.cursorPosition = editor.positionAt(mouse.x, mouse.y)
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) root.requestPaste(true)
        else menu.popup()
      }
    }
  }
  Menu {
    id: menu
    MenuItem { text: "Вырезать"; enabled: editor.selectedText !== ""; onTriggered: editor.cut() }
    MenuItem { text: "Копировать"; enabled: editor.selectedText !== ""; onTriggered: editor.copy() }
    MenuItem {
      text: "Вставить"; enabled: !root.pasteBusy
      onTriggered: Qt.callLater(function() { root.forceActiveFocus(); root.requestPaste(false) })
    }
    MenuItem { text: "Выделить всё"; onTriggered: editor.selectAll() }
  }
  ToolTip {
    visible: root.pasteError !== "" && root.activeFocus
    text: root.pasteError
    timeout: 5000
  }
  Process {
    id: clipboard
    stdout: StdioCollector { id: result; waitForEnd: true }
    onExited: function(code) { root.completePaste(code, result.text) }
  }
}
