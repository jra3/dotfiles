#!/bin/sh

SCRIPT=$( readlink -e $0 )
SCRIPTPATH=$( dirname $SCRIPT )

for file in gitconfig inputrc tmux.conf zshrc; do
    ln -fs $SCRIPTPATH/$file ~/.$file
done

mkdir -p ~/bin
for script in $SCRIPTPATH/scripts/*; do
    ln -fs $script ~/bin
done

ln -fs $SCRIPTPATH/upgrade.sh ~/bin/up
