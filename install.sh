#!/bin/sh

SCRIPT=$( readlink -e $0 )
SCRIPTPATH=$( dirname $SCRIPT )

for file in gitconfig inputrc tmux.conf zshrc; do
    echo $file
    ln -fs $SCRIPTPATH/$file ~/.$file
done
