import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []
  property var pasteState: ({ boards: [], stack: [] })
  property string filterKind: "all"
  property string filterBoard: "all"
  property string promptMode: ""
  property string promptText: ""

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-extras.json"
  property string pluginDir: (root.manifest && root.manifest.__sourceDir)
    ? String(root.manifest.__sourceDir)
    : (Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.0-cyberdyne-systems-0.clipboard")
  property string captureScript: root.pluginDir + "/capture.sh"
  property string pasteBin: root.pluginDir + "/bin/omarchy-clips"
  property var kindChipIds: ["all", "pins", "text", "url", "image", "color", "code", "file", "snippet"]

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property real textScale: 1.5
  readonly property int fontCaption: Math.round(Style.font.caption * textScale)
  readonly property int fontBody: Math.round(Style.font.body * textScale)
  readonly property int fontTitle: Math.round(Style.font.title * textScale)
  readonly property int fontHeading: Math.round(Style.font.heading * textScale)
  readonly property int fontDisplay: Math.round(Style.font.displayLarge * textScale)
  property int contentMargin: Style.spacing.panelPadding + Style.space(6)
  property int headerHeight: Math.max(Style.space(48), root.fontHeading + Style.spacing.controlPaddingY * 2)
  property int chipHeight: Math.max(Style.space(36), root.fontCaption + Style.spacing.sm)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(1400), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(880), panel.height - Style.gapsOut * 2)
  property int sidebarWidth: Style.space(200)
  property int rowHeight: Math.max(Style.space(78), root.fontTitle + root.fontCaption + Style.spacing.rowPaddingX * 2)
  property int footerHeight: Math.max(Style.space(32), root.fontCaption + Style.spacing.xs)
  property int historyLimit: 300

  function kindChipLabel(id) {
    if (id === "all") return "All"
    if (id === "pins") return "Pins"
    return ClipboardHistory.kindLabel(id)
  }

  function placeholderText() {
    if (root.promptMode === "board") return "New board name…"
    if (root.promptMode === "assign") return "Move to board…"
    return "Search clipboard…"
  }

  function headerText() {
    if (root.promptMode) return root.promptText || root.placeholderText()
    return root.filterText || root.placeholderText()
  }

  function footerText() {
    if (root.promptMode) return "Enter save   Esc cancel"
    var stack = (root.pasteState && root.pasteState.stack) ? root.pasteState.stack.length : 0
    var extra = stack > 0 ? ("   ^↵ paste stack " + stack) : ""
    return "↵ paste   ⇧↵ copy   ^P pin   ^S snippet   ^B board   ^N new   ^Space stack   ^[ ] type" + extra
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.promptMode = ""
    root.promptText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildBoards()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.promptMode = ""
    root.promptText = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    root.rebuildBoards()
    if (root.opened) root.rebuildDisplay()
  }

  function loadState(raw) {
    root.pasteState = ClipboardHistory.parseState(raw)
    root.rebuildBoards()
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.history.length), null, 2) + "\n")
  }

  function saveState() {
    stateFile.setText(JSON.stringify(root.pasteState, null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry)
    if (!normalized) return

    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line))
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory(root.history, true)
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildBoards()
    root.rebuildDisplay()
  }

  function currentOptions() {
    return {
      board: root.filterBoard,
      kind: (root.filterKind === "all" || root.filterKind === "pins") ? "" : root.filterKind,
      pinnedOnly: root.filterKind === "pins",
      snippetOnly: root.filterKind === "snippet",
      stackIds: (root.pasteState && root.pasteState.stack) ? root.pasteState.stack : []
    }
  }

  function rebuildBoards() {
    var boards = ClipboardHistory.collectBoards(root.history, root.pasteState ? root.pasteState.boards : [])
    boardModel.clear()
    boardModel.append({ boardId: "all", label: "All" })
    boardModel.append({ boardId: "inbox", label: "Inbox" })
    for (var i = 0; i < boards.length; i++)
      boardModel.append({ boardId: boards[i], label: boards[i] })
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50, root.currentOptions())

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryId: row.id,
        entryType: row.entryType,
        kind: row.kind,
        kindLabel: row.kindLabel,
        kindIcon: row.kindIcon,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index,
        pinned: row.pinned,
        snippet: row.snippet,
        board: row.board,
        capturedAt: row.capturedAt,
        colorValue: row.colorValue,
        inStack: row.inStack
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setKind(nextKind) {
    root.filterKind = nextKind
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setBoardFilter(nextBoard) {
    root.filterBoard = nextBoard
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function cycleKind(delta) {
    var ids = root.kindChipIds
    var current = 0
    for (var i = 0; i < ids.length; i++) if (ids[i] === root.filterKind) current = i
    var next = (current + delta + ids.length) % ids.length
    root.setKind(ids[next])
  }

  function cycleBoard(delta) {
    if (boardModel.count === 0) return
    var current = 0
    for (var i = 0; i < boardModel.count; i++) {
      if (boardModel.get(i).boardId === root.filterBoard) current = i
    }
    var next = (current + delta + boardModel.count) % boardModel.count
    root.setBoardFilter(boardModel.get(next).boardId)
  }

  function startPrompt(mode) {
    root.promptMode = mode
    root.promptText = ""
    root.disarmPointer()
  }

  function cancelPrompt() {
    root.promptMode = ""
    root.promptText = ""
  }

  function confirmPrompt() {
    var name = String(root.promptText || "").trim()
    var mode = root.promptMode
    root.cancelPrompt()
    if (!name) return
    root.pasteState = ClipboardHistory.addBoard(root.pasteState, name)
    root.saveState()
    if (mode === "assign" || root.cursorActive)
      root.assignBoard(root.selectedIndex, name)
    root.filterBoard = name
    root.rebuildBoards()
    root.rebuildDisplay()
  }

  function togglePin(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.history = ClipboardHistory.setPinned(root.history, row.historyIndex, !row.pinned)
    root.saveHistory()
    root.rebuildDisplay()
  }

  function toggleSnippet(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.history = ClipboardHistory.setSnippet(root.history, row.historyIndex, !row.snippet)
    root.saveHistory()
    root.rebuildDisplay()
  }

  function assignBoard(index, board) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.history = ClipboardHistory.setBoard(root.history, row.historyIndex, board)
    root.saveHistory()
    root.rebuildBoards()
    root.rebuildDisplay()
  }

  function assignToCurrentBoard(index) {
    if (root.filterBoard === "all") {
      root.startPrompt("assign")
      return
    }
    root.assignBoard(index, root.filterBoard === "inbox" ? "" : root.filterBoard)
  }

  function toggleStack(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (!row.entryId) return
    root.pasteState = ClipboardHistory.toggleStack(root.pasteState, row.entryId)
    root.saveState()
    root.rebuildDisplay()
  }

  function pasteStack() {
    if (!root.pasteState || !root.pasteState.stack || root.pasteState.stack.length === 0) return
    root.opened = false
    Quickshell.execDetached([root.pasteBin, "stack", "paste"])
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row)
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.copySelected(row)
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.openSelected(row)
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }
  ListModel { id: boardModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
    onFileChanged: reload()
  }

  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/(shell/plugins/clipboard|plugins/.*/clipboard)/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
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
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (root.promptMode) {
            if (event.key === Qt.Key_Escape) {
              root.cancelPrompt()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.confirmPrompt()
              event.accepted = true
            } else if (Util.editsFilter(event, root.promptText)) {
              root.promptText = Util.editedFilter(event, root.promptText)
              event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.promptText += event.text
              event.accepted = true
            }
            return
          }

          if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_P) {
              root.togglePin(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_S) {
              root.toggleSnippet(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_B) {
              root.assignToCurrentBoard(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_N) {
              root.startPrompt("board")
              event.accepted = true
            } else if (event.key === Qt.Key_Space) {
              root.toggleStack(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.pasteStack()
              event.accepted = true
            } else if (event.key === Qt.Key_BracketLeft) {
              root.cycleKind(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_BracketRight) {
              root.cycleKind(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              root.cycleBoard((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
              event.accepted = true
            }
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier)) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete unpinned clipboard history? Pins and snippets are kept."
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText()
            color: root.foreground
            opacity: (root.promptMode ? root.promptText : root.filterText) ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.fontHeading
            elide: Text.ElideRight
          }
        }

        Flickable {
          width: parent.width
          height: root.chipHeight
          contentWidth: chipRow.width
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.HorizontalFlick

          Row {
            id: chipRow
            spacing: Style.space(6)
            height: parent.height

            Repeater {
              model: root.kindChipIds
              delegate: Rectangle {
                required property string modelData
                readonly property bool selected: root.filterKind === modelData
                height: root.chipHeight
                width: chipLabel.implicitWidth + Style.space(14)
                radius: height / 2
                color: selected ? root.selectedBackground : "transparent"
                border.width: Style.normalBorderWidth
                border.color: selected ? root.selectedText : Util.alpha(root.border, 0.28)

                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: root.kindChipLabel(parent.modelData)
                  color: parent.selected ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontCaption
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setKind(parent.modelData)
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.chipHeight - root.footerHeight - root.contentSpacing * 3

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: root.sidebarWidth
              height: parent.height
              clip: true

              ListView {
                id: boardList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: boardModel
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  required property int index
                  required property string boardId
                  required property string label
                  readonly property bool selected: root.filterBoard === boardId

                  width: ListView.view.width
                  height: Math.max(Style.space(36), root.fontBody + Style.spacing.sm)
                  radius: root.cornerRadius
                  color: selected ? root.selectedBackground : "transparent"

                  Text {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    text: label
                    color: parent.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontBody
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setBoardFilter(boardId)
                  }
                }
              }
            }

            Item {
              width: (parent.width - root.sidebarWidth) / 2
              height: parent.height
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string entryType
                  required property string kind
                  required property string kindLabel
                  required property string kindIcon
                  required property string previewText
                  required property string fullText
                  required property string previewImage
                  required property bool pinned
                  required property bool snippet
                  required property string board
                  required property string capturedAt
                  required property string colorValue
                  required property bool inStack

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    anchors.topMargin: Style.space(6)
                    anchors.bottomMargin: Style.space(6)
                    spacing: Style.space(10)

                    Rectangle {
                      visible: row.colorValue.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      radius: Style.space(4)
                      color: row.colorValue.length > 0 ? row.colorValue : "transparent"
                      border.width: Style.normalBorderWidth
                      border.color: Util.alpha(root.border, 0.4)
                    }

                    Image {
                      visible: row.previewImage.length > 0 && row.colorValue.length === 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: row.previewImage
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Column {
                      width: parent.width - (
                        (row.colorValue.length > 0 || row.previewImage.length > 0) ? parent.height + parent.spacing : 0
                      )
                      height: parent.height
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        text: (row.pinned ? "󰐃 " : "") + (row.inStack ? "≡ " : "") + row.previewText
                        color: row.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fontTitle
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                      }

                      Text {
                        width: parent.width
                        text: row.kindIcon + " " + row.kindLabel
                          + (row.board ? " · " + row.board : "")
                          + (row.capturedAt ? " · " + row.capturedAt : "")
                          + (row.snippet ? " · snippet" : "")
                        color: row.hasCursor ? root.selectedText : root.foreground
                        opacity: 0.62
                        font.family: root.fontFamily
                        font.pixelSize: root.fontCaption
                        elide: Text.ElideRight
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              width: (parent.width - root.sidebarWidth) / 2
              height: parent.height
              clip: true

              property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Column {
                visible: parent.activeRow && !parent.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: 0
                spacing: Style.space(10)

                Rectangle {
                  visible: parent.parent.activeRow && parent.parent.activeRow.colorValue
                  width: Math.min(parent.width, Style.space(220))
                  height: visible ? Style.space(96) : 0
                  radius: root.cornerRadius
                  color: (parent.parent.activeRow && parent.parent.activeRow.colorValue) ? parent.parent.activeRow.colorValue : "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: Util.alpha(root.border, 0.4)
                }

                Text {
                  width: parent.width
                  height: parent.height - (parent.children[0].visible ? parent.children[0].height + parent.spacing : 0)
                  text: parent.parent.activeRow ? parent.parent.activeRow.fullText : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontTitle
                  wrapMode: Text.WrapAnywhere
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignTop
                }
              }

              Image {
                visible: parent.activeRow && parent.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: 0
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                source: parent.activeRow ? parent.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
                verticalAlignment: Image.AlignTop
                asynchronous: true
                smooth: true
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: root.fontDisplay
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: root.fontTitle
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: root.footerText()
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: root.fontCaption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
