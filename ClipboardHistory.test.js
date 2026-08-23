const H = require("./ClipboardHistory.js")
const assert = require("assert")

function test(name, fn) {
  fn()
  console.log("ok", name)
}

test("normalize old text and image", () => {
  const text = H.normalizeEntry({ type: "text", text: "hello" })
  assert.strictEqual(text.type, "text")
  assert.strictEqual(text.kind, "text")
  assert.ok(text.id)
  const image = H.normalizeEntry({ type: "image", path: "/tmp/a.png", mime: "image/png", capturedAt: "Saturday 15:02" })
  assert.strictEqual(image.kind, "image")
  assert.strictEqual(image.capturedAt, "Saturday 15:02")
})

test("kind detection", () => {
  assert.strictEqual(H.detectKind({ type: "text", text: "https://omarchy.org" }), "url")
  assert.strictEqual(H.detectKind({ type: "text", text: "#aabbcc" }), "color")
  assert.strictEqual(H.detectKind({ type: "text", text: "file:///home/a/b.txt" }), "file")
  assert.strictEqual(H.detectKind({ type: "text", text: "#!/bin/bash\necho hi\n" }), "code")
  assert.strictEqual(H.detectKind({ type: "image", path: "/x.png" }), "image")
})

test("recopy preserves pin board snippet id", () => {
  let history = []
  history = H.addEntry(history, { type: "text", text: "secret token" }, 10)
  history = H.setPinned(history, 0, true)
  history = H.setBoard(history, 0, "Work")
  history = H.setSnippet(history, 0, true)
  const id = history[0].id
  history = H.addEntry(history, { type: "text", text: "secret token" }, 10)
  assert.strictEqual(history.length, 1)
  assert.strictEqual(history[0].id, id)
  assert.strictEqual(history[0].pinned, true)
  assert.strictEqual(history[0].snippet, true)
  assert.strictEqual(history[0].board, "Work")
  assert.strictEqual(history[0].kind, "snippet")
})

test("pinned and snippets survive trim", () => {
  let history = []
  history = H.addEntry(history, { type: "text", text: "keep me" }, 2)
  history = H.setSnippet(history, 0, true)
  history = H.addEntry(history, { type: "text", text: "a" }, 2)
  history = H.addEntry(history, { type: "text", text: "b" }, 2)
  history = H.addEntry(history, { type: "text", text: "c" }, 2)
  const texts = history.map((e) => e.text).sort()
  assert.ok(texts.indexOf("keep me") >= 0)
  assert.ok(history.length <= 3)
})

test("display rows filter board kind pin", () => {
  let history = []
  history = H.addEntry(history, { type: "text", text: "https://a.example" }, 20)
  history = H.setBoard(history, 0, "Work")
  history = H.addEntry(history, { type: "text", text: "#fff" }, 20)
  history = H.setPinned(history, 0, true)
  history = H.addEntry(history, { type: "text", text: "plain note" }, 20)

  const work = H.displayRows(history, "", 50, { board: "Work" })
  assert.strictEqual(work.length, 1)
  assert.strictEqual(work[0].kind, "url")

  const pins = H.displayRows(history, "", 50, { pinnedOnly: true })
  assert.strictEqual(pins.length, 1)
  assert.strictEqual(pins[0].kind, "color")

  const colors = H.displayRows(history, "", 50, { kind: "color" })
  assert.strictEqual(colors.length, 1)

  const search = H.displayRows(history, "plain", 50, { board: "all" })
  assert.strictEqual(search.length, 1)
})

test("stack toggle and boards", () => {
  let state = H.parseState("{}")
  state = H.addBoard(state, "Work")
  state = H.addBoard(state, "Work")
  assert.deepStrictEqual(state.boards, ["Work"])
  state = H.toggleStack(state, "abc")
  state = H.toggleStack(state, "def")
  state = H.toggleStack(state, "abc")
  assert.deepStrictEqual(state.stack, ["def"])
})

test("clear keeps protected when asked", () => {
  let history = H.addEntry([], { type: "text", text: "temp" }, 10)
  history = H.addEntry(history, { type: "text", text: "saved" }, 10)
  history = H.setPinned(history, 0, true)
  const cleared = H.clearHistory(history, true)
  assert.strictEqual(cleared.length, 1)
  assert.strictEqual(cleared[0].text, "saved")
})

console.log("all tests passed")
