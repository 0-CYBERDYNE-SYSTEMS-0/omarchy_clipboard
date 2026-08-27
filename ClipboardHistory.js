var MAX_ENTRIES = 300
var MAX_TEXT_CHARS = 16384
var MAX_PATH_CHARS = 4096
var MAX_MIME_CHARS = 128
var MAX_ID_CHARS = 128
var MAX_BOARD_CHARS = 64
var MAX_KIND_CHARS = 32
var MAX_CAPTURED_CHARS = 64
var MAX_HISTORY_JSON_CHARS = 4 * 1024 * 1024
var MAX_STATE_JSON_CHARS = 256 * 1024

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function hashString(value) {
  var s = String(value || "")
  var h = 2166136261
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h * 16777619) >>> 0
  }
  return (h >>> 0).toString(16)
}

function makeId(entry) {
  return hashString(entryKey(entry))
}

function looksLikeIsoDate(value) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(String(value || ""))
}

function nowIso() {
  var d = new Date()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    + "T" + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function formatCapturedAt(value) {
  var raw = String(value || "")
  if (!raw) return ""
  if (!looksLikeIsoDate(raw)) return raw

  var d = new Date(raw)
  if (isNaN(d.getTime())) return raw

  var now = new Date()
  var hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  var sameDay = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth()
    && d.getDate() === now.getDate()
  if (sameDay) return hm
  return (d.getMonth() + 1) + "/" + d.getDate() + " " + hm
}

function detectKind(entry) {
  if (!entry) return "text"
  if (entry.snippet || entry.kind === "snippet") return "snippet"
  if (entry.type === "image") return "image"

  var paths = filePaths(entry)
  if (paths.length > 0) return "file"

  var t = String(entry.text || "").trim()
  if (!t) return "text"
  if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t)) return "color"
  if (/^rgba?\(/i.test(t) || /^hsla?\(/i.test(t)) return "color"
  if (/^https?:\/\//i.test(t) || /^www\./i.test(t)) return "url"
  if (/^#!\//.test(t)) return "code"
  if (t.indexOf("\n") !== -1 && /[{;}]/.test(t) && t.length > 40) return "code"
  return "text"
}

function kindLabel(kind) {
  var key = String(kind || "text")
  if (key === "url") return "Link"
  if (key === "color") return "Color"
  if (key === "code") return "Code"
  if (key === "file") return "File"
  if (key === "image") return "Image"
  if (key === "snippet") return "Snippet"
  return "Text"
}

function kindIcon(kind) {
  var key = String(kind || "text")
  if (key === "url") return "󰌷"
  if (key === "color") return "󰏘"
  if (key === "code") return "󰅴"
  if (key === "file") return "󰈔"
  if (key === "image") return "󰋩"
  if (key === "snippet") return "󰩺"
  return "󰊄"
}

function normalizeEntry(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? normalizeEntry({ type: "text", text: value }) : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  var entry = null

  if (type === "text") {
    var text = String(value.text || "")
    if (text.trim().length === 0 || text.length > MAX_TEXT_CHARS) return null
    entry = { type: "text", text: text }
  } else if (type === "image") {
    var path = String(value.path || "")
    var mime = String(value.mime || "image/png")
    if (!path || path.length > MAX_PATH_CHARS || mime.length > MAX_MIME_CHARS) return null
    entry = {
      type: "image",
      path: path,
      mime: mime
    }
  } else {
    return null
  }

  if (value.capturedAt !== undefined && value.capturedAt !== null) {
    var capturedAt = String(value.capturedAt)
    if (capturedAt.length > 0 && capturedAt.length <= MAX_CAPTURED_CHARS)
      entry.capturedAt = capturedAt
  }
  if (value.id) {
    var id = String(value.id)
    if (id.length > 0 && id.length <= MAX_ID_CHARS) entry.id = id
  }
  if (value.pinned === true || value.pinned === "true") entry.pinned = true
  if (value.snippet === true || value.snippet === "true") entry.snippet = true
  if (value.board) {
    var board = String(value.board)
    if (board.length > 0 && board.length <= MAX_BOARD_CHARS) entry.board = board
  }

  if (entry.snippet) entry.kind = "snippet"
  else if (value.kind && String(value.kind) !== "snippet") {
    var kind = String(value.kind)
    entry.kind = kind.length <= MAX_KIND_CHARS ? kind : detectKind(entry)
  } else entry.kind = detectKind(entry)

  if (entry.snippet) {
    entry.pinned = true
    entry.kind = "snippet"
  }

  if (!entry.id) entry.id = makeId(entry)
  return entry
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function parseHistory(raw) {
  try {
    var source = String(raw || "[]")
    if (source.length > MAX_HISTORY_JSON_CHARS) return []
    var parsed = JSON.parse(source)
    var next = []
    if (!Array.isArray(parsed)) return next

    var cap = Math.min(parsed.length, MAX_ENTRIES * 2)
    for (var i = 0; i < cap; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return trimHistory(next, MAX_ENTRIES)
  } catch (e) {
    return []
  }
}

function isProtected(entry) {
  return !!(entry && (entry.pinned || entry.snippet))
}

function trimHistory(history, limit) {
  var max = limit === undefined || limit === null ? MAX_ENTRIES : Number(limit)
  if (isNaN(max)) max = MAX_ENTRIES
  max = Math.max(0, Math.min(MAX_ENTRIES, max))

  var values = Array.isArray(history) ? history : []
  var kept = []
  var unpinned = 0
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue
    if (isProtected(entry)) {
      kept.push(entry)
    } else if (unpinned < max) {
      kept.push(entry)
      unpinned++
    }
  }
  return kept
}

function addEntry(history, entry, limit) {
  var normalized = normalizeEntry(entry)
  var values = Array.isArray(history) ? history.slice() : []
  if (!normalized) return trimHistory(values, limit)

  var key = entryKey(normalized)
  var existingIndex = -1
  for (var i = 0; i < values.length; i++) {
    var existing = normalizeEntry(values[i])
    values[i] = existing
    if (existing && entryKey(existing) === key) {
      existingIndex = i
      break
    }
  }

  if (existingIndex >= 0) {
    var old = values[existingIndex]
    normalized.id = old.id || normalized.id
    if (old.pinned) normalized.pinned = true
    if (old.snippet) {
      normalized.snippet = true
      normalized.pinned = true
      normalized.kind = "snippet"
    }
    if (old.board && !normalized.board) normalized.board = old.board
    if (!normalized.capturedAt) normalized.capturedAt = old.capturedAt
    values.splice(existingIndex, 1)
  }

  if (!normalized.capturedAt) normalized.capturedAt = nowIso()
  values.unshift(normalized)
  return trimHistory(values, limit)
}

function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

function clearHistory(history, keepProtected) {
  if (!keepProtected) return []
  var values = Array.isArray(history) ? history : []
  var kept = []
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (entry && isProtected(entry)) kept.push(entry)
  }
  return kept
}

function updateEntryAt(history, index, mutator) {
  var values = Array.isArray(history) ? history.slice() : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values
  var entry = normalizeEntry(values[target])
  if (!entry) return values
  var next = mutator(entry)
  if (!next) {
    values.splice(target, 1)
    return values
  }
  values[target] = normalizeEntry(next)
  return values
}

function setPinned(history, index, pinned) {
  return updateEntryAt(history, index, function(entry) {
    if (pinned) entry.pinned = true
    else {
      delete entry.pinned
      if (entry.snippet) {
        delete entry.snippet
        entry.kind = detectKind({ type: entry.type, text: entry.text, path: entry.path, mime: entry.mime })
      }
    }
    return entry
  })
}

function setSnippet(history, index, snippet) {
  return updateEntryAt(history, index, function(entry) {
    if (snippet) {
      entry.snippet = true
      entry.pinned = true
      entry.kind = "snippet"
    } else {
      delete entry.snippet
      entry.kind = detectKind({ type: entry.type, text: entry.text, path: entry.path, mime: entry.mime })
    }
    return entry
  })
}

function setBoard(history, index, board) {
  return updateEntryAt(history, index, function(entry) {
    var name = String(board || "").trim()
    if (name && name !== "inbox" && name !== "all" && name.length <= MAX_BOARD_CHARS) entry.board = name
    else delete entry.board
    return entry
  })
}

function findIndexById(history, id) {
  var values = Array.isArray(history) ? history : []
  var key = String(id || "")
  if (!key) return -1
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (entry && String(entry.id || "") === key) return i
  }
  return -1
}

function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image")
    return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "") + " " + String(entry.board || "")
  return String(entry.text || "") + " " + fileEntryText(entry) + " " + String(entry.board || "") + " " + String(entry.kind || "")
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = formatCapturedAt(entry && entry.capturedAt || "")
  var label = String(entry && entry.mime || "") === "image/png" ? "Screenshot" : "Image"
  if (!timestamp) return label
  return label + " · " + timestamp
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

function colorValue(entry) {
  if (!entry || entry.kind !== "color") return ""
  return String(entry.text || "").trim()
}

function parseState(raw) {
  try {
    var source = String(raw || "{}")
    if (source.length > MAX_STATE_JSON_CHARS) return { boards: [], stack: [] }
    var parsed = JSON.parse(source)
    if (!parsed || typeof parsed !== "object") parsed = {}
    var boards = []
    var seen = {}
    var boardSource = Array.isArray(parsed.boards) ? parsed.boards : []
    for (var i = 0; i < boardSource.length && boards.length < 64; i++) {
      var name = String(boardSource[i] || "").trim()
      if (!name || name.length > MAX_BOARD_CHARS || name === "all" || name === "inbox" || seen[name]) continue
      seen[name] = true
      boards.push(name)
    }
    var stack = []
    var stackSource = Array.isArray(parsed.stack) ? parsed.stack : []
    for (var j = 0; j < stackSource.length && stack.length < MAX_ENTRIES; j++) {
      var id = String(stackSource[j] || "")
      if (id && id.length <= MAX_ID_CHARS) stack.push(id)
    }
    return { boards: boards, stack: stack }
  } catch (e) {
    return { boards: [], stack: [] }
  }
}

function collectBoards(history, savedBoards) {
  var boards = []
  var seen = {}
  var extras = Array.isArray(savedBoards) ? savedBoards : []
  for (var i = 0; i < extras.length; i++) {
    var extra = String(extras[i] || "").trim()
    if (!extra || seen[extra]) continue
    seen[extra] = true
    boards.push(extra)
  }
  var values = Array.isArray(history) ? history : []
  for (var j = 0; j < values.length; j++) {
    var board = values[j] && values[j].board ? String(values[j].board).trim() : ""
    if (!board || seen[board]) continue
    seen[board] = true
    boards.push(board)
  }
  return boards
}

function addBoard(state, name) {
  var next = parseState(JSON.stringify(state || {}))
  var board = String(name || "").trim()
  if (!board || board === "all" || board === "inbox") return next
  for (var i = 0; i < next.boards.length; i++) {
    if (next.boards[i] === board) return next
  }
  next.boards.push(board)
  return next
}

function toggleStack(state, id) {
  var next = parseState(JSON.stringify(state || {}))
  var key = String(id || "")
  if (!key) return next
  var found = -1
  for (var i = 0; i < next.stack.length; i++) {
    if (next.stack[i] === key) { found = i; break }
  }
  if (found >= 0) next.stack.splice(found, 1)
  else next.stack.push(key)
  return next
}

function clearStack(state) {
  var next = parseState(JSON.stringify(state || {}))
  next.stack = []
  return next
}

function stackEntries(history, state) {
  var parsed = parseState(JSON.stringify(state || {}))
  var values = Array.isArray(history) ? history : []
  var rows = []
  for (var i = 0; i < parsed.stack.length; i++) {
    var index = findIndexById(values, parsed.stack[i])
    if (index < 0) continue
    rows.push({ entry: values[index], index: index })
  }
  return rows
}

var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  var copy = {
    type: "text",
    text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit)
  }
  if (entry.id) copy.id = entry.id
  if (entry.kind) copy.kind = entry.kind
  if (entry.pinned) copy.pinned = true
  if (entry.snippet) copy.snippet = true
  if (entry.board) copy.board = entry.board
  if (entry.capturedAt) copy.capturedAt = entry.capturedAt
  return copy
}

function matchesFilter(entry, query, options) {
  var opts = options || {}
  if (!entry) return false

  if (opts.pinnedOnly && !entry.pinned && !entry.snippet) return false
  if (opts.snippetOnly && !entry.snippet) return false

  var kind = String(opts.kind || "")
  if (kind && kind !== "all" && entry.kind !== kind) return false

  var board = String(opts.board || "")
  if (board === "inbox") {
    if (entry.board) return false
  } else if (board && board !== "all") {
    if (String(entry.board || "") !== board) return false
  }

  var needle = String(query || "").trim().toLowerCase()
  if (needle && searchableText(entry).toLowerCase().indexOf(needle) < 0) return false
  return true
}

function displayRows(history, query, limit, options) {
  var values = Array.isArray(history) ? history : []
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  if (max === 0) return []

  var opts = options || {}
  var stack = {}
  var stackIds = opts.stackIds || (opts.state && opts.state.stack) || []
  for (var s = 0; s < stackIds.length; s++) stack[String(stackIds[s])] = true

  var rows = []
  for (var i = 0; i < values.length; i++) {
    var entry = cappedEntry(normalizeEntry(values[i]))
    if (!matchesFilter(entry, query, opts)) continue

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var isImage = entry.type === "image"
    var previewPath = isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "")
    rows.push({
      id: String(entry.id || ""),
      entryType: isFile ? "file" : entry.type,
      kind: String(entry.kind || detectKind(entry)),
      kindLabel: kindLabel(entry.kind || detectKind(entry)),
      kindIcon: kindIcon(entry.kind || detectKind(entry)),
      fullText: isImage ? "" : fullText(entry),
      previewText: previewText(entry),
      previewImage: previewPath,
      path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      index: i,
      pinned: !!entry.pinned,
      snippet: !!entry.snippet,
      board: String(entry.board || ""),
      capturedAt: formatCapturedAt(entry.capturedAt || ""),
      colorValue: colorValue(entry),
      inStack: !!stack[String(entry.id || "")]
    })
    if (rows.length >= max) break
  }

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_ENTRIES: MAX_ENTRIES,
    MAX_TEXT_CHARS: MAX_TEXT_CHARS,
    MAX_PATH_CHARS: MAX_PATH_CHARS,
    MAX_HISTORY_JSON_CHARS: MAX_HISTORY_JSON_CHARS,
    MAX_STATE_JSON_CHARS: MAX_STATE_JSON_CHARS,
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    parseHistory: parseHistory,
    addEntry: addEntry,
    removeEntryAt: removeEntryAt,
    clearHistory: clearHistory,
    parseEntryJson: parseEntryJson,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    displayRows: displayRows,
    detectKind: detectKind,
    kindLabel: kindLabel,
    kindIcon: kindIcon,
    setPinned: setPinned,
    setSnippet: setSnippet,
    setBoard: setBoard,
    findIndexById: findIndexById,
    parseState: parseState,
    collectBoards: collectBoards,
    addBoard: addBoard,
    toggleStack: toggleStack,
    clearStack: clearStack,
    stackEntries: stackEntries,
    formatCapturedAt: formatCapturedAt,
    nowIso: nowIso,
    trimHistory: trimHistory,
    matchesFilter: matchesFilter
  }
}
