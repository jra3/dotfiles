#!/usr/bin/env zsh

# ============================================================================
# History Configuration (XDG-compliant)
# ============================================================================
export HISTFILE="$XDG_STATE_HOME/zsh/history"
export HISTSIZE=130000
export SAVEHIST=130000
mkdir -p "$(dirname "$HISTFILE")"

setopt EXTENDED_HISTORY       # Record timestamp in history
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate entries
setopt HIST_IGNORE_SPACE      # Ignore commands starting with space
setopt HIST_VERIFY            # Show command before executing from history
setopt SHARE_HISTORY          # Share history across sessions
setopt INC_APPEND_HISTORY     # Add commands immediately

# ============================================================================
# Directory Navigation
# ============================================================================
setopt AUTO_CD              # Auto changes to a directory without typing cd
setopt AUTO_PUSHD           # Push old directory onto stack
setopt PUSHD_IGNORE_DUPS    # Don't push duplicates
setopt CDABLE_VARS          # Change directory to a path stored in a variable
setopt MULTIOS              # Write to multiple descriptors
setopt EXTENDED_GLOB        # Use extended globbing syntax
unsetopt CLOBBER            # Do not overwrite existing files with > and >>

# ============================================================================
# Shell Options
# ============================================================================
set -o physical
setopt SH_WORD_SPLIT
setopt CORRECT
setopt INTERACTIVE_COMMENTS
setopt RC_QUOTES

# ============================================================================
# Completion System
# ============================================================================
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
setopt COMPLETE_ALIASES

# ============================================================================
# Key Bindings
# ============================================================================
bindkey -e
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

autoload -Uz history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey '^[[A' history-beginning-search-backward-end
bindkey '^[[B' history-beginning-search-forward-end
bindkey '^P' history-beginning-search-backward-end
bindkey '^N' history-beginning-search-forward-end
bindkey '^U' backward-kill-line
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^W' backward-kill-word

# ============================================================================
# Prompt (Starship)
# ============================================================================
eval "$(starship init zsh)"

# Terminal title
precmd_functions+=(set_terminal_title)
function set_terminal_title {
    print -Pn "\e]0;${PWD/#$HOME/~}\a"
}

# ============================================================================
# fzf Configuration
# ============================================================================
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --inline-info'

# ============================================================================
# zoxide
# ============================================================================
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# ============================================================================
# Shared Functions
# ============================================================================
fe()  { local f; IFS=$'\n' f=($(fzf --query="$1" --multi)); [[ -n "$f" ]] && ${EDITOR:-vim} "${f[@]}"; }
fcd() { local d; d=$(fd --type d . ${1:-.} | fzf +m) && cd "$d"; }
fbr() { git branch -vv | fzf +m --ansi | awk '{print $1}' | xargs git checkout; }
fwt() { cd "$(git worktree list | fzf +m | awk '{print $1}')"; }

extract() {
    [[ -f "$1" ]] || { echo "'$1' is not a valid file"; return 1; }
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf "$1" ;; *.bz2) bunzip2 "$1" ;;
        *.rar) unrar x "$1" ;; *.gz) gunzip "$1" ;; *.tar) tar xf "$1" ;;
        *.tbz2) tar xjf "$1" ;; *.tgz) tar xzf "$1" ;; *.zip) unzip "$1" ;;
        *.Z) uncompress "$1" ;; *.7z) 7z x "$1" ;; *.zst) unzstd "$1" ;;
        *) echo "'$1' cannot be extracted" ;;
    esac
}

# ============================================================================
# Aliases
# ============================================================================
alias g='git'
alias ag='rg'
alias ..='cd ..'
alias ...='cd ../..'
alias tn='tmux-new-session'
alias twt='tmux-worktree'

# ============================================================================
# Tool Completions
# ============================================================================
command -v pnpm &>/dev/null && eval "$(pnpm completion zsh 2>/dev/null)"
command -v gh &>/dev/null && eval "$(gh completion -s zsh)"
[[ -f ~/.cargo/env ]] && source ~/.cargo/env

# ============================================================================
# PATH
# ============================================================================
path=($HOME/bin $HOME/.local/bin $HOME/go/bin /usr/local/bin $path)

# ============================================================================
# Platform-Specific Configuration
# ============================================================================
if [[ "$OSTYPE" == darwin* ]]; then
    source "$ZDOTDIR/darwin.zsh"
else
    source "$ZDOTDIR/arch.zsh"
fi

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
