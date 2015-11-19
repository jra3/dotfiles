#!/bin/sh

SCRIPT=$( readlink -e $0 )
SCRIPTPATH=$( dirname $SCRIPT )

cd $SCRIPTPATH && git pull && $SCRIPTPATH/install.sh
