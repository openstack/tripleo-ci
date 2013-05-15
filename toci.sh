#!/usr/bin/env bash

export STARTTIME=$(date)
export TOCI_SOURCE_DIR=$PWD

# All temp files should go here
export TOCI_WORKING_DIR=$(mktemp -d --tmpdir toci_working_XXXXXXX)
# Any files to be uploaded to results server goes here
export TOCI_LOG_DIR=$(mktemp -d --tmpdir toci_logs_XXXXXXX)
# Files that should be cached between runs should go in here
# e.g. downloaded images, git repo's etc...
export TOCI_CACHE_DIR=/var/tmp/toci_cache


echo "Starting run $STARTTIME ($TOCI_WORKING_DIR,$TOCI_LOG_DIR)"

# env specific to this run, can contain
# TOCI_RESULTS_SERVER, http_proxy, TOCI_UPLOAD, TOCI_REMOVE,
source ~/.toci
# If running in cron $USER isn't setup
export USER=${USER:-$(whoami)}

mkdir -p $TOCI_CACHE_DIR

STATUS=0
./toci_setup.sh > $TOCI_LOG_DIR/setup.out 2>&1 || STATUS=1
if [ $STATUS == 0 ] ; then
    ./toci_test.sh > $TOCI_LOG_DIR/test.out 2>&1 || STATUS=1
fi
./toci_cleanup.sh > $TOCI_LOG_DIR/cleanup.out 2>&1 || STATUS=1

if [ ${TOCI_UPLOAD:-0} == 1 ] ; then
    cd $(dirname $TOCI_LOG_DIR)
    tar -czf - $(basename $TOCI_LOG_DIR) | ssh ec2-user@$TOCI_RESULTS_SERVER tar -C /var/www/html/toci -xzf -
    if [ $STATUS == 0 ] ; then
        ssh ec2-user@$TOCI_RESULTS_SERVER "echo \<a href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : OK\</a\>\<br/\> >> /var/www/html/toci/index.html ; chmod -R 775 /var/www/html/toci/*"
    else
        ssh ec2-user@$TOCI_RESULTS_SERVER "echo \<a style=\\\"COLOR: \#FF0000\\\" href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : ERR\</a\>\<br/\> >> /var/www/html/toci/index.html ; chmod -R 775 /var/www/html/toci/*"
    fi
fi

if [ ${TOCI_REMOVE:-1} == 1 ] ; then
    rm -rf $TOCI_WORKING_DIR $TOCI_LOG_DIR
fi
