# Set XDG-compliant zsh config directory
export ZDOTDIR="$HOME/.config/zsh"

# pnpm global bin directory
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Go bin directory
export GOPATH="$HOME/go"
case ":$PATH:" in
  *":$GOPATH/bin:"*) ;;
  *) export PATH="$PATH:$GOPATH/bin" ;;
esac
