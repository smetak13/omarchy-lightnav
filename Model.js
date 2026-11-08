var WORKSPACE_SLOTS = 10

function slotLabel(workspaceId) {
  if (workspaceId < 1) return "S"
  var slot = (workspaceId - 1) % WORKSPACE_SLOTS + 1
  return slot === WORKSPACE_SLOTS ? "0" : String(slot)
}

function isInternalMonitor(name) {
  return /^(eDP|LVDS|DSI)/.test(String(name || ""))
}

var SAME_PLACE_TOLERANCE = 0.01

function beyondTolerance(difference) {
  return Math.abs(difference) > SAME_PLACE_TOLERANCE ? difference : 0
}

function compareNames(a, b) {
  return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
}

function comparePlaces(a, b) {
  return beyondTolerance((b.area || 0) - (a.area || 0))
    || beyondTolerance((a.top || 0) - (b.top || 0))
    || beyondTolerance((a.left || 0) - (b.left || 0))
    || (a.workspaceId || 0) - (b.workspaceId || 0)
}

function byName(a, b) {
  return compareNames(a, b) || comparePlaces(a, b)
}

function bySize(a, b) {
  return comparePlaces(a, b) || compareNames(a, b)
}

function searchable(text) {
  return String(text || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
}

var NO_MATCH = -1

function matchRank(row, needle) {
  var name = searchable(row.name)
  if (name === needle) return 0
  if (name.indexOf(needle) === 0) return 1
  if (name.indexOf(" " + needle) >= 0) return 2
  if (name.indexOf(needle) >= 0) return 3
  if (searchable(row.title).indexOf(needle) >= 0) return 4
  return NO_MATCH
}

function arrange(rows, query) {
  var needle = searchable(query).trim()
  if (!needle) return rows.slice().sort(bySize)

  return rows
    .map(function(row) { return { row: row, rank: matchRank(row, needle) } })
    .filter(function(ranked) { return ranked.rank !== NO_MATCH })
    .sort(function(a, b) { return a.rank - b.rank || byName(a.row, b.row) })
    .map(function(ranked) { return ranked.row })
}

function logicalSize(monitor) {
  var scale = monitor.scale || 1
  var rotated = monitor.transform % 2 === 1
  var width = (rotated ? monitor.height : monitor.width) / scale
  var height = (rotated ? monitor.width : monitor.height) / scale
  return { width: width, height: height }
}

function clamp01(value) {
  return Math.min(1, Math.max(0, value))
}

function miniature(windows, monitor, chosenAddress) {
  var size = logicalSize(monitor)
  return windows.map(function(window) {
    var left = clamp01((window.at[0] - monitor.x) / size.width)
    var top = clamp01((window.at[1] - monitor.y) / size.height)
    var right = clamp01((window.at[0] + window.size[0] - monitor.x) / size.width)
    var bottom = clamp01((window.at[1] + window.size[1] - monitor.y) / size.height)
    return { x: left, y: top, width: right - left, height: bottom - top, chosen: window.address === chosenAddress }
  })
}

function fallbackName(appClass, title) {
  var word = String(appClass || "").split(".").pop()
  if (!word) return String(title || "")
  return word.charAt(0).toUpperCase() + word.slice(1)
}

var SUPER_MASK = 64
var ALT_MASK = 8
var SHORTCUT_CANDIDATES = [
  { label: "SUPER + N", modmask: SUPER_MASK, key: "N" },
  { label: "SUPER + ALT + N", modmask: SUPER_MASK | ALT_MASK, key: "N" }
]

var SHORTCUT_DESCRIPTION = "Lightnav"

var PLUGIN_ID = "smetak13.lightnav"

function shortcutLine(label) {
  return 'o.bind("' + label + '", "' + SHORTCUT_DESCRIPTION + '", { panel = "' + PLUGIN_ID + '" })'
}

function manualCommand(label) {
  return "echo '" + shortcutLine(label) + "' >> ~/.config/hypr/bindings.lua && hyprctl reload"
}

function shortcutBlock(label) {
  return ["", "-- >>> Lightnav shortcut, added by Lightnav", shortcutLine(label), "-- <<< Lightnav shortcut", ""].join("\n")
}

function isSetUp(binds) {
  return binds.some(function(bind) { return bind.description === SHORTCUT_DESCRIPTION })
}

function freeShortcut(binds) {
  return SHORTCUT_CANDIDATES.filter(function(candidate) {
    return !binds.some(function(bind) {
      return bind.modmask === candidate.modmask && String(bind.key).toUpperCase() === candidate.key
    })
  })[0] || null
}

if (typeof module !== "undefined") {
  module.exports = {
    slotLabel: slotLabel,
    isInternalMonitor: isInternalMonitor,
    arrange: arrange,
    miniature: miniature,
    logicalSize: logicalSize,
    fallbackName: fallbackName,
    freeShortcut: freeShortcut,
    isSetUp: isSetUp,
    shortcutLine: shortcutLine,
    manualCommand: manualCommand,
    shortcutBlock: shortcutBlock
  }
}
