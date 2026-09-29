// Pure functions behind the sudo escalation dialog: parse a record the root
// hook wrote, work out what sudo is about to run, and lay it out as lines
// of plain text. No Qt here, so `node SudoModel.test.js` covers it.

var SHELLS = { sh: 1, bash: 1, zsh: 1, dash: 1, fish: 1, ksh: 1, mksh: 1, ash: 1 }
var SAFE_WORD = /^[A-Za-z0-9_@%+=:,.\/-]+$/

// Control characters, line separators and bidi overrides drawn as their
// code point, so nothing in an argument can move the cursor or reorder the
// text the dialog shows. Everything is rendered PlainText on top of this.
function visible(s) {
  return String(s).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, function(c) {
    var code = c.charCodeAt(0)
    if (code < 0x20) return String.fromCharCode(0x2400 + code)
    if (code === 0x7f) return "\u2421"
    return "\u2039U+" + ("0000" + code.toString(16).toUpperCase()).slice(-4) + "\u203a"
  })
}

function hasControl(s) {
  return /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u200e\u200f\u202a-\u202e\u2066-\u2069]/.test(String(s))
}

// Quote one word the way shlex.join does, so a payload reads as it was typed.
function shellQuote(a) {
  a = String(a)
  if (a.length && SAFE_WORD.test(a)) return a
  return "'" + a.replace(/'/g, "'\\''") + "'"
}

function joinArgv(list) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(shellQuote(list[i]))
  return out.join(" ")
}

function basename(p) {
  var s = String(p || "")
  var i = s.lastIndexOf("/")
  return i === -1 ? s : s.slice(i + 1)
}

function parseRecord(text) {
  var r
  try { r = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!r || r.v !== 1) return null
  if (typeof r.pid !== "number" || !Array.isArray(r.argv)) return null
  if (!r.command || typeof r.command !== "object") return null
  if (!Array.isArray(r.command.args)) r.command.args = []
  if (!Array.isArray(r.from)) r.from = []
  return r
}

// `sh -c payload`: the payload is the word after -c, or after a cluster
// like -ec, among the options before the first operand.
function shellPayload(args) {
  for (var i = 1; i < args.length; i++) {
    var a = String(args[i])
    if (a === "--") return null
    if (a.charAt(0) !== "-" || a === "-") return null
    if (a.charAt(1) === "-") continue           // --posix and friends
    if (a.indexOf("c") !== -1) {
      if (i + 1 < args.length) return { payload: String(args[i + 1]), rest: args.slice(i + 2) }
      return null
    }
  }
  return null
}

// Break a shell payload into one line per command, splitting at the list
// operators (&&, ||, ;, |, |&, &) and newlines that sit outside quotes and
// outside (), $() and ${}. The operator stays at the end of its line.
function splitPayload(payload) {
  var s = String(payload)
  var lines = []
  var cur = ""
  var q = ""          // active quote: ', " or ""
  var depth = 0       // ( and ${ nesting
  var i = 0
  function flush() {
    var t = cur.replace(/^\s+|\s+$/g, "")
    if (t.length) lines.push(t)
    cur = ""
  }
  while (i < s.length) {
    var c = s.charAt(i)
    var n = s.charAt(i + 1)
    if (q === "'") {
      cur += c; if (c === "'") q = ""; i++; continue
    }
    if (q === '"') {
      if (c === "\\" && i + 1 < s.length) { cur += c + n; i += 2; continue }
      cur += c; if (c === '"') q = ""; i++; continue
    }
    if (c === "\\" && i + 1 < s.length) {
      if (n === "\n") { i += 2; continue }       // line continuation
      cur += c + n; i += 2; continue
    }
    if (c === "'" || c === '"') { q = c; cur += c; i++; continue }
    if (c === "$" && (n === "(" || n === "{")) { depth++; cur += c + n; i += 2; continue }
    if (c === "(") { depth++; cur += c; i++; continue }
    if (c === ")" || c === "}") { if (depth > 0) depth--; cur += c; i++; continue }
    if (depth === 0) {
      if (c === "\n") { flush(); i++; continue }
      if ((c === "&" && n === "&") || (c === "|" && n === "|")) { cur += c + n; flush(); i += 2; continue }
      if (c === "|" && n === "&") { cur += c + n; flush(); i += 2; continue }
      if (c === ";" || c === "|" || c === "&") { cur += c; flush(); i++; continue }
    }
    cur += c; i++
  }
  flush()
  return lines
}

// Plumbing that sits between the requester and sudo: not who asked.
var PLUMBING = { sh: 1, bash: 1, zsh: 1, dash: 1, fish: 1, ksh: 1, herdr: 1, tmux: 1, screen: 1, "tmux: server": 1 }
var TERMINALS = { kitty: 1, foot: 1, alacritty: 1, ghostty: 1, wezterm: 1, "wezterm-gui": 1, gnome: 1, konsole: 1, xterm: 1 }

// Who asked: the nearest ancestor of sudo that is not a shell or a
// multiplexer. "claude" for an agent, "the terminal" for something typed.
function origin(from) {
  for (var i = from.length - 1; i >= 0; i--) {
    var comm = String(from[i])
    if (PLUMBING[comm]) continue
    if (TERMINALS[comm]) return "the terminal"
    return visible(comm)
  }
  return from.length ? "the terminal" : "an unknown process"
}

// Everything the dialog draws, as plain strings. `lines` is the command
// block: the resolved executable first, then a sh -c payload one command
// per line, indented.
function describe(record) {
  var cmd = record.command || {}
  var kind = String(cmd.kind || "command")
  var args = cmd.args || []
  var exe = String(cmd.exe || "")
  var warnings = []
  var lines = []
  var headline = ""

  if (!record.tty) warnings.push("no tty: not typed at a terminal")
  var control = false
  for (var i = 0; i < record.argv.length; i++) if (hasControl(record.argv[i])) control = true
  if (control) warnings.push("control characters in the command are shown as symbols")

  if (kind === "command") {
    var word = args.length ? String(args[0]) : ""
    var tail = args.slice(1)
    if (!exe) {
      warnings.push("'" + visible(word) + "' is not on sudo's secure_path")
      exe = word
    }
    headline = visible(joinArgv([basename(exe)].concat(tail)))
    var payload = SHELLS[basename(exe)] ? shellPayload(args) : null
    if (payload) {
      var opts = args.slice(1, args.indexOf(payload.payload))
      lines.push(visible(joinArgv([exe].concat(opts))) + "  # then, inside that shell:")
      var parts = splitPayload(payload.payload)
      for (var j = 0; j < parts.length; j++) lines.push("    " + visible(parts[j]))
      if (payload.rest.length) lines.push("  with $0 $1..: " + visible(joinArgv(payload.rest)))
    } else {
      lines.push(visible(joinArgv([exe].concat(tail))))
    }
  } else if (kind === "shell") {
    headline = "interactive shell"
    lines.push(visible(exe || "shell") + "  # every command typed into it runs as " + visible(cmd.target || "root"))
  } else if (kind === "edit") {
    headline = visible(joinArgv(["sudoedit"].concat(args)))
    lines.push(headline)
  } else if (kind === "list") {
    headline = "sudo -l"
    lines.push("lists the sudo rules, runs nothing")
  } else if (kind === "validate") {
    headline = "sudo -v"
    lines.push("refreshes credentials only; with timestamp_timeout=0 this gates nothing")
  } else {
    headline = visible(joinArgv(record.argv))
    lines.push(headline)
  }

  return {
    kind: kind,
    origin: origin(record.from),
    target: visible(cmd.target || "root"),
    headline: headline,
    lines: lines,
    from: record.from.map(visible).join(" \u2192 ") || "?",
    tty: record.tty ? visible(record.tty) : "no tty",
    cwd: visible(record.cwd || "?"),
    typed: visible(joinArgv(record.argv)),
    warnings: warnings
  }
}

function clock(epoch) {
  var d = new Date(epoch * 1000)
  function two(n) { return (n < 10 ? "0" : "") + n }
  return two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds())
}

if (typeof module !== "undefined") {
  module.exports = {
    visible: visible, hasControl: hasControl, shellQuote: shellQuote, joinArgv: joinArgv,
    basename: basename, parseRecord: parseRecord, shellPayload: shellPayload,
    splitPayload: splitPayload, describe: describe, clock: clock, origin: origin
  }
}
