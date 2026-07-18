# slack — open `slack://` deep links in the browser

On this Linux setup (Hyprland, no desktop Slack app) the Slack web interstitial
—`https://<workspace>.slack.com/archives/<id>`— fires a `slack://` deep link to
hand off to the desktop app. With no app registered for the scheme, GNOME's app
chooser dead-ends at **"No Apps available"** and the link never opens.

This package registers a handler that rewrites the deep link to the Slack web
client and opens it in the default browser (Helium).

## Contents

- `.local/bin/slack-url-handler` — parses `team`/`id` out of the `slack://` URL
  and opens `https://app.slack.com/client/<team>/<id>`. Falls back to
  `https://app.slack.com` when it can't resolve them.
- `.local/share/applications/slack-url-handler.desktop` — declares the handler
  for `x-scheme-handler/slack`.

## Install

```bash
cd ~/.dotfiles
stow slack
update-desktop-database ~/.local/share/applications
xdg-mime default slack-url-handler.desktop x-scheme-handler/slack
```

Verify:

```bash
xdg-mime query default x-scheme-handler/slack        # → slack-url-handler.desktop
SLACK_HANDLER_DRYRUN=1 slack-url-handler \
  'slack://channel?team=T0123&id=D0456&st=abc'       # → https://app.slack.com/client/T0123/D0456
```

## Notes

- `app.slack.com/client/...` URLs load the web app directly and skip the
  interstitial entirely — the cleanest link form to share when you can.
- The `.desktop` file is durable in this repo; the `xdg-mime default`
  association lives in `~/.config/mimeapps.list` (not stow-tracked) and is
  re-applied by the install command above.
