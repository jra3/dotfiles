#!/bin/sh


SCRIPTPATH=$HOME/.dotfiles

for file in gitconfig inputrc tmux.conf zshrc; do
    ln -fs $SCRIPTPATH/$file ~/.$file
done

mkdir -p ~/bin
for script in $SCRIPTPATH/scripts/*; do
    ln -fs $script ~/bin
done

ln -fs $SCRIPTPATH/upgrade.sh ~/bin/up
ln -fs $SCRIPTPATH/pub.sh ~/bin/pub
