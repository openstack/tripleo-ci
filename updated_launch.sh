#!/usr/bin/env bash

. toci_functions.sh

LOCKFILE=/var/tmp/toci.lock
GITREF=${1:-origin/master}

export TOCI_LOG_DIR=${TOCI_LOG_DIR:-$(mktemp -d --tmpdir toci_logs_XXXXXXX)}
RUNLOG=$TOCI_LOG_DIR/run.out

cd $(dirname $0)
git fetch origin | tee -a $RUNLOG 2>&1

# Exit if there is a script already running, otherwise update repo
# TODO : fix small race condition here (probably not a problem)
flock -x -n $LOCKFILE git reset --hard $GITREF | tee -a $RUNLOG 2>&1 || exit 0
flock -x -n $LOCKFILE ./toci.sh  | tee -a $RUNLOG 2>&1

