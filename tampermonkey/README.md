# tampermonkey — userscripts for Helium

Not a stow package: nothing here goes into `$HOME`. It is tooling, like `pacman/`,
and is deliberately absent from every list in `bootstrap`.

## How the pieces fit

- **The extension** is force-installed into every Helium profile by policy:
  `pacman/configure-system` writes its ID (`dhdgffkkebhmkfjojejmpbldmpobfkfo`)
  into `/etc/chromium/policies/managed/extensions.json`, beside floccus and
  F.B. Purity. See the root `CLAUDE.md` for why the update URL carries
  `prodversion`.
- **The scripts** are the `*.user.js` files in this directory. The repo is public,
  so each one has a stable URL on `raw.githubusercontent.com`. That URL is both
  where Tampermonkey installs the script from and where it checks for updates.
  It is also the link to send someone.

Policy installs the extension and nothing more. It cannot install scripts or
change Tampermonkey's settings, so on each machine:

1. Turn on **Allow User Scripts** at `chrome://extensions` → Tampermonkey →
   Details. Chromium 138+ gives MV3 userscript managers no script access without
   it, and Tampermonkey shows a warning banner until it is on.
2. Run `tampermonkey/install` and click Install on each tab it opens.

## Adding a script

Every script needs these header lines, or it will not update itself:

```js
// @version      1.0
// @updateURL    https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/<name>.user.js
// @downloadURL  https://raw.githubusercontent.com/jra3/dotfiles/main/tampermonkey/<name>.user.js
```

Tampermonkey updates a script only when the remote `@version` is higher than
the installed one. **Bump `@version` on every change**, or other machines keep
the old copy without any warning. It checks once a day by default. To pull
a change sooner, use Dashboard → Installed userscripts → *Last updated* column →
click the date.

Edit the file here, not in Tampermonkey's editor. An edit made in Tampermonkey
lives only in that profile, and the next update from the repo overwrites it.

The file must end in `.user.js`. Tampermonkey intercepts navigation to that
suffix and shows its install page. Any other name shows as plain text.
