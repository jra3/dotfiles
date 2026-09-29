// node SudoModel.test.js
const assert = require("assert")
const M = require("./SudoModel.js")

function record(argv, command, extra) {
  return Object.assign({
    v: 1, time: 1790712581, pid: 4242, user: "john", tty: "/dev/pts/3",
    cwd: "/home/john", from: ["kitty", "zsh", "claude"], argv: argv,
    command: Object.assign({ kind: "command", target: "root", exe: "", args: [], secure_path: "/usr/bin" }, command)
  }, extra || {})
}

// Quoting round-trips like shlex.join.
assert.strictEqual(M.joinArgv(["ls", "-la", "a b", "it's"]), "ls -la 'a b' 'it'\\''s'")

// Control characters and bidi overrides are drawn, never interpreted.
assert.strictEqual(M.visible("a\u001b[2Jb"), "a\u241b[2Jb")
assert.strictEqual(M.visible("x\u202ey"), "x\u2039U+202E\u203ay")
assert.strictEqual(M.visible("nl\n"), "nl\u240a")

// A payload splits at list operators outside quotes and subshells.
assert.deepStrictEqual(
  M.splitPayload("apt update && rm -rf /x; echo \"a;b\" | tee 'c|d' $(e; f) (g; h)"),
  ["apt update &&", "rm -rf /x;", "echo \"a;b\" |", "tee 'c|d' $(e; f) (g; h)"])
assert.deepStrictEqual(M.splitPayload("one \\\n  two\nthree"), ["one   two", "three"])

// sh -c is found through option clusters and stops at operands.
assert.deepStrictEqual(M.shellPayload(["bash", "-lc", "id", "extra"]), { payload: "id", rest: ["extra"] })
assert.strictEqual(M.shellPayload(["bash", "script.sh", "-c", "id"]), null)
assert.strictEqual(M.shellPayload(["sh", "--", "-c"]), null)

// A plain command shows the resolved executable, not argv[0].
let d = M.describe(record(["sudo", "ls", "-la"], { exe: "/usr/local/bin/ls", args: ["ls", "-la"] }))
assert.strictEqual(d.headline, "ls -la")
assert.deepStrictEqual(d.lines, ["/usr/local/bin/ls -la"])
assert.deepStrictEqual(d.warnings, [])

// A shell payload is laid out one command per line.
d = M.describe(record(["sudo", "sh", "-c", "a && b"], { exe: "/usr/bin/sh", args: ["sh", "-c", "a && b"] }))
assert.deepStrictEqual(d.lines, ["/usr/bin/sh -c  # then, inside that shell:", "    a &&", "    b"])

// Missing executable and missing tty are warnings, not silence.
d = M.describe(record(["sudo", "nope"], { exe: "", args: ["nope"] }, { tty: "" }))
assert.strictEqual(d.tty, "no tty")
assert.ok(d.warnings.some(w => w.indexOf("not on sudo's secure_path") !== -1))
assert.ok(d.warnings.some(w => w.indexOf("no tty") !== -1))

// The other sudo modes.
assert.strictEqual(M.describe(record(["sudo", "-i"], { kind: "shell", exe: "/usr/bin/bash" })).headline, "interactive shell")

// The title names who asked, skipping shells and multiplexers.
assert.strictEqual(M.origin(["zsh", "herdr", "herdr", "zsh", "claude", "zsh"]), "claude")
assert.strictEqual(M.origin(["kitty", "zsh"]), "the terminal")
assert.strictEqual(M.origin(["zsh"]), "the terminal")
assert.strictEqual(M.origin([]), "an unknown process")
assert.strictEqual(M.origin(["kitty", "zsh", "python3", "sh"]), "python3")
assert.strictEqual(M.describe(record(["sudo", "-e", "/etc/x"], { kind: "edit", exe: "sudoedit", args: ["/etc/x"] })).headline, "sudoedit /etc/x")
assert.strictEqual(M.describe(record(["sudo", "-v"], { kind: "validate" })).headline, "sudo -v")

// Records that are not ours are rejected.
assert.strictEqual(M.parseRecord("{}"), null)
assert.strictEqual(M.parseRecord("not json"), null)
assert.ok(M.parseRecord(JSON.stringify(record(["sudo", "true"], { exe: "/usr/bin/true", args: ["true"] }))))

console.log("ok")
