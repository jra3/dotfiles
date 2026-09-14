# helium — the YouTube Shorts remover

One unpacked Chromium extension, `youtube-no-shorts`, loaded into Helium by path.

## What is *not* here: the flags file

`~/.config/helium-browser-flags.conf` is **generated, never stowed**.
`pacman/configure-system` writes it from `$OMARCHY_PATH/config/chromium-flags.conf`
with `~/` expanded to `$HOME`, because Helium's wrapper deliberately escapes both
`~` and `$` before `eval` — a tilde path reaches the browser literally and the
extension silently fails to load.

That same stanza **appends** this package's extension directories to whatever
`--load-extension` line Omarchy shipped. Two consequences worth knowing:

- An Omarchy update that adds a bundled extension is picked up automatically on
  the next `configure-system` run. There is no hand-maintained copy to drift.
- Chromium keeps only the **last** occurrence of a repeated switch, so every
  extension must end up on one joined list. It cannot be split across lines, or
  across `/etc/helium-browser-flags.conf` and the user one (the wrapper reads
  both).

Adding another extension to this package means adding its directory name to the
`for ext in ...` loop in that stanza.

Force-installed store extensions (floccus, F.B. Purity) are a separate mechanism
— policy JSON in `/etc/chromium/policies/managed/`, also written by
`configure-system`. See the root `CLAUDE.md`.

## Stow this package FOLDED — the one place `--no-folding` is wrong

The repo's usual rule is `--no-folding` for any directory an external tool writes
into, and Chromium does write into this one: it compiles `rules.json` and drops
`_metadata/generated_indexed_rulesets/` beside the manifest at load time (which
is why that path is in `.gitignore`).

Do it anyway. Unfolded, `~/.local/share/chromium-extensions/youtube-no-shorts/`
is a real directory of file symlinks pointing back into `~/.dotfiles`, and
Chromium canonicalises every extension resource and **refuses to load anything
that resolves outside the extension root**. The failure is near-silent and
lopsided: `manifest.json` and `rules.json` are read by the browser process and
work fine, so the redirects still fire and the extension looks healthy at
`chrome://extensions` — but neither content script is ever injected, and every
Short stays on the page. Measured unfolded: redirect OK, 30 of 30 Shorts links
still visible.

Folded, the whole `chromium-extensions` directory is one symlink, the extension
root resolves into the repo, and every resource sits inside it. If
`~/.local/share/chromium-extensions` already exists as a real directory, stow
will not fold — remove it and stow again.

## youtube-no-shorts

MV3, unpacked. Modelled on Omarchy's own `whatsapp-slim`, down to the `key`
field, which pins the extension ID (`iekpfdmddbgnodhpgnmojpmebcdbmoio`) so it
stays the same across machines and reinstalls.

- **`rules.json`** — declarativeNetRequest redirects, applied at the network
  layer before anything loads: `/shorts/<id>` → `/watch?v=<id>`,
  `/@channel/shorts` → `/@channel/videos`, and a bare `/shorts` → `/`. A Short
  someone sends you still opens; it opens in the normal player, with no reel to
  fall into.
- **`no-shorts.css`** — injected at `document_start`, so Shorts surfaces never
  paint. Covers everything YouTube names after Shorts.
- **`no-shorts.js`** — the rest: the sidebar entry and the filter chips carry no
  `/shorts/` href at all and can only be matched by label; YouTube's own
  pushState routing loads a Short without a `main_frame` request, so the
  redirect is repeated there too.

### Two traps worth keeping

**Never hide the section around a shelf on the search page.** One
`ytd-item-section-renderer` holds the Shorts shelves *and* all sixteen real
results as siblings — collapsing it blanks the page. Shelves are hidden as the
shelf element (`grid-shelf-view-model`), and a section is only collapsed where
the shelf is provably its `:only-child`.

**The sidebar "Shorts" entry has no `href`.** Measured: its
`ytd-guide-entry-renderer` returns `href=null`, unlike every neighbour. CSS
cannot reach it; the label sweep in the JS is what removes it.

### Verified

Measured on a throwaway headless profile over CDP, logged out, against
`youtube.com/results?search_query=guitar`:

| | baseline | with extension |
|---|---|---|
| visible `/shorts/` links | 30 | **0** |
| visible `grid-shelf-view-model` | 2 | **0** |
| visible Shorts lockups | 30 | **0** |
| visible real `/watch` results | 18 | **18 of 18** |
| sidebar entries | 14 | 13 (only "Shorts" gone) |
| filter chips | All, **Shorts**, Unwatched, Watched, Videos, … | same minus Shorts |

All three redirects land where they should, and `@MrBeast`'s channel tab strip
comes back `Home, Videos, Shorts [HIDDEN], Shows, Posts`.

Not exercised, because they need a logged-in session: the Shorts shelf on the
Home and Subscriptions feeds, and Shorts in the watch-page sidebar. Those rules
(`ytd-rich-shelf-renderer[is-shorts]`, `ytd-reel-shelf-renderer`,
`ytd-compact-video-renderer:has(a[href^="/shorts/"])`) are written against the
element names YouTube still ships but are unproven here.

### Re-checking after a YouTube redesign

YouTube renames these elements every so often — search results moved from
`ytd-reel-shelf-renderer` to `grid-shelf-view-model` at some point. To see what
it calls things today, open a Shorts-heavy page and ask the live DOM:

```js
// devtools console, on a search results page
const vis = el => getComputedStyle(el).display !== 'none' && el.getClientRects().length;
[...document.querySelectorAll('a[href^="/shorts/"]')].filter(vis)
  .map(a => { let e = a, c = []; for (let d = 0; e && d < 6; d++) { c.push(e.tagName.toLowerCase()); e = e.parentElement; } return c.join(' < '); });
```

An empty array means nothing leaked. Anything listed names the renderer that
needs a new selector.

## Install

```bash
cd ~/.dotfiles
stow helium              # folded, deliberately -- see above
pacman/configure-system  # writes the flags file and appends this extension
```

Order matters: `configure-system` skips the append and tells you to re-run if the
extension isn't stowed yet. Then restart Helium — `--load-extension` is read once
at process start, and a second `helium-browser` invocation just hands the URL to
the running instance. Confirm with `youtube.com/shorts/dQw4w9WgXcQ` landing on
`/watch`.
