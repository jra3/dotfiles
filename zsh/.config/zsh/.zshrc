# Source environment setup
. "$HOME/.local/bin/env"

# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# History configuration (XDG-compliant)
export HISTFILE="$XDG_STATE_HOME/zsh/history"
export HISTSIZE=130000
export SAVEHIST=130000
mkdir -p "$(dirname "$HISTFILE")"

# History options
setopt EXTENDED_HISTORY       # Record timestamp in history
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate entries
setopt HIST_IGNORE_SPACE      # Ignore commands starting with space
setopt HIST_VERIFY            # Show command before executing from history
setopt SHARE_HISTORY          # Share history across sessions
setopt INC_APPEND_HISTORY     # Add commands immediately

# Basic zsh options
setopt AUTO_CD              # cd by typing directory name
setopt AUTO_PUSHD           # push old directory onto stack
setopt PUSHD_IGNORE_DUPS    # don't push duplicates

# Omarchy defaults (shell-agnostic)
source ~/.local/share/omarchy/default/bash/aliases
source ~/.local/share/omarchy/default/bash/functions
source ~/.local/share/omarchy/default/bash/envs


# ============================================================================
# Directory Navigation
# ============================================================================
setopt AUTO_CD              # Auto changes to a directory without typing cd
setopt CDABLE_VARS          # Change directory to a path stored in a variable
setopt MULTIOS              # Write to multiple descriptors
setopt EXTENDED_GLOB        # Use extended globbing syntax
unsetopt CLOBBER            # Do not overwrite existing files with > and >>
                            # Use >! and >>! to bypass

# ============================================================================
# Shell Options
# ============================================================================
set -o physical
setopt SH_WORD_SPLIT
setopt CORRECT              # Command auto-correction
setopt INTERACTIVE_COMMENTS # Allow comments in interactive shell
setopt RC_QUOTES            # Allow 'Henry''s Garage' instead of 'Henry'\''s Garage'


export EDITOR="emacsclient -nw"
e() {
    emacsclient -n "$@"
    hyprctl dispatch focuswindow "class:^(emacs)$"
}

# ============================================================================
# Completion System
# ============================================================================

autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # Case-insensitive
setopt COMPLETE_ALIASES


# ============================================================================
# fzf - Fuzzy Finder
# ============================================================================
if command -v fzf &>/dev/null; then
    source /usr/share/fzf/completion.zsh
    source /usr/share/fzf/key-bindings.zsh

    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

    export FZF_DEFAULT_OPTS='
        --height 40%
        --layout=reverse
        --border
        --inline-info
        --color=dark
        --color=fg:-1,bg:-1,hl:#5fff87,fg+:-1,bg+:-1,hl+:#ffaf5f
        --color=info:#af87ff,prompt:#5fff87,pointer:#ff87d7,marker:#ff87d7,spinner:#ff87d7
        --bind="ctrl-/:toggle-preview"
        --bind="ctrl-u:preview-page-up"
        --bind="ctrl-d:preview-page-down"
    '

    export FZF_CTRL_T_OPTS="
        --preview 'bat -n --color=always --line-range :500 {} 2>/dev/null || cat {} 2>/dev/null || echo \"No preview available\"'
        --preview-window=right:50%:hidden
        --bind='ctrl-/:toggle-preview'
    "

    export FZF_ALT_C_OPTS="
        --preview 'eza --tree --level=2 --color=always {} 2>/dev/null || ls -la {}'
        --preview-window=right:50%:hidden
        --bind='ctrl-/:toggle-preview'
    "

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi


# ============================================================================
# zoxide - Initialize (omarchy provides the zd wrapper)
# ============================================================================
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi


# ============================================================================
# Key Bindings
# ============================================================================
bindkey -e
bindkey '^[[1;5C' forward-word        # Ctrl+Right
bindkey '^[[1;5D' backward-word       # Ctrl+Left

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
# Color Definitions
# ============================================================================
typeset -gA colors
colors=(
    'blue'     '%F{4}'
    'cyan'     '%F{6}'
    'green'    '%F{2}'
    'magenta'  '%F{5}'
    'red'      '%F{1}'
    'white'    '%F{7}'
    'yellow'   '%F{3}'
    'black'    '%F{0}'
    'reset'    '%f'
)


# ============================================================================
# Git Status Symbols
# ============================================================================
typeset -gA git_symbols
git_symbols=(
    'added'      '✚'
    'ahead'      '⬆'
    'behind'     '⬇'
    'deleted'    '✖'
    'modified'   '✱'
    'renamed'    '➜'
    'unmerged'   '═'
    'untracked'  '✭'
)


# ============================================================================
# VCS Info Configuration (Git Integration)
# ============================================================================
autoload -Uz vcs_info
setopt PROMPT_SUBST
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr "${colors[green]}${git_symbols[added]}${colors[reset]}"
zstyle ':vcs_info:*' unstagedstr "${colors[red]}${git_symbols[modified]}${colors[reset]}"
zstyle ':vcs_info:git:*' formats " ${colors[cyan]}%b%c%u${colors[reset]}"
zstyle ':vcs_info:git:*' actionformats " ${colors[cyan]}%b${colors[reset]} ${colors[yellow]}(%a)${colors[reset]}%c%u"


# ============================================================================
# Prompt Functions
# ============================================================================
function prompt_sorin_pwd {
    local pwd="${PWD/#$HOME/~}"
    print -n "${colors[blue]}${pwd}${colors[reset]}"
}
function prompt_sorin_git_status {
    [[ -n "$vcs_info_msg_0_" ]] && print -n "$vcs_info_msg_0_"
}
function prompt_sorin_precmd {
    vcs_info
}


# ============================================================================
# Terminal Title
# ============================================================================
function set_terminal_title {
    local title_format="${PWD/#$HOME/~}"
    case "$TERM" in
        xterm*|rxvt*|screen*|tmux*)
            print -Pn "\e]0;${title_format}\a"
            ;;
    esac
}

# Add precmd functions
precmd_functions+=(prompt_sorin_precmd)
precmd_functions+=(set_terminal_title)


# ============================================================================
# Build Prompt
# ============================================================================
function build_prompt {
     local prompt_pwd="$(prompt_sorin_pwd)"

     # Multicolored triple chevron prompt
     local prompt_char=""
     if [[ $UID -eq 0 ]]; then
         prompt_char="${colors[red]}#${colors[reset]} "
     else
         prompt_char="${colors[red]}❯${colors[yellow]}❯${colors[green]}❯${colors[reset]} "
     fi

     print -n "${prompt_pwd} ${prompt_char}"
 }


# Build the right prompt
function build_rprompt {
     local rprompt=""

     # Git status
     local git_status="$(prompt_sorin_git_status)"
     if [[ -n "$git_status" ]]; then
         rprompt="${git_status}"
     fi

     # Return code (only show if non-zero)
     if [[ -n "$rprompt" ]]; then
         rprompt+=" "
     fi
     rprompt+='%(?..'${colors[red]}'✘ %?'${colors[reset]}')'

     print -n "$rprompt"
}

PROMPT='$(build_prompt)'
RPROMPT='$(build_rprompt)'


# ============================================================================
# fzf-Powered Functions
# ============================================================================

# Search and edit files
fe() {
    local files
    IFS=$'\n' files=($(fzf --query="$1" --multi --select-1 --exit-0 \
        --preview 'bat -n --color=always --line-range :500 {} 2>/dev/null || cat {}' \
        --preview-window=right:50%:hidden \
        --bind='ctrl-/:toggle-preview'))
    [[ -n "$files" ]] && ${EDITOR:-vim} "${files[@]}"
}

# Change to selected directory
fcd() {
    local dir
    dir=$(fd --type d --hidden --follow --exclude .git . ${1:-.} 2>/dev/null | fzf +m \
        --preview 'eza --tree --level=2 --color=always {} 2>/dev/null || ls -la {}' \
        --preview-window=right:50%:hidden \
        --bind='ctrl-/:toggle-preview') && cd "$dir"
}

# Git branch selector
fbr() {
    local branches branch
    branches=$(git --no-pager branch -vv --color=always | grep -v '^[[:space:]]*+') &&
    branch=$(echo "$branches" | fzf +m --ansi --header='[git branch]') &&
    git checkout $(echo "$branch" | awk '{print $1}' | sed "s/.* //")
}

# Git worktree selector
fwt() {
    local worktrees worktree_dir
    worktrees=$(git worktree list | awk '{print $1 " [" $3 "]"}') &&
    worktree_dir=$(echo "$worktrees" | fzf +m --ansi --header='[git worktree]' | awk '{print $1}') &&
    cd "$worktree_dir"
}

# Git commit browser
fshow() {
    git log --graph --color=always \
        --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --tiebreak=index --bind=ctrl-s:toggle-sort \
        --header='[git log] Press CTRL-S to toggle sort' \
        --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | xargs git show --color=always' \
        --bind "enter:execute:
            (grep -o '[a-f0-9]\{7,\}' | xargs git show --color=always | less -R) <<< {}"
}

# Search content in files with ripgrep
frg() {
    local file line
    read -r file line <<<"$(rg --no-heading --line-number --color=always "${*:-}" | \
        fzf -d ':' -n 2.. --ansi --no-sort \
        --preview-window 'down:50%:+{2}' \
        --preview 'bat --color=always {1} --highlight-line {2}')"
    if [[ -n "$file" ]]; then
        ${EDITOR:-vim} "$file" "+$line"
    fi
}

# Kill process
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m --header='[kill process]' | awk '{print $2}')
    if [ "x$pid" != "x" ]; then
        echo $pid | xargs kill -${1:-9}
    fi
}

# Extract archives
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.zst)       unzstd "$1"      ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Aliases for fzf functions
alias vf='fe'
alias cdf='fcd'
alias gcb='fbr'
alias glog='fshow'
alias rgf='frg'
alias killf='fkill'

# Other aliases
alias ag='rg'


# ============================================================================
# Utility Functions
# ============================================================================

# Unix timestamp converter
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -d "@$1" -Iseconds
    fi
}


# ============================================================================
# Tool Completions
# ============================================================================

# pnpm
if command -v pnpm &>/dev/null; then
    eval "$(pnpm completion zsh 2>/dev/null)"
fi

# pip
if command -v pip &>/dev/null; then
    eval "$(pip completion --zsh 2>/dev/null)"
fi


# pnpm
export PNPM_HOME="/home/john/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
