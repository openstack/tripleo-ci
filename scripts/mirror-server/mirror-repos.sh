#!/bin/bash
set -eu

IFS=$'\n'

BASEDIR=$(dirname $0)

REPODIR=/var/www/html/repos

mkdir -p $REPODIR

for REPO in $(cat $BASEDIR/mirrored.list | grep -v "^#"); do
    echo "Processing $REPO"
    RDIR=${REPO%% *}
    RURL=${REPO##* }
    if ! [ -e $REPODIR/$RDIR ] ; then
        git clone --mirror $RURL $REPODIR/$RDIR
    fi

    cd $REPODIR/$RDIR
    git fetch
    git update-server-info
done
