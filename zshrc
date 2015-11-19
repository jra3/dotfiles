autoload bashcompinit && bashcompinit
autoload compinit && compinit

# Interana Dev First!
export DEVTOOLSDIR=/home/john/interana/devtools
source $DEVTOOLSDIR/devrc

# eval "$(register-python-argcomplete ia)"

ZSH=$HOME/.oh-my-zsh

export ZSH_TMUX_AUTOSTART=true
export ZSH_TMUX_AUTOCONNECT=true

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

export CLOWNTOWN=1

export EDITOR=emacs
export EMACS_DIR=~/.dot-emacs
export INPUTRC=~/.inputrc

alias g=git
alias b="cd ~/interana/backend"

alias db="/opt/interana/third_party/bin/mysql --socket=/tmp/iasql.sock $@ <&0 -u nobody -pti"
alias monit="sudo -u interana /home/john/interana/backend/scripts/mon_me.sh"
alias t="nosetests --with-timer --with-coverage --cover-erase --cover-branches --cover-package=."

# Customize to your needs...
export PATH=~/bin:~/.local/bin:/opt/interana/third_party/bin:$PATH
export PATH=/usr/local/bin:/usr/local/sbin:$PATH

PYTHONPATH=$PYTHONPATH:~/interana/backend:~/.local/lib/python2.7/site-packages/
