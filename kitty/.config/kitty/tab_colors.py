"""Colour a kitty tab by what is running in it.

kitty fires on_cmd_startstop for every command once shell integration is on
(`shell_integration no-cursor` in shared.conf still enables it -- that value only
opts out of the cursor-shape changes), so a tab can be recoloured the moment
herdr starts and reverted when it exits. No polling, no shell wrapper, nothing
to keep in sync with how herdr happens to be invoked.

Tab colours are four plain attributes on the Tab object -- ints, or None to fall
back to the active_tab_*/inactive_tab_* keys in kitty.conf. They are the same
attributes `kitten @ set-tab-color` assigns, so this writes them directly rather
than shelling out to the remote-control socket on every prompt.

Two things a watcher cannot do, and both are why the next step is a custom
tab_bar.py (`tab_bar_style custom`): watchers are attached at window creation,
so a config reload does not retrofit them onto tabs that already exist, and a
tab that already had herdr running when kitty started never saw a start event.
A draw-time hook sees every tab on every frame and has neither problem.
"""

import os
import re
import shlex

# Leading tokens that wrap the real command rather than being it.
PASSTHROUGH = frozenset({"command", "exec", "builtin", "nohup", "sudo", "doas", "env"})
# `env`-style VAR=value assignments, which sit between `env` and the command.
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# Tab colour attributes, in the order kitty declares them.
ATTRS = ("active_fg", "active_bg", "inactive_fg", "inactive_bg")

# Command name -> colours. Contrast against Tokyo Night measured with WCAG
# relative luminance; the 4.5:1 AA floor is what kitty's own #444-on-#999
# inactive default (3.4:1) misses.
RULES = {
    "herdr": {
        "active_fg": 0x1A1B26,    # background on ...
        "active_bg": 0xF7768E,    # ... red -- 6.5:1
        "inactive_fg": 0xF7768E,  # red on ...
        "inactive_bg": 0x3D2430,  # ... dim red -- 5.3:1
    },
}


def command_name(cmdline):
    """The program a shell-integration cmdline actually runs, or "".

    cmdline arrives as the raw string that was typed, not an argv list, so it
    has to be split -- and an unbalanced quote makes shlex raise rather than
    return, which would otherwise take the watcher down on a typo.
    """
    try:
        argv = shlex.split(cmdline)
    except ValueError:
        return ""
    while argv:
        head = argv[0]
        if ASSIGNMENT.match(head):
            argv = argv[1:]
            continue
        name = os.path.basename(head)
        if name in PASSTHROUGH:
            argv = argv[1:]
            continue
        return name
    return ""


def apply_colors(tab, running):
    """Paint the tab for whatever rule-matching command is still running in it.

    Splits are unbound in shared.conf so a tab is one window in practice, but
    the bookkeeping is per window anyway: clearing on the first exit would
    otherwise wipe the colour a sibling window still wants.
    """
    colors = next((RULES[name] for name in running.values() if name in RULES), None)
    for attr in ATTRS:
        setattr(tab, attr, None if colors is None else colors[attr])
    tab.mark_tab_bar_dirty()


def on_cmd_startstop(boss, window, data):
    tab = window.tabref()
    if tab is None:
        return
    running = getattr(tab, "_tab_colors_running", None)
    if running is None:
        running = {}
        tab._tab_colors_running = running

    if data.get("is_start"):
        name = command_name(data.get("cmdline") or "")
        if name not in RULES:
            # Not tracked, so there is nothing to forget on the matching stop
            # event either -- which is what keeps this dict one entry deep.
            return
        running[window.id] = name
    elif running.pop(window.id, None) is None:
        return

    apply_colors(tab, running)
