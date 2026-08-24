# Arch Linux specific configuration

# Omarchy defaults
[[ -f ~/.local/share/omarchy/default/bash/envs ]] && source ~/.local/share/omarchy/default/bash/envs
[[ -f ~/.local/share/omarchy/default/bash/aliases ]] && source ~/.local/share/omarchy/default/bash/aliases
[[ -f ~/.local/share/omarchy/default/bash/functions ]] && source ~/.local/share/omarchy/default/bash/functions

# Environment setup
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# Editor
# Emacs runs in the terminal; the GUI frame is SUPER+SHIFT+E in Hyprland.
# e() calls `command emacs` because zsh expands aliases when it *defines* a
# function, so a bare `emacs -nw` in the body would become `emacs -nw -nw`.
export EDITOR="emacs -nw"
alias emacs='emacs -nw'
e() { command emacs -nw "$@"; }

# fzf
if command -v fzf &>/dev/null; then
    source /usr/share/fzf/completion.zsh 2>/dev/null
    source /usr/share/fzf/key-bindings.zsh 2>/dev/null
    bindkey -r '^T'
    bindkey '^Xt' fzf-file-widget

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi

# Unix timestamp (GNU date)
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -d "@$1" -Iseconds
    fi
}
