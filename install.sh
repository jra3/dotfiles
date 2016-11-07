#!/bin/sh


SCRIPTPATH=$HOME/.dotfiles

for file in gitconfig inputrc tmux.conf zsh*; do
    echo $file
    ln -fs $SCRIPTPATH/$file ~/.$file
done

mkdir -p ~/bin
for script in $SCRIPTPATH/scripts/*; do
    ln -fs $script ~/bin
done
