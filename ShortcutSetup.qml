import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  property string stage: ""
  property var shortcut: null
  property int selectedButton: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string bindingsPath: root.home + "/.config/hypr/bindings.lua"
  readonly property string declinedPath: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/lightnav/shortcut-declined"
  readonly property string shownLabel: root.shortcut ? root.shortcut.label : "SUPER + N"
  readonly property var buttons: {
    if (root.stage === "offer") return [{ action: "notNow", label: strings.t("setup.notNow") }, { action: "add", label: strings.t("setup.add") }]
    if (root.stage === "added") return [{ action: "done", label: strings.t("setup.done") }]
    return [{ action: "copy", label: root.copied ? strings.t("setup.copied") : strings.t("setup.copy") }, { action: "done", label: strings.t("setup.done") }]
  }
  property bool copied: false

  signal wanted()
  signal finished()

  implicitHeight: content.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function check() {
    bindsProbe.running = true
  }

  function decide(output) {
    if (!output.trim()) return
    var binds = JSON.parse(output)
    if (Model.isSetUp(binds)) return
    root.shortcut = Model.freeShortcut(binds)
    root.show(root.shortcut ? "offer" : "taken")
    root.wanted()
  }

  function show(stage) {
    root.stage = stage
    root.copied = false
    root.selectedButton = root.buttons.length - 1
  }

  function press(index) {
    var action = root.buttons[index].action
    if (action === "add") {
      adder.running = true
    } else if (action === "notNow") {
      root.show("manual")
    } else if (action === "copy") {
      Quickshell.execDetached(["wl-copy", root.command()])
      root.copied = true
    } else {
      if (root.stage !== "added") root.rememberDeclined()
      root.finished()
    }
  }

  function command() {
    return root.stage === "taken" ? Model.shortcutLine("SUPER + N") : Model.manualCommand(root.shownLabel)
  }

  function rememberDeclined() {
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1"', "sh", root.declinedPath])
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.press(root.stage === "offer" ? 0 : root.buttons.length - 1)
    } else if (Util.readingKey(event) === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) {
      root.selectedButton = Math.max(0, root.selectedButton - 1)
    } else if (Util.readingKey(event) === Qt.Key_Right || event.key === Qt.Key_Tab) {
      root.selectedButton = Math.min(root.buttons.length - 1, root.selectedButton + 1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.press(root.selectedButton)
    }
  }

  Process {
    id: bindsProbe
    command: ["sh", "-c", '[ -e "$1" ] || hyprctl binds -j', "sh", root.declinedPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.decide(text)
    }
  }

  Process {
    id: adder
    command: ["sh", "-c", 'printf "%s" "$1" >> "$2" && hyprctl reload >/dev/null', "sh", Model.shortcutBlock(root.shownLabel), root.bindingsPath]
    onExited: function(exitCode) { root.show(exitCode === 0 ? "added" : "failed") }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    wrapMode: Text.WordWrap
  }

  component KeyCap: Rectangle {
    property string label: ""
    width: Math.max(height, keyText.implicitWidth + Style.space(20))
    height: Style.space(38)
    radius: Math.min(Style.cornerRadius, Style.space(4))
    color: Util.alpha(root.foreground, 0.05)
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: Util.alpha(root.foreground, 0.45)

    Text {
      id: keyText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(16)

    PlainText {
      width: parent.width
      text: strings.t("setup.title." + root.stage)
      font.pixelSize: Style.font.heading
    }

    PlainText {
      width: parent.width
      text: strings.t("setup.body." + root.stage).arg(root.shownLabel)
      opacity: 0.7
      font.pixelSize: Style.font.body
      lineHeight: 1.2
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.stage === "offer" || root.stage === "added"
      spacing: Style.space(10)
      topPadding: Style.space(6)
      bottomPadding: Style.space(6)

      Repeater {
        model: root.shownLabel.split(" + ")

        Row {
          required property int index
          required property string modelData
          spacing: Style.space(10)

          PlainText {
            anchors.verticalCenter: parent.verticalCenter
            visible: index > 0
            text: "+"
            opacity: 0.5
            font.pixelSize: Style.font.title
          }

          KeyCap { label: modelData }
        }
      }
    }

    Rectangle {
      width: parent.width
      visible: root.stage === "manual" || root.stage === "taken" || root.stage === "failed"
      height: commandText.implicitHeight + Style.space(20)
      radius: Math.min(Style.cornerRadius, Style.space(4))
      color: Util.alpha(root.foreground, 0.05)
      border.width: Math.max(1, Style.spacing.hairline)
      border.color: Util.alpha(root.foreground, 0.2)

      TextEdit {
        id: commandText
        anchors.fill: parent
        anchors.margins: Style.space(10)
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: root.command()
        color: root.foreground
        selectionColor: Util.alpha(root.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(10)
      topPadding: Style.space(4)

      Repeater {
        model: root.buttons

        BorderSurface {
          required property int index
          required property var modelData
          readonly property bool selected: root.selectedButton === index

          width: Math.max(Style.space(96), buttonText.implicitWidth + Style.space(28))
          height: Style.space(34)
          radius: 0
          color: selected ? root.selectedBackground : "transparent"
          borderSpec: Border.flat(selected ? root.accent : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)

          Text {
            id: buttonText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.label
            color: selected ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedButton = index
            onClicked: root.press(index)
          }
        }
      }
    }
  }
}
