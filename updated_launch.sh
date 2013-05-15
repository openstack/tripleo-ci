#!/usr/bin/env bash

LOCKFILE=/var/tmp/toci.lock
GITREF=${1:-origin/master}

cd $(dirname $0)
git fetch origin

# Exit if there is a script already running, otherwise update repo
# TODO : fix small race condition here (probably not a problem)
flock -x -n $LOCKFILE git reset --hard $GITREF || exit 0
flock -x -n $LOCKFILE ./toci.sh

