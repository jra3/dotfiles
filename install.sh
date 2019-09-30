#!/bin/sh

SCRIPTPATH=$HOME/.dotfiles

for file in macos gnus gitconfig inputrc tmux.conf; do
    echo $file
    ln -fs $SCRIPTPATH/$file ~/.$file
done

mkdir -p ~/bin
for script in $SCRIPTPATH/scripts/*; do
    ln -fs $script ~/bin
done
