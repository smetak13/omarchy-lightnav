const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("slot label matches the bar's per-monitor numbering", () => {
  const labels = [1, 3, 10, 13, 20].map(id => Model.slotLabel(id))

  assert.deepEqual(labels, ["1", "3", "0", "3", "0"])
})

test("special workspaces such as the scratchpad are labelled S", () => {
  const label = Model.slotLabel(-98)

  assert.equal(label, "S")
})

test("built-in panels count as the laptop monitor and everything else as external", () => {
  const internal = ["eDP-1", "eDP-2", "LVDS-1", "DSI-1", "DP-3", "HDMI-A-1"].map(Model.isInternalMonitor)

  assert.deepEqual(internal, [true, true, true, true, false, false])
})

const row = (name, title = "", extra = {}) => ({ name, title, ...extra })
const names = rows => rows.map(r => r.name)

test("with no query windows are listed largest first, whatever the app", () => {
  const rows = [
    row("Chromium", "", { area: 0.25, top: 0, left: 0.5, workspaceId: 1 }),
    row("Obsidian", "", { area: 1, top: 0, left: 0, workspaceId: 3 }),
    row("Discord", "", { area: 0.25, top: 0.5, left: 0.5, workspaceId: 1 }),
    row("foot", "", { area: 0.5, top: 0, left: 0, workspaceId: 1 })
  ]

  const arranged = Model.arrange(rows, "")

  assert.deepEqual(names(arranged), ["Obsidian", "foot", "Chromium", "Discord"])
})

test("with no query windows of the same size and place fall back to app name", () => {
  const rows = [row("foot"), row("Chromium"), row("Obsidian"), row("Discord")]

  const arranged = Model.arrange(rows, "")

  assert.deepEqual(names(arranged), ["Chromium", "Discord", "foot", "Obsidian"])
})

test("a query keeps only apps whose name or window title contains it", () => {
  const rows = [row("Chromium", "Gmail - Inbox"), row("foot", "~/Work"), row("Obsidian", "Notes")]

  const arranged = Model.arrange(rows, "MAIL")

  assert.deepEqual(names(arranged), ["Chromium"])
})

test("matching ignores diacritics in both the query and the names", () => {
  const rows = [row("Prohlížeč"), row("Soubory", "Čas a datum"), row("foot")]

  const arranged = Model.arrange(rows, "prohliz")
  const byTitle = Model.arrange(rows, "čas")

  assert.deepEqual(names(arranged), ["Prohlížeč"])
  assert.deepEqual(names(byTitle), ["Soubory"])
})

test("a query ranks exact names, then prefixes, word starts, inner matches and title matches", () => {
  const rows = [
    row("Chromium", "Code review"),
    row("Decoder"),
    row("Visual Studio Code"),
    row("Codex"),
    row("Code")
  ]

  const arranged = Model.arrange(rows, "code")

  assert.deepEqual(names(arranged), ["Code", "Codex", "Visual Studio Code", "Decoder", "Chromium"])
})

test("the miniature places every window of the workspace relative to its monitor and marks the chosen one", () => {
  const monitor = { x: 1920, y: 0, width: 3840, height: 2160, scale: 2 }
  const windows = [
    { address: "0xa", at: [1920, 0], size: [960, 1080] },
    { address: "0xb", at: [2880, 0], size: [960, 1080] }
  ]

  const tiles = Model.miniature(windows, monitor, "0xb")

  assert.deepEqual(tiles, [
    { x: 0, y: 0, width: 0.5, height: 1, chosen: false },
    { x: 0.5, y: 0, width: 0.5, height: 1, chosen: true }
  ])
})

test("a rotated monitor's miniature uses its portrait shape", () => {
  const monitor = { x: 0, y: 0, width: 2560, height: 1440, scale: 1, transform: 1 }
  const windows = [{ address: "0xa", at: [0, 1280], size: [1440, 1280] }]

  const tiles = Model.miniature(windows, monitor, "0xa")

  assert.deepEqual(tiles, [{ x: 0, y: 0.5, width: 1, height: 0.5, chosen: true }])
})

test("a window without a desktop entry is named after its class", () => {
  const fallbacks = ["com.mitchellh.ghostty", "org.omarchy.agent", "firefox", ""].map(appClass => Model.fallbackName(appClass, "Untitled"))

  assert.deepEqual(fallbacks, ["Ghostty", "Agent", "Firefox", "Untitled"])
})

const placed = (title, area, top, left, workspaceId = 1) => row("foot", title, { area, top, left, workspaceId })
const titles = rows => rows.map(r => r.title)

test("windows of the same app are listed largest first", () => {
  const rows = [placed("a-small", 0.25, 0, 0.5), placed("c-full", 1, 0, 0, 3), placed("b-half", 0.5, 0, 0, 2)]

  const arranged = Model.arrange(rows, "")

  assert.deepEqual(titles(arranged), ["c-full", "b-half", "a-small"])
})

test("equally large windows of the same app follow reading order, then workspace number", () => {
  const rows = [
    placed("bottom-right", 0.125, 0.5, 0.75),
    placed("other-workspace", 0.125, 0.5, 0.5, 2),
    placed("bottom-left", 0.125, 0.5, 0.5),
    placed("top-right", 0.125, 0, 0.5)
  ]

  const arranged = Model.arrange(rows, "")

  assert.deepEqual(titles(arranged), ["top-right", "bottom-left", "other-workspace", "bottom-right"])
})

test("a pixel of difference from gaps or odd widths does not count as a different size or row", () => {
  const rows = [placed("right", 0.5004, 0, 0.5), placed("left", 0.5, 0.0004, 0)]

  const arranged = Model.arrange(rows, "")

  assert.deepEqual(titles(arranged), ["left", "right"])
})

const SUPER = 64
const ALT = 8
const bind = (modmask, key, description = "") => ({ modmask, key, description })

test("the suggested shortcut is SUPER + N when it is free", () => {
  const binds = [bind(SUPER | 4, "N", "Network"), bind(SUPER | 1, "N", "Editor")]

  const shortcut = Model.freeShortcut(binds)

  assert.equal(shortcut.label, "SUPER + N")
})

test("when SUPER + N is taken the suggestion falls back to SUPER + ALT + N, then to none", () => {
  const taken = [bind(SUPER, "n", "Notes")]
  const allTaken = [bind(SUPER, "N", "Notes"), bind(SUPER | ALT, "N", "New window")]

  const fallback = Model.freeShortcut(taken)
  const none = Model.freeShortcut(allTaken)

  assert.equal(fallback.label, "SUPER + ALT + N")
  assert.equal(none, null)
})

test("Lightnav counts as set up once any shortcut is described as Lightnav", () => {
  const before = [bind(SUPER, "SPACE", "Omarchy menu")]
  const after = before.concat([bind(SUPER | ALT, "J", "Lightnav")])

  assert.equal(Model.isSetUp(before), false)
  assert.equal(Model.isSetUp(after), true)
})

test("the shortcut line binds the chosen keys to Lightnav", () => {
  const line = Model.shortcutLine("SUPER + N")

  assert.equal(line, 'o.bind("SUPER + N", "Lightnav", { panel = "smetak13.lightnav" })')
})

test("the manual command appends the shortcut line to the Hyprland bindings", () => {
  const command = Model.manualCommand("SUPER + N")

  assert.equal(command, `echo 'o.bind("SUPER + N", "Lightnav", { panel = "smetak13.lightnav" })' >> ~/.config/hypr/bindings.lua && hyprctl reload`)
})

test("the block Lightnav adds is marked so it can be found and removed", () => {
  const block = Model.shortcutBlock("SUPER + N")

  assert.equal(block, [
    "",
    "-- >>> Lightnav shortcut, added by Lightnav",
    'o.bind("SUPER + N", "Lightnav", { panel = "smetak13.lightnav" })',
    "-- <<< Lightnav shortcut",
    ""
  ].join("\n"))
})
