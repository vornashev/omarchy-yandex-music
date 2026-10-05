import QtQuick
import qs.Commons
import qs.Ui

// Signed-out flow: start → device code → expired code → done.
Item {
  id: root

  required property var panel
  readonly property color fg: panel.foreground
  readonly property color dim: panel.dim
  readonly property string ff: panel.fontFamily
  readonly property color lineColor: Qt.rgba(fg.r, fg.g, fg.b, .14)
  readonly property color okColor: Color.accent
  readonly property color badColor: Color.urgent
  readonly property string stage: panel.authDone ? "done"
    : (panel.data.authPending === true ? "code"
      : (panel.data.authExpired === true ? "expired" : "start"))
  readonly property string codeText: stage === "code" ? String(panel.data.authCode || "") : panel.lastAuthCode
  readonly property string codeChars: codeText.replace(/[^A-Za-z0-9]/g, "").toUpperCase()
  readonly property int half: Math.ceil(codeChars.length / 2)
  property real nowSeconds: Date.now() / 1000
  readonly property real secondsLeft: Math.max(0, Number(panel.data.authExpiresAt || 0) - nowSeconds)
  readonly property bool hasCode: String(panel.data.authCode || "") !== ""

  implicitHeight: column.implicitHeight + Style.space(stage === "done" ? 80 : 48)

  function press() {
    if (stage === "start") panel.startAuth()
    else if (stage === "code") panel.openAuthPage()
    else if (stage === "expired") panel.startAuth()
    else panel.finishAuth(true)
  }
  function timeLeft() {
    var total = Math.round(secondsLeft)
    return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
  }

  Rectangle { anchors.fill: parent; color: Color.popups.background }

  Timer {
    interval: 1000; repeat: true
    running: root.stage === "code" && root.visible
    onTriggered: root.nowSeconds = Date.now() / 1000
  }

  component PrimaryButton: BorderSurface {
    id: primary
    property string label: ""
    property string icon: ""
    property string keyHint: ""
    property bool danger: false
    signal clicked()
    height: Style.space(38)
    radius: Style.cornerRadius
    opacity: enabled ? 1 : .5
    color: primaryMouse.containsMouse ? Qt.lighter(Color.accent, 1.12) : Color.accent
    borderSpec: Border.none()
    Row {
      anchors.centerIn: parent
      spacing: Style.space(10)
      LucideIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: primary.icon; color: Color.background; size: Style.space(14)
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: primary.label; color: Color.background
        font.family: root.ff; font.pixelSize: Style.font.bodySmall + Style.space(1); font.bold: true
      }
      BorderSurface {
        visible: primary.keyHint !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(18), keyText.implicitWidth + Style.space(10)); height: Style.space(16)
        radius: 0; color: "transparent"
        borderSpec: Border.controlSpec("normal", Color.background, Color.background)
        opacity: .6
        Text {
          id: keyText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: primary.keyHint; color: Color.background
          font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }
    }
    MouseArea {
      id: primaryMouse
      anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: primary.clicked()
    }
  }

  Column {
    id: column
    x: Style.space(24); y: Style.space(root.stage === "done" ? 40 : 24)
    width: parent.width - Style.space(48)
    spacing: Style.space(root.stage === "done" ? 16 : 20)

    // ── header ──────────────────────────────────────────────────────────
    Row {
      visible: root.stage !== "done"
      spacing: Style.space(14)
      Rectangle {
        width: Style.space(48); height: width; radius: width / 2
        color: "transparent"; border.width: 1; border.color: Color.accent
        LucideIcon {
          anchors.centerIn: parent
          name: "audio-lines"; color: Color.accent; size: Style.space(22)
        }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          text: "Яндекс Музыка"; color: root.fg
          font.family: root.ff; font.pixelSize: Style.font.title + Style.space(2); font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: root.stage === "start" ? "Автономный плеер для бара Omarchy"
            : "Подтвердите вход в браузере"
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ── start ───────────────────────────────────────────────────────────
    BorderSurface {
      visible: root.stage === "start"
      width: parent.width; height: featureColumn.implicitHeight + Style.space(28)
      color: Style.normalFillFor(root.fg, Color.accent)
      borderSpec: Border.none()
      Column {
        id: featureColumn
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: Style.space(14)
        spacing: Style.space(10)
        Repeater {
          model: [{ icon: "radio", text: "Моя волна, плейлисты и поиск" },
            { icon: "keyboard", text: "Управление из бара и с клавиатуры" },
            { icon: "unplug", text: "Браузер нужен только для входа" }]
          Row {
            required property var modelData
            spacing: Style.space(10)
            LucideIcon {
              anchors.verticalCenter: parent.verticalCenter
              name: modelData.icon; color: Color.accent; size: Style.space(14)
            }
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.text; color: root.fg
              font.family: root.ff; font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
    PrimaryButton {
      visible: root.stage === "start"
      width: parent.width
      label: "Войти через Яндекс"; icon: "log-in"; keyHint: "⏎"
      onClicked: root.panel.startAuth()
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "start"
      width: parent.width; wrapMode: Text.WordWrap
      text: "Покажем короткий код для ya.ru/device.\nПароль плеер не видит."
      color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption; lineHeight: 1.3
    }

    // ── steps (code / expired) ──────────────────────────────────────────
    Row {
      visible: root.stage === "code" || root.stage === "expired"
      width: parent.width; spacing: Style.space(6)
      readonly property bool codeReady: root.hasCode || root.stage === "expired"
      Row {
        spacing: Style.space(6)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18); height: width; radius: width / 2
          color: Color.accent; border.width: 1; border.color: Color.accent
          LucideIcon { anchors.centerIn: parent; name: "check"; color: Color.background; size: Style.space(10); strokeWidth: 3 }
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Откройте страницу"; color: root.dim
          font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Style.space(22); height: 1; color: Color.accent }
      Row {
        spacing: Style.space(6)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18); height: width; radius: width / 2
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .2)
          border.width: 1; border.color: Color.accent
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "2"; color: Color.accent
            font.family: root.ff; font.pixelSize: Style.font.caption - 1; font.bold: true
          }
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Введите код"; color: root.fg
          font.family: root.ff; font.pixelSize: Style.font.caption; font.bold: true
        }
      }
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Style.space(22); height: 1; color: root.lineColor }
      Row {
        spacing: Style.space(6)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18); height: width; radius: width / 2
          color: "transparent"; border.width: 1; border.color: root.lineColor
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "3"; color: root.dim
            font.family: root.ff; font.pixelSize: Style.font.caption - 1; font.bold: true
          }
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Готово"; color: root.dim
          font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }
    }

    // ── code block ──────────────────────────────────────────────────────
    BorderSurface {
      visible: root.stage === "code" || root.stage === "expired"
      width: parent.width; height: codeColumn.implicitHeight + Style.space(32)
      color: Style.normalFillFor(root.fg, Color.accent)
      borderSpec: Border.controlSpec("normal", root.stage === "expired" ? root.badColor : Color.accent,
        root.stage === "expired" ? root.badColor : Color.accent)
      Column {
        id: codeColumn
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: Style.space(16)
        spacing: Style.space(12)
        Text {
          textFormat: Text.PlainText
          text: root.stage === "expired" ? "КОД ИСТЁК" : "КОД ДЛЯ YA.RU/DEVICE"
          color: root.stage === "expired" ? root.badColor : root.dim
          font.family: root.ff; font.pixelSize: Style.font.caption
          font.bold: true; font.letterSpacing: 1.5
        }
        Row {
          spacing: Style.space(6)
          Repeater {
            model: root.codeChars.length > 0 ? root.codeChars.length : 8
            Row {
              id: charCell
              required property int index
              spacing: Style.space(6)
              Item {
                visible: charCell.index === root.half && root.codeChars.length > 0
                width: Style.space(8); height: Style.space(40)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "–"; color: root.dim
                  font.family: root.ff; font.pixelSize: Style.font.title
                }
              }
              BorderSurface {
                width: Style.space(33); height: Style.space(40)
                radius: Style.cornerRadius
                color: Color.background
                borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.codeChars.length > 0 ? root.codeChars.charAt(charCell.index) : "·"
                  color: root.stage === "expired" || root.codeChars.length === 0 ? root.dim : Color.accent
                  font.family: root.ff; font.pixelSize: Style.font.title + Style.space(4); font.bold: true
                }
              }
            }
          }
        }
      }
    }

    Row {
      visible: root.stage === "code" || root.stage === "expired"
      width: parent.width; spacing: Style.space(8)
      BorderSurface {
        id: copyButton
        readonly property bool copied: root.codeText !== "" && root.panel.copiedAuthCode === root.codeText
        width: Style.space(153); height: Style.space(38)
        radius: Style.cornerRadius
        opacity: root.stage === "code" && root.hasCode ? 1 : .5
        color: copyMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
        borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
        Row {
          anchors.centerIn: parent
          spacing: Style.space(10)
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: copyButton.copied ? "check" : "copy"
            color: copyButton.copied ? Color.accent : root.fg; size: Style.space(14)
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: copyButton.copied ? "Скопировано" : "Копировать"; color: copyButton.copied ? Color.accent : root.fg
            font.family: root.ff; font.pixelSize: Style.font.bodySmall + Style.space(1); font.bold: true
          }
          BorderSurface {
            visible: !copyButton.copied
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18); height: Style.space(16)
            radius: 0; color: "transparent"
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "C"; color: root.dim
              font.family: root.ff; font.pixelSize: Style.font.caption
            }
          }
        }
        MouseArea {
          id: copyMouse
          anchors.fill: parent; hoverEnabled: true; enabled: root.stage === "code" && root.hasCode
          cursorShape: Qt.PointingHandCursor
          onClicked: root.panel.copyAuthCode()
        }
      }
      PrimaryButton {
        width: parent.width - copyButton.width - parent.spacing
        enabled: root.stage === "expired" || root.hasCode
        label: root.stage === "expired" ? "Получить новый код" : "Открыть страницу"
        icon: root.stage === "expired" ? "refresh-cw" : "external-link"
        keyHint: root.stage === "expired" ? "R" : "⏎"
        onClicked: root.stage === "expired" ? root.panel.startAuth() : root.panel.openAuthPage()
      }
    }

    Item {
      visible: root.stage === "code" || root.stage === "expired"
      width: parent.width; height: Style.space(15)
      LucideIcon {
        id: waitIcon
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        name: root.stage === "expired" ? "timer-off" : "loader-circle"
        color: root.stage === "expired" ? root.badColor : Color.accent; size: Style.space(14)
        RotationAnimator on rotation {
          running: root.stage === "code" && root.visible
          from: 0; to: 360; duration: 1000; loops: Animation.Infinite
        }
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: waitIcon.right; anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.stage === "expired" ? "Код больше не действует"
          : (root.hasCode ? "Ждём подтверждения…" : "Получаем код…")
        color: root.stage === "expired" ? root.badColor : root.dim
        font.family: root.ff; font.pixelSize: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        visible: root.stage === "code" && root.hasCode && Number(root.panel.data.authExpiresAt || 0) > 0
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        text: "код действует " + root.timeLeft()
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "code" || root.stage === "expired"
      text: "Отменить вход"
      color: cancelMouse.containsMouse ? root.fg : root.dim
      font.family: root.ff; font.pixelSize: Style.font.bodySmall
      MouseArea {
        id: cancelMouse
        anchors.fill: parent; anchors.margins: -Style.space(4)
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.panel.cancelAuth()
      }
    }

    // ── done ────────────────────────────────────────────────────────────
    Rectangle {
      visible: root.stage === "done"
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(72); height: width; radius: width / 2
      color: Color.accent
      LucideIcon {
        anchors.centerIn: parent
        name: "check"; color: Color.background; size: Style.space(30); strokeWidth: 2.5
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "done"
      width: parent.width; horizontalAlignment: Text.AlignHCenter
      text: "Вы вошли"; color: root.fg
      font.family: root.ff; font.pixelSize: Style.font.title + Style.space(4); font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "done" && text !== ""
      width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
      text: [String(root.panel.data.authLogin || ""), root.panel.data.authPlus === true ? "Яндекс Плюс" : ""]
        .filter(function(part) { return part !== "" }).join(" · ")
      color: Color.accent; font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "done"
      width: parent.width; horizontalAlignment: Text.AlignHCenter
      text: "Вкладку браузера можно закрыть."; color: root.dim
      font.family: root.ff; font.pixelSize: Style.font.bodySmall
    }
    PrimaryButton {
      visible: root.stage === "done"
      width: parent.width
      label: "Включить Мою волну"; icon: "radio"
      onClicked: root.panel.finishAuth(true)
    }
    Text {
      textFormat: Text.PlainText
      visible: root.stage === "done"
      width: parent.width; horizontalAlignment: Text.AlignHCenter
      text: "Перейти в медиатеку"
      color: skipMouse.containsMouse ? root.fg : root.dim
      font.family: root.ff; font.pixelSize: Style.font.bodySmall
      MouseArea {
        id: skipMouse
        anchors.fill: parent; anchors.margins: -Style.space(4)
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.panel.finishAuth(false)
      }
    }
  }
}
