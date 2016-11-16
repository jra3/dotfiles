# Local variables:
# coding: utf-8
# mode: sh
# End:

autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit

export PYTHONSTARTUP="$HOME/.pythonrc"

ZSH=$HOME/.oh-my-zsh

ZSH_THEME="afowler"
export UPDATE_ZSH_DAYS=300

COMPLETION_WAITING_DOTS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(
    autojump    # a cd that 'learns'. run brew install autojump
    common-aliases 
    dirhistory  # M-Left, M-Right
    encode64    # encode64, decode64
    fabric      # autocomplete
    gitfast     # faster git prompt et al      
    jsontools   # pp_json, is_json, urlencode_json, urldecode_json
    npm         # autocomplete
    nyan        # NYAN!!!
    osx         #
    pj
    pep8        # autocomplete
    pip         # autocomplete
    pyenv       # prompt
    pylint      # autocomplete
    python      # autocomplete
    redis-cli   # autocomplete
    safe-paste  # "safely" allow paste of things with backticks
    sudo        # ESC-ESC
    supervisor  # autocomplete
    tmux        # https://github.com/robbyrussell/oh-my-zsh/wiki/Plugins#tmux
    urltools    # urlencode, urldecode
    vagrant     # autocomplete
    zsh_reload  
    catimg      # lulz
)

source $ZSH/oh-my-zsh.sh

# special indicator for sandboxes
if [[ $(hostname) = *jra3* ]]; then
    CARETCOLOR=red
fi

# Non oh-my-zsh below here =====================================================

export GOROOT=/usr/local/opt/go/libexec
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin:$GOROOT/bin

export EMACS_DIR=~/.dot-emacs
export INPUTRC=~/.inputrc

alias g=git

case "$(uname -s)" in    
    Darwin)
	source $HOME/.zsh_mac
	;;
    
    Linux)
	source $HOME/.zsh_linux
	;;
    
    *)
	echo 'Kill yourself'
	;;
esac

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# So it has come to this...
