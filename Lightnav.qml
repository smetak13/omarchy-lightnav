import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string mode: "list"
  property string filterText: ""
  property int selectedIndex: 0
  property var rows: []

  readonly property string laptopGlyph: "\uDB80\uDF22"
  readonly property string monitorGlyph: "\uDB80\uDF79"
  readonly property string minimizedWorkspace: "special:minimized"
  readonly property int visibleRows: 6

  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color accent: Commons.Color.menu.selectedText
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Style.space(50)
  readonly property int miniatureHeight: Style.space(28)
  readonly property int listHeight: rowHeight * visibleRows
  readonly property bool settingUp: mode === "setup"
  readonly property int cardWidth: Math.min(Style.space(settingUp ? 460 : 560), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: settingUp
    ? card.contentTopInset + card.contentBottomInset + shortcutSetup.implicitHeight
    : contentMargin * 2 + headerHeight + contentSpacing + listHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
    root.mode = "list"
    root.filterText = ""
    root.rows = []
    root.selectedIndex = 0
    root.opened = true
    root.refresh()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "smetak13.lightnav")
  }

  function refresh() {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.rebuild()
  }

  function monitorGeometry(monitor) {
    var ipc = monitor && monitor.lastIpcObject
    if (!ipc || !ipc.width) return null
    return { x: ipc.x, y: ipc.y, width: ipc.width, height: ipc.height, scale: ipc.scale || 1, transform: ipc.transform || 0 }
  }

  function windowRows() {
    var toplevels = Hyprland.toplevels.values
    var collected = []
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      var ipc = toplevel.lastIpcObject || {}
      if (!ipc.address || ipc.mapped === false) continue
      if (toplevel.wayland && toplevel.wayland.parent) continue

      var appClass = String(ipc.class || (toplevel.wayland && toplevel.wayland.appId) || "")
      var entry = appClass ? DesktopEntries.heuristicLookup(appClass) : null
      var workspace = toplevel.workspace
      var name = entry ? String(entry.name || "") : ""
      if (!name) name = Model.fallbackName(appClass, toplevel.title)
      var title = String(toplevel.title || "")

      collected.push({
        name: name,
        title: title.toLowerCase() === name.toLowerCase() ? "" : title,
        icon: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
        address: String(toplevel.address || ""),
        workspaceId: workspace ? workspace.id : 0,
        minimized: !!workspace && workspace.name === root.minimizedWorkspace,
        monitorName: toplevel.monitor ? String(toplevel.monitor.name || "") : "",
        geometry: root.monitorGeometry(toplevel.monitor),
        at: ipc.at,
        size: ipc.size,
        current: toplevel.activated === true
      })
    }

    for (var j = 0; j < collected.length; j++) {
      var row = collected[j]
      row.slot = Model.slotLabel(row.workspaceId)
      row.internal = Model.isInternalMonitor(row.monitorName)
      row.tiles = row.geometry && row.at && row.size ? Model.miniature(root.workspaceWindows(collected, row.workspaceId), row.geometry, row.address) : []
      row.aspect = row.geometry ? Model.logicalSize(row.geometry).width / Model.logicalSize(row.geometry).height : 16 / 9
      var own = row.tiles.filter(function(tile) { return tile.chosen })[0]
      row.area = own ? own.width * own.height : 0
      row.top = own ? own.y : 0
      row.left = own ? own.x : 0
    }
    return collected
  }

  function workspaceWindows(collected, workspaceId) {
    return collected.filter(function(row) { return row.workspaceId === workspaceId && row.at && row.size })
  }

  function rowKey(row) {
    return row ? row.address : ""
  }

  function rebuild(selectFirst) {
    if (!root.opened) return
    var keepKey = selectFirst ? "" : root.rowKey(root.rows[root.selectedIndex])
    var previousIndex = root.selectedIndex
    root.rows = Model.arrange(root.windowRows(), root.filterText)
    pointerGate.reset()

    var index = selectFirst ? 0 : Math.max(0, Math.min(previousIndex, root.rows.length - 1))
    for (var i = 0; keepKey && i < root.rows.length; i++) {
      if (root.rowKey(root.rows[i]) === keepKey) index = i
    }
    root.selectedIndex = index
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function setFilter(text) {
    root.filterText = text
    root.rebuild(true)
  }

  function select(delta) {
    if (root.rows.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.rows.length - 1, root.selectedIndex + delta))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activate(index) {
    var row = root.rows[index]
    if (row) root.focusWindow(row)
  }

  function focusWindow(row) {
    var address = row.address.indexOf("0x") === 0 ? row.address : "0x" + row.address
    var target = "window = \"address:" + address + "\""
    var steps = []
    if (row.minimized) {
      var monitor = Hyprland.focusedMonitor
      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
      if (workspace >= 1) steps.push("hl.dsp.window.move({ workspace = \"" + workspace + "\", " + target + " })")
    }
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    root.dismiss()
    Util.execDetached(steps.map(function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }).join(" && "))
  }

  function closeWindow(row) {
    if (!row) return
    var address = row.address.indexOf("0x") === 0 ? row.address : "0x" + row.address
    Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.window.close({ window = \"address:" + address + "\" })"))
  }

  function offerShortcut() {
    root.mode = "setup"
    root.opened = true
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  Timer {
    interval: 2500
    running: true
    onTriggered: shortcutSetup.check()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Timer {
    id: refreshSettle
    interval: 60
    onTriggered: root.rebuild()
  }

  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      Hyprland.refreshToplevels()
      refreshSettle.restart()
    }
  }

  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      enabled: root.opened
      function onLastIpcObjectChanged() { refreshSettle.restart() }
    }
  }

  Connections {
    target: Hyprland.toplevels
    enabled: root.opened
    function onValuesChanged() { refreshSettle.restart() }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    elide: Text.ElideRight
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-lightnav"

    onShownChanged: if (shown) refreshSettle.restart()

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent

        Keys.onPressed: function(event) {
          if (root.settingUp) {
            shortcutSetup.handleKey(event)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-root.visibleRows)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(root.visibleRows)
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.closeWindow(root.rows[root.selectedIndex])
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      ShortcutSetup {
        id: shortcutSetup
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.settingUp
        onWanted: root.offerShortcut()
        onFinished: root.dismiss()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing
        visible: !root.settingUp

        Item {
          width: parent.width
          height: root.headerHeight

          FilterInput {
            id: filterInput
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            keyHandler: keyCatcher
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            onTextChanged: if (text !== root.filterText) root.setFilter(text)
          }

          Connections {
            target: root
            function onFilterTextChanged() { if (filterInput.text !== root.filterText) filterInput.text = root.filterText }
          }

          PlainText {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !root.filterText && !filterInput.preeditText
            text: strings.t("search.placeholder")
            opacity: 0.58
            font.pixelSize: Style.font.heading
          }
        }

        Item {
          width: parent.width
          height: root.listHeight

          ListView {
            id: resultList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            delegate: windowDelegate
          }

          PlainText {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.rows.length === 0
            text: root.filterText ? strings.t("search.noMatches").arg(root.filterText) : strings.t("search.empty")
            opacity: 0.7
            font.pixelSize: Style.font.title
          }
        }
      }
    }
  }

  Component {
    id: windowDelegate

    Rectangle {
      id: windowRow
      required property int index
      required property var modelData

      readonly property bool hasCursor: index === root.selectedIndex

      width: ListView.view.width
      height: root.rowHeight
      radius: root.cornerRadius
      color: hasCursor ? root.selectedBackground : "transparent"

      Item {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        opacity: windowRow.modelData.current ? 0.45 : 1

        IconImage {
          id: appIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          implicitSize: Style.space(28)
          source: windowRow.modelData.icon
          asynchronous: true
        }

        Column {
          anchors.left: appIcon.right
          anchors.leftMargin: Style.space(12)
          anchors.right: miniature.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: appName.height

            PlainText {
              id: appName
              width: Math.min(implicitWidth, parent.width)
              text: windowRow.modelData.name
              color: windowRow.hasCursor ? root.accent : root.foreground
              font.pixelSize: Style.font.title
            }

            PlainText {
              anchors.left: appName.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.baseline: appName.baseline
              visible: text.length > 0
              text: windowRow.modelData.title
              opacity: 0.5
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            spacing: Style.space(6)

            Rectangle {
              width: Math.max(Style.space(16), slotText.implicitWidth + Style.space(6))
              height: Style.space(16)
              radius: Math.min(root.cornerRadius, Style.space(3))
              color: "transparent"
              border.width: Math.max(1, Style.spacing.hairline)
              border.color: Util.alpha(root.foreground, 0.45)

              PlainText {
                id: slotText
                anchors.centerIn: parent
                text: windowRow.modelData.slot
                font.pixelSize: Style.font.caption
              }
            }

            PlainText {
              anchors.verticalCenter: parent.verticalCenter
              text: windowRow.modelData.internal ? root.laptopGlyph : root.monitorGlyph
              opacity: 0.7
              font.pixelSize: Style.font.body
            }
          }
        }

        Rectangle {
          id: miniature
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: windowRow.modelData.tiles.length > 0
          height: root.miniatureHeight
          width: visible ? Math.round(height * windowRow.modelData.aspect) : 0
          radius: Math.min(root.cornerRadius, Style.space(3))
          color: "transparent"
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: Util.alpha(root.foreground, 0.35)

          Repeater {
            model: windowRow.modelData.tiles
            delegate: Rectangle {
              required property var modelData
              readonly property real inset: Style.space(2)
              x: inset + modelData.x * (miniature.width - inset * 2)
              y: inset + modelData.y * (miniature.height - inset * 2)
              width: Math.max(1, modelData.width * (miniature.width - inset * 2) - 1)
              height: Math.max(1, modelData.height * (miniature.height - inset * 2) - 1)
              radius: Math.min(root.cornerRadius, Style.space(1))
              color: modelData.chosen ? Util.alpha(root.accent, 0.85) : Util.alpha(root.foreground, 0.16)
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) { if (pointerGate.moved(windowRow, mouse)) root.selectedIndex = windowRow.index }
        onClicked: root.activate(windowRow.index)
      }
    }
  }
}
