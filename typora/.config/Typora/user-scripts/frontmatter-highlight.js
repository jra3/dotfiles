// Syntax-highlight YAML front matter in Typora's editor.
//
// Typora renders front matter as one escaped text node in pre.md-meta-block, so
// there is nothing for CSS to select. This finds keys, values and punctuation
// by regex and registers them with the CSS Custom Highlight API, which colors
// text ranges without touching the DOM. That matters: the block is editable and
// Typora rebuilds the saved file from its text, so wrapping keys in <span>s
// would corrupt it. Colors come from the theme via ::highlight(fm-*).
//
// Loaded by init.js. See typora/README.md.

(() => {
    if (!window.CSS || !CSS.highlights || !window.Highlight) return;

    const NAMES = ["key", "punct", "string", "literal", "number", "url", "comment"];
    const hl = Object.fromEntries(NAMES.map((n) => {
        const h = new Highlight();
        CSS.highlights.set(`fm-${n}`, h);
        return [n, h];
    }));

    // "key: value", optionally after "- " (a list of maps). The colon must be
    // followed by space or end of line, so "https://..." is never a key.
    const KEY_LINE = /^(\s*)(-\s+)?([^\s#:-][^:#]*?|"[^"]*"|'[^']*')(\s*)(:)(?=\s|$)(.*)$/;
    const LIST_ITEM = /^(\s*)(-)(\s+)(.*)$/;
    const LITERAL = /^(true|false|yes|no|on|off|null|~)$/i;
    const NUMBER = /^[-+]?(\d[\d_]*(\.\d+)?([eE][-+]?\d+)?|\.inf|\.nan)$/i;
    const DATE = /^\d{4}-\d{2}-\d{2}([T ][\d:.]+(Z|[-+]\d{2}:?\d{2})?)?$/;
    const URL_RE = /^[a-z][a-z0-9+.-]*:\/\/\S+$/i;

    // Concatenate the block's text nodes so a line split across nodes mid-edit
    // still tokenizes, and map string offsets back to (node, offset).
    function textOf(block) {
        const nodes = [];
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
        let text = "";
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
            nodes.push({ node: n, start: text.length });
            text += n.data;
        }
        const locate = (off) => {
            for (let i = nodes.length - 1; i >= 0; i--) {
                if (off >= nodes[i].start) return [nodes[i].node, off - nodes[i].start];
            }
            return [block, 0];
        };
        return { text, locate };
    }

    function scanValue(value, base, add) {
        const lead = value.length - value.trimStart().length;
        let v = value.trim();
        let at = base + lead;
        if (!v) return;

        // Trailing " # comment" (not inside quotes).
        if (!/^["']/.test(v)) {
            const c = v.search(/(^|\s)#/);
            if (c >= 0) {
                const hash = v.indexOf("#", c);
                add("comment", at + hash, at + v.length);
                v = v.slice(0, c).trimEnd();
                if (!v) return;
            }
        }

        if (/^"(?:[^"\\]|\\.)*"$|^'(?:[^']|'')*'$/.test(v)) return add("string", at, at + v.length);
        if (LITERAL.test(v)) return add("literal", at, at + v.length);
        if (DATE.test(v) || NUMBER.test(v)) return add("number", at, at + v.length);
        if (URL_RE.test(v)) return add("url", at, at + v.length);

        // Flow sequence/map: [a, b] or {a: b}. Color the brackets and commas.
        if (/^[[{].*[\]}]$/.test(v)) {
            for (let i = 0; i < v.length; i++) {
                if ("[]{},".includes(v[i])) add("punct", at + i, at + i + 1);
            }
            return;
        }

        // Anchors, aliases, tags and block-scalar indicators.
        if (/^([&*!][^\s]+|[|>][-+]?)$/.test(v)) return add("punct", at, at + v.length);
    }

    function scanBlock(block) {
        const { text, locate } = textOf(block);
        const add = (name, from, to) => {
            if (to <= from) return;
            const r = new Range();
            r.setStart(...locate(from));
            r.setEnd(...locate(to));
            hl[name].add(r);
        };

        let lineStart = 0;
        for (const line of text.split("\n")) {
            const trimmed = line.trimStart();
            const indent = line.length - trimmed.length;
            let m;
            if (trimmed.startsWith("#")) {
                add("comment", lineStart + indent, lineStart + line.length);
            } else if ((m = KEY_LINE.exec(line))) {
                const [, sp, dash = "", key, gap, , value] = m;
                let at = lineStart + sp.length;
                if (dash) add("punct", at, at + 1);
                at += dash.length;
                add("key", at, at + key.length);
                at += key.length + gap.length;
                add("punct", at, at + 1);
                scanValue(value, at + 1, add);
            } else if ((m = LIST_ITEM.exec(line))) {
                const [, sp, dash, gap, value] = m;
                const at = lineStart + sp.length;
                add("punct", at, at + dash.length);
                scanValue(value, at + dash.length + gap.length, add);
            }
            lineStart += line.length + 1;
        }
    }

    function refresh() {
        for (const h of Object.values(hl)) h.clear();
        document.querySelectorAll("#write pre.md-meta-block").forEach(scanBlock);
    }

    let queued = false;
    const schedule = () => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => {
            queued = false;
            refresh();
        });
    };

    const start = () => {
        new MutationObserver(schedule).observe(document.body, {
            subtree: true,
            childList: true,
            characterData: true,
        });
        schedule();
    };

    if (document.body) start();
    else document.addEventListener("DOMContentLoaded", start);
})();
