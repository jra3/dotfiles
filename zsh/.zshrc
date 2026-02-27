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
# Add custom completions to fpath
fpath=($XDG_CONFIG_HOME/zsh/completions $fpath)

autoload -Uz compinit
# Only regenerate dump file if it's older than 24 hours; -C skips security check
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# Options
setopt COMPLETE_IN_WORD    # Complete from both ends of a word
setopt ALWAYS_TO_END       # Move cursor to end of completed word
setopt AUTO_MENU           # Show completion menu on successive tab press
setopt AUTO_LIST           # Automatically list choices on ambiguous completion
setopt AUTO_PARAM_SLASH    # Add trailing slash for completed directories
unsetopt MENU_COMPLETE     # Don't autoselect first completion entry

# Caching
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"

# Case-insensitive, partial-word, and substring completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Group matches and describe
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:options' auto-description '%d'
zstyle ':completion:*:corrections' format ' %F{green}-- %d (errors: %e) --%f'
zstyle ':completion:*:descriptions' format ' %F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format ' %F{purple} -- %d --%f'
zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion:*:default' list-prompt '%S%M matches%s'
zstyle ':completion:*' format ' %F{yellow}-- %d --%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes

# Fuzzy match mistyped completions
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle -e ':completion:*:approximate:*' max-errors 'reply=($((($#PREFIX+$#SUFFIX)/3))numeric)'

# Don't complete unavailable commands
zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec))'

# Directories
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'users' 'expand'
zstyle ':completion:*' squeeze-slashes true

# History
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes

# Ignore multiple entries
zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
zstyle ':completion:*:rm:*' file-patterns '*:all-files'

# Kill
zstyle ':completion:*:*:*:*:processes' command 'ps -u $LOGNAME -o pid,user,command -w'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;36=0=01'
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*' insert-ids single

# SSH/SCP/RSYNC
zstyle ':completion:*:(ssh|scp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:(ssh|scp|rsync):*' group-order users files all-files hosts-domain hosts-host hosts-ipaddr
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-host' ignored-patterns '*(.|:)*' loopback ip6-loopback localhost ip6-localhost broadcasthost
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-ipaddr' ignored-patterns '^(<->.<->.<->.<->|(|::)([[:xdigit:].]##:(#c,2))##(|%*))' '127.0.0.<->' '255.255.255.255' '::1' 'fe80::*'

# Git - only complete branches/commits for checkout (not modified files)
# TEMPORARILY DISABLED for debugging:
# zstyle ':completion:*:git-checkout:*' tag-order 'tree-ishs' -

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
# Cached eval helper: regenerates only when binary is newer than cache
# ============================================================================
_zsh_cached_source() {
  local cmd="$1" name="$2"; shift 2
  local cache="$HOME/.cache/zsh/${name}.zsh"
  if [[ ! -f "$cache" || "$(command -v "$cmd")" -nt "$cache" ]]; then
    mkdir -p "${cache:h}"
    "$cmd" "$@" >"$cache" 2>/dev/null
  fi
  source "$cache"
}

# ============================================================================
# Prompt (Starship)
# ============================================================================
_zsh_cached_source starship starship-init init zsh

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
    _zsh_cached_source zoxide zoxide-init init zsh
fi

# ============================================================================
# direnv
# ============================================================================
if command -v direnv &>/dev/null; then
    _zsh_cached_source direnv direnv-hook hook zsh
fi

# ============================================================================
# pyenv
# ============================================================================
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv &>/dev/null; then
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
fi

# ============================================================================
# Shared Functions
# ============================================================================
fe()  { local f; IFS=$'\n' f=($(fzf --query="$1" --multi)); [[ -n "$f" ]] && ${EDITOR:-vim} "${f[@]}"; }
fcd() { local d; d=$(fd --type d . ${1:-.} | fzf +m) && cd "$d"; }
fbr() {
  git branch -vv | fzf +m --ansi \
    --height 80% \
    --preview 'git log --oneline --graph --color=always -20 $(echo {} | awk '"'"'{print $1}'"'"')' \
    --preview-window 'down:50%:wrap' \
    --bind '|:change-preview-window(down:50%:wrap|down:20%:wrap|hidden)' \
  | awk '{print $1}' | xargs git checkout
}
fwt() { cd "$(git worktree list | fzf +m | awk '{print $1}')"; }

# fzf-powered git worktree manager with gtr integration
# Main logic in ~/.local/bin/fgtr script; this wrapper handles cd/editor/ai
fgtr() {
  local result
  result=$(command fgtr) || return $?
  case "$result" in
    EDITOR:*) git gtr editor "${result#EDITOR:}" ;;
    AI:*)     git gtr ai "${result#AI:}" ;;
    "")       ;;
    *)        builtin cd "$result" ;;
  esac
}

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

_gt_yargs_completions()
{
  local reply
  local si=$IFS
  IFS=$'
' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" graphite --get-yargs-completions "${words[@]}"))
  IFS=$si
  _describe 'values' reply
}

# ============================================================================
# Aliases
# ============================================================================
alias gg='graphite'
compdef _gt_yargs_completions graphite
compdef _gt_yargs_completions gg
alias g='git'
compdef _git g
alias ag='rg'
alias ..='cd ..'
alias ...='cd ../..'
alias tn='tmux-new-session'
alias twt='tmux-worktree'
alias watch='watch --color'
alias gtr='git gtr'
compdef _gtr gtr

# git-worktree-runner: cd into a worktree
gcd() { cd "$(git gtr go "$1")" }
compdef '_gtr_all_targets' gcd

# ============================================================================
# Tool Completions
# ============================================================================
command -v pnpm &>/dev/null && _zsh_cached_source pnpm pnpm-completion completion zsh
command -v gh &>/dev/null && _zsh_cached_source gh gh-completion completion -s zsh
[[ -f ~/.cargo/env ]] && source ~/.cargo/env

# ============================================================================
# PATH
# ============================================================================
path=($HOME/bin $HOME/.local/bin $HOME/go/bin /usr/local/bin $path)

# # ============================================================================
# # mise (version manager for Node, etc.)
# # ============================================================================
# if command -v mise &>/dev/null; then
#    eval "$(mise activate zsh)"
# fi

# ============================================================================
# Platform-Specific Configuration
# ============================================================================
if [[ "$OSTYPE" == darwin* ]]; then
    source "$HOME/.config/zsh/darwin.zsh"
else
    source "$HOME/.config/zsh/arch.zsh"
fi

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Add ~/.local/bin to PATH for user binaries
export PATH="$HOME/.local/bin:$PATH"

# --- Gas Town Integration (managed by gt) ---
[[ -f "/home/jallen/.config/gastown/shell-hook.sh" ]] && source "/home/jallen/.config/gastown/shell-hook.sh"
# --- End Gas Town ---

# Speed up: only run gastown precmd hook when the directory actually changes.
# The hook does git rev-parse + file-system checks on every Enter keypress,
# which makes rapid Enter presses slow. Since GT_TOWN_ROOT/GT_RIG can't change
# without a directory change, it's safe to skip when $PWD is unchanged.
if (( $+functions[_gastown_hook] )); then
  _gastown_precmd_last_dir=
  _gastown_hook_fast() {
    [[ "$PWD" == "$_gastown_precmd_last_dir" ]] && return 0
    _gastown_precmd_last_dir=$PWD
    _gastown_hook
  }
  add-zsh-hook -d precmd _gastown_hook
  add-zsh-hook precmd _gastown_hook_fast
fi
