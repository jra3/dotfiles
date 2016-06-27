autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit

export ASYNC_TEST_TIMEOUT=300
export PYTHONSTARTUP="$HOME/.pythonrc"

ZSH=$HOME/.oh-my-zsh

ZSH_THEME="afowler"
export UPDATE_ZSH_DAYS=30

COMPLETION_WAITING_DOTS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(
    autojump
    autopep8
    battery
    bower
    brew
    coffee
    colorize
    common-aliases
    copydir  # copy pwd to clipboard
    copyfile # copy file to clipboard
    cp       # rsync shortcut "cpv"
    dirhistory
    encode64
    git
    git-prompt
    git-remote-branch
    gitignore
    history-substring-search
    iwhois
    jsontools
    mosh
    node
    npm
    nyan
    osx
    pep8
    pip
    pj
    pyenv
    pylint
    python
    repo
    rsync
    safe-paste
    sudo
    tmux
    torrent
    zsh_reload
    catimg
)

source $ZSH/oh-my-zsh.sh

# special indicator for sandboxes
if [[ $(hostname) = *dev* ]]; then
    CARETCOLOR=red
fi

# Non oh-my-zsh below here =====================================================

export EMACS_DIR=~/.dot-emacs
export INPUTRC=~/.inputrc

export ALTERNATE_EDITOR=""
export EDITOR="emacsclient -t"                  # $EDITOR should open in terminal
export VISUAL="emacsclient -c -a emacs"         # $VISUAL opens in GUI with non-daemon as alternate

alias g=git
alias e="$VISUAL --no-wait"
alias t="$EDITOR"

# Customize to your needs...
export PATH=~/bin:~/.local/bin:/opt/interana/third_party/bin:$PATH
export PATH=/usr/local/bin:/usr/local/sbin:$PATH

PYTHONPATH=$PYTHONPATH:~/interana/backend:~/.local/lib/python2.7/site-packages/

# workaround for tramp
if [[ "$TERM" == "dumb" ]]
then
  unsetopt zle
  unsetopt prompt_cr
  unsetopt prompt_subst
  unfunction precmd
  unfunction preexec
  PS1='$ '
fi
