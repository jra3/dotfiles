#!/bin/sh

SCRIPT=$( readlink -e $0 )
SCRIPTPATH=$( dirname $SCRIPT )

cd $SCRIPTPATH && git commit -a -m "$1" && git push
