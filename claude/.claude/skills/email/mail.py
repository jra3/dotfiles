#!/usr/bin/env python3
"""Compact Gmail-over-IMAP front end to himalaya v2 for agents.

Every message is named by its UID in the account's All Mail mailbox, so one id
works across labels. Searches use Gmail's own syntax via X-GM-RAW. Reads use
BODY.PEEK and never mark mail read. Sending works only on an existing draft.
"""
import argparse
import base64
import email
import email.policy
import email.utils
import html.parser
import json
import os
import re
import subprocess
import sys
import time
import tomllib


class Fail(Exception):
    pass


# --- himalaya plumbing ------------------------------------------------------

def hm(*args, input=None, account=None):
    cmd = ["himalaya"] + (["-a", account] if account else []) + list(args)
    p = subprocess.run(cmd, input=input, capture_output=True)
    if p.returncode:
        raise Fail(p.stderr.decode(errors="replace").strip() or f"{cmd[1:]} failed")
    return p.stdout


class Account:
    def __init__(self, name):
        if not name:
            accts = json.loads(hm("account", "list", "--json"))["accounts"]
            name = next((a["name"] for a in accts if a["default"]), None)
            if not name:
                raise Fail("no default account; pass -a NAME")
        path = os.environ.get("HIMALAYA_CONFIG") or os.path.expanduser("~/.config/himalaya/config.toml")
        with open(path.split(":")[0], "rb") as f:
            cfg = tomllib.load(f)["accounts"].get(name)
        if cfg is None:
            raise Fail(f"no account named {name!r} in {path}")
        alias = cfg.get("mailbox", {}).get("alias", {})
        self.name = name
        self.me = cfg.get("email", "").lower()
        self.all_mail = alias.get("archive", "[Gmail]/All Mail")
        self.drafts = alias.get("drafts", "[Gmail]/Drafts")
        self.sent = alias.get("sent", "[Gmail]/Sent Mail")

    def hm(self, *args, input=None):
        return hm(*args, input=input, account=self.name)

    def raw(self, *lines):
        tagged = "".join(f"a{i} {line}\r\n" for i, line in enumerate(lines))
        out = self.hm("imap", "raw", input=tagged.encode()).decode(errors="replace")
        for m in re.finditer(r"^a\d+ (NO|BAD) (.*)$", out, re.M):
            raise Fail(f"IMAP {m[1]}: {m[2]}")
        return out

    def uid_search(self, mailbox, criteria):
        out = self.raw(f"EXAMINE {q(mailbox)}", f"UID SEARCH {criteria}")
        return [int(n) for line in re.findall(r"^\* SEARCH(.*)$", out, re.M) for n in line.split()]

    def gsearch(self, query):
        return self.uid_search(self.all_mail, f"X-GM-RAW {q(query)}")

    def meta(self, uids):
        """uid -> (thread id, labels) from Gmail's IMAP extensions."""
        if not uids:
            return {}
        out = self.raw(f"EXAMINE {q(self.all_mail)}",
                       f"UID FETCH {seq(uids)} (X-GM-THRID X-GM-LABELS)")
        res = {}
        for line in re.findall(r"^\* \d+ FETCH \((.*)\)\s*$", out, re.M):
            uid = re.search(r"\bUID (\d+)", line)
            thr = re.search(r"X-GM-THRID (\d+)", line)
            labels = re.search(r"X-GM-LABELS \((.*?)\)(?: [A-Z]|$)", line)
            if uid and thr:
                names = re.findall(r'"((?:[^"\\]|\\.)*)"|(\S+)', labels[1]) if labels else []
                res[int(uid[1])] = (thr[1], [(a or b).replace("\\\\", "\\") for a, b in names])
        return res

    def fetch(self, uids, body=False):
        if not uids:
            return []
        args = ["imap", "fetch", "-m", self.all_mail, seq(uids), "--envelope", "--flags", "--json"]
        if body:
            args.append("--body")
        msgs = json.loads(self.hm(*args))["messages"]
        for m in msgs:
            env = m["envelope"]
            env["subject"] = unmangle(env["subject"])
            for k in ("from", "to", "cc", "reply_to"):
                env[k] = [unmangle(x) for x in env[k] or []]
            m["when"] = parse_date(env["date"])
            if body:
                m["parsed"] = email.message_from_bytes(base64.b64decode(m["body"]), policy=email.policy.default)
        return msgs

    def thread(self, uid):
        meta = self.meta([uid])
        if uid not in meta:
            raise Fail(f"no message {uid} in {self.all_mail}")
        return self.uid_search(self.all_mail, f"X-GM-THRID {meta[uid][0]}")

    def find_by_msgid(self, msgid, tries=10):
        for _ in range(tries):
            uids = self.gsearch(f"rfc822msgid:{msgid.strip('<>')}")
            if uids:
                return uids[-1]
            time.sleep(1)
        return None

    def delete_draft(self, msgid):
        uids = self.uid_search(self.drafts, f"HEADER Message-ID {q(msgid)}")
        if uids:
            self.raw(f"SELECT {q(self.drafts)}", f"UID STORE {seq(uids)} +FLAGS (\\Deleted)",
                     f"UID EXPUNGE {seq(uids)}")


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def seq(uids):
    return ",".join(str(u) for u in uids)


def unmangle(s):
    """Undo UTF-8 that was decoded as cp1252 ("â€”" -> "—"); leave anything else."""
    if not s or s.isascii():
        return s
    try:
        return s.encode("cp1252").decode("utf-8")
    except UnicodeError:
        return s


def parse_date(s):
    try:
        return email.utils.parsedate_to_datetime(s).astimezone()
    except (TypeError, ValueError):
        return None


# --- rendering --------------------------------------------------------------

def addrs(lst):
    # himalaya gives one unquoted "Name <addr>" per entry; email.utils would
    # split names holding commas and drop ones like "coderabbitai[bot]".
    out = []
    for s in lst or []:
        m = re.fullmatch(r'\s*"?(.*?)"?\s*<([^<>]+)>\s*', s)
        out.append((m[1], m[2]) if m else ("", s.strip()))
    return out


def fmt_addr(lst, n=1):
    out = [f"{name} <{a}>" if name else a for name, a in addrs(lst)]
    return ", ".join(out[:n]) + (f" +{len(out) - n}" if len(out) > n else "")


def marks(m, labels=()):
    f = set(m["flags"]) | set(labels)
    return ("*" if "\\Seen" not in f else " ") + ("A" if "\\Answered" in f else " ") + \
           ("D" if "\\Draft" in f else " ")


def line(m, labels=()):
    when = m["when"].strftime("%m-%d %H:%M") if m["when"] else "??-?? ??:??"
    env = m["envelope"]
    who = fmt_addr(env["to"]) if labels and "\\Draft" in labels else fmt_addr(env["from"])
    return f"{m['uid']:>8}  {when}  {marks(m, labels)}  {who}  {env['subject'] or '(no subject)'}"


class _Text(html.parser.HTMLParser):
    BLOCK = {"p", "div", "br", "tr", "li", "h1", "h2", "h3", "h4", "table", "blockquote"}

    def __init__(self):
        super().__init__()
        self.out, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script", "head"):
            self.skip += 1
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in ("style", "script", "head"):
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def body_text(msg):
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is None:
        return ""
    text = part.get_content()
    if not text.strip():  # some senders ship a blank plain part beside the real HTML
        part = msg.get_body(preferencelist=("html",))
        text = part.get_content() if part else ""
    if part is not None and part.get_content_subtype() == "html":
        p = _Text()
        p.feed(text)
        text = "".join(p.out)
    return re.sub(r"[ \t ]+\n", "\n", text.replace("\r\n", "\n"))


CUT = [
    re.compile(r"^On .{0,300}wrote:\s*$", re.S),          # Gmail/Apple quote header
    re.compile(r"^-{2,}\s*Original Message\s*-{2,}", re.I),
    re.compile(r"^-{2,}\s*Forwarded message\s*-{2,}", re.I),
    re.compile(r"^_{10,}\s*$"),                             # Outlook separator
    re.compile(r"^From: .+\n(Sent|Date): ", re.I),          # Outlook header block
    re.compile(r"^-- ?$"),                                  # signature delimiter
    re.compile(r"^Sent from my \w+", re.I),
]


def trim(text):
    lines = re.sub(r"<!--.*?-->", "", text, flags=re.S).split("\n")
    kept = []
    for i, ln in enumerate(lines):
        window = "\n".join(lines[i:i + 3])
        if any(rx.match(ln) or rx.match(window) for rx in CUT):
            break
        if ln.lstrip().startswith(">"):
            continue
        kept.append(ln.rstrip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(kept)).strip()


def capped(text, cap):
    return text if not cap or len(text) <= cap else text[:cap].rstrip() + f"\n[... {len(text) - cap} more chars; --full or --cap N]"


def show(m, labels, full, cap, verbose):
    env = m["envelope"]
    print(f"--- {line(m, labels)}")
    if verbose:
        print(f"From: {fmt_addr(env['from'], 9)}\nTo: {fmt_addr(env['to'], 99)}")
        if env["cc"]:
            print(f"Cc: {fmt_addr(env['cc'], 99)}")
        print(f"Labels: {' '.join(labels)}")
    text = body_text(m["parsed"])
    print(capped(text.strip() if full else trim(text), None if full else cap))
    atts = [p.get_filename() for p in m["parsed"].iter_attachments() if p.get_filename()]
    if atts:
        print(f"[attachments: {', '.join(atts)}]")


# --- commands ---------------------------------------------------------------

def cmd_search(acct, a):
    query = " ".join(a.query) or "in:inbox"
    uids = acct.gsearch(query)
    page = uids[-a.limit:]
    meta = acct.meta(page)
    for m in sorted(acct.fetch(page), key=lambda m: m["uid"], reverse=True):
        print(line(m, meta.get(m["uid"], ("", []))[1]))
    print(f"({len(page)} of {len(uids)} for: {query})")


def cmd_drafts(acct, a):
    a.query = ["in:drafts"]
    cmd_search(acct, a)


def cmd_read(acct, a):
    msgs = acct.fetch([a.uid], body=True)
    if not msgs:
        raise Fail(f"no message {a.uid} in {acct.all_mail}")
    show(msgs[0], acct.meta([a.uid]).get(a.uid, ("", []))[1], a.full, a.cap, True)


def cmd_thread(acct, a):
    uids = acct.thread(a.uid)
    meta = acct.meta(uids)
    msgs = sorted(acct.fetch(uids, body=True), key=lambda m: m["when"] or 0)
    if a.last and len(msgs) > a.last:
        print(f"[{len(msgs) - a.last} earlier messages omitted]")
        msgs = msgs[-a.last:]
    for m in msgs:
        show(m, meta.get(m["uid"], ("", []))[1], a.full, a.cap, a.verbose)


def save_draft(acct, raw, replace):
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    acct.hm("message", "add", "-m", acct.drafts, "-f", "draft", input=raw)
    if replace:
        old = acct.fetch([replace])
        if old:
            acct.delete_draft(old[0]["envelope"]["message_id"])
    uid = acct.find_by_msgid(msg["Message-ID"])
    print(f"draft {uid if uid else '(saved; uid not indexed yet, see drafts)'}")
    for h in ("To", "Cc", "Subject"):
        if msg[h]:
            print(f"{h}: {msg[h]}")


def recipients(acct, env, reply_all):
    me = acct.me
    src_from = addrs(env["from"])
    from_me = any(a.lower() == me for _, a in src_from)
    to = addrs(env["to"]) if from_me else (addrs(env["reply_to"]) or src_from)
    cc = []
    if reply_all:
        seen = {a.lower() for _, a in to} | {me}
        for name, addr in addrs((env["to"] or []) + (env["cc"] or [])):
            if addr.lower() not in seen:
                seen.add(addr.lower())
                cc.append((name, addr))
    return [email.utils.formataddr(x) for x in to], [email.utils.formataddr(x) for x in cc]


def cmd_draft(acct, a):
    body = sys.stdin.read() if a.file == "-" else open(a.file).read()
    if a.reply:
        uids = acct.thread(a.reply)
        meta = acct.meta(uids)
        msgs = sorted((m for m in acct.fetch(uids) if "\\Draft" not in meta.get(m["uid"], ("", []))[1]),
                      key=lambda m: m["when"] or 0)
        latest = msgs[-1]
        if latest["uid"] != a.reply and not a.force:
            raise Fail(f"{a.reply} is not the latest message in its thread; latest is:\n{line(latest)}\n"
                       f"reply to {latest['uid']}, or pass --force on the user's word")
        src = next(m for m in msgs if m["uid"] == a.reply)
        to, cc = recipients(acct, src["envelope"], not a.no_cc)
        to, cc = a.to or to, (a.cc if a.cc is not None else cc)
        args = ["message", "reply", "-m", acct.all_mail, str(a.reply), "--body", body]
    else:
        if not (a.to and a.subject):
            raise Fail("a new message needs --to and --subject (or --reply UID)")
        to, cc = a.to, a.cc or []
        args = ["message", "compose", "--body", body]
    for t in to:
        args += ["--to", t]
    for c in cc:
        args += ["--cc", c]
    if a.subject:
        args += ["--subject", a.subject]
    raw = acct.hm(*args)
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    # `reply` adds its own derived recipient; pin To/Cc to exactly what we chose.
    for h, vals in (("To", to), ("Cc", cc)):
        del msg[h]
        if vals:
            msg[h] = ", ".join(vals)
    raw = msg.as_bytes()
    if a.dry_run:
        for h in ("From", "To", "Cc", "Subject", "In-Reply-To"):
            if msg[h]:
                print(f"{h}: {msg[h]}")
        print(f"\n{trim(body_text(msg))}\n(dry run: nothing saved)")
        return
    save_draft(acct, raw, a.replace)


def cmd_send(acct, a):
    meta = acct.meta([a.uid]).get(a.uid)
    if not meta or "\\Draft" not in meta[1]:
        raise Fail(f"{a.uid} is not a draft; only drafts can be sent")
    m = acct.fetch([a.uid], body=True)[0]
    raw, msgid = base64.b64decode(m["body"]), m["envelope"]["message_id"]
    # Gmail merges messages sharing a Message-ID, so the Sent copy would merge
    # into the draft and be destroyed with it. Remove the draft before sending.
    acct.delete_draft(msgid)
    try:
        acct.hm("message", "send", input=raw)
    except Fail:
        acct.hm("message", "add", "-m", acct.drafts, "-f", "draft", input=raw)
        raise
    sent = None
    for _ in range(10):
        sent = acct.uid_search(acct.sent, f"HEADER Message-ID {q(msgid)}")
        if sent:
            break
        time.sleep(1)
    print(f"sent to {fmt_addr(m['envelope']['to'], 99)}: {m['envelope']['subject']}")
    if not sent:
        print(f"warning: no copy in {acct.sent} yet; check before resending")


def main():
    p = argparse.ArgumentParser(prog="mail.py", description=__doc__.split("\n")[0])
    p.add_argument("-a", "--account", help="himalaya account (default: the config's default)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("search", help="list messages matching a Gmail query (default: in:inbox)")
    s.add_argument("query", nargs="*")
    s.add_argument("-n", "--limit", type=int, default=20)
    s.set_defaults(fn=cmd_search)

    s = sub.add_parser("drafts", help="list drafts")
    s.add_argument("-n", "--limit", type=int, default=20)
    s.set_defaults(fn=cmd_drafts)

    s = sub.add_parser("read", help="one message, quotes and signature trimmed")
    s.add_argument("uid", type=int)
    s.add_argument("--full", action="store_true")
    s.add_argument("--cap", type=int, default=4000)
    s.set_defaults(fn=cmd_read)

    s = sub.add_parser("thread", help="a message's whole conversation, oldest first")
    s.add_argument("uid", type=int)
    s.add_argument("--last", type=int)
    s.add_argument("--cap", type=int, default=1000)
    s.add_argument("--full", action="store_true")
    s.add_argument("-v", "--verbose", action="store_true", help="full From/To/Cc/labels per message")
    s.set_defaults(fn=cmd_thread)

    s = sub.add_parser("draft", help="save a reply or new message to Drafts")
    s.add_argument("file", help="plain-text body file, or - for stdin")
    s.add_argument("--reply", type=int, metavar="UID")
    s.add_argument("--no-cc", action="store_true", help="reply to the sender only")
    s.add_argument("--force", action="store_true", help="reply to a message that is not the thread's latest")
    s.add_argument("--to", action="append")
    s.add_argument("--cc", action="append")
    s.add_argument("--subject")
    s.add_argument("--replace", type=int, metavar="UID", help="delete this older draft after saving")
    s.add_argument("--dry-run", action="store_true")
    s.set_defaults(fn=cmd_draft)

    s = sub.add_parser("send", help="send an existing draft")
    s.add_argument("uid", type=int)
    s.set_defaults(fn=cmd_send)

    a = p.parse_args()
    try:
        a.fn(Account(a.account), a)
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
