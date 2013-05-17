#!/usr/bin/env bash

. toci_functions.sh

export STARTTIME=$(date)
export TOCI_SOURCE_DIR=$PWD

# All temp files should go here
export TOCI_WORKING_DIR=$(mktemp -d --tmpdir toci_working_XXXXXXX)
# Any files to be uploaded to results server goes here
export TOCI_LOG_DIR=${TOCI_LOG_DIR:-$(mktemp -d --tmpdir toci_logs_XXXXXXX)}
# Files that should be cached between runs should go in here
# e.g. downloaded images, git repo's etc...
export TOCI_CACHE_DIR=/var/tmp/toci_cache

RESULT_CACHE=$TOCI_CACHE_DIR/results_cache.html

echo "Starting run $STARTTIME ($TOCI_WORKING_DIR,$TOCI_LOG_DIR)"

# env specific to this run, can contain
# TOCI_RESULTS_SERVER, http_proxy, TOCI_UPLOAD, TOCI_REMOVE,
source ~/.toci
# If running in cron $USER isn't setup
export USER=${USER:-$(whoami)}

mkdir -p $TOCI_CACHE_DIR

STATUS=0
mark_time Starting setup
timeout --foreground 30m ./toci_setup.sh > $TOCI_LOG_DIR/setup.out 2>&1 || STATUS=1
if [ $STATUS == 0 ] ; then
    mark_time Starting tests
    timeout --foreground 30m ./toci_test.sh > $TOCI_LOG_DIR/test.out 2>&1 || STATUS=1
fi
mark_time Starting cleanup
timeout --foreground 30m ./toci_cleanup.sh > $TOCI_LOG_DIR/cleanup.out 2>&1 || STATUS=1
mark_time Starting finished

if [ ${TOCI_UPLOAD:-0} == 1 ] ; then
    cd $(dirname $TOCI_LOG_DIR)
    tar -czf - $(basename $TOCI_LOG_DIR) | ssh ec2-user@$TOCI_RESULTS_SERVER tar -C /var/www/html/toci -xzf -
    touch $RESULT_CACHE
    mv $RESULT_CACHE result_cache.html.bck
    echo "<html><head/><body>" > index.html
    if [ $STATUS == 0 ] ; then
        echo "<a href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : OK</a\><br/\>" > $RESULT_CACHE
    else
        echo "<a style=\"COLOR: #FF0000\" href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : ERR</a\><br/\>" > $RESULT_CACHE
    fi
    # keep only the last 100 runs
    head -n 100 result_cache.html.bck >> $RESULT_CACHE
    rm result_cache.html.bck
    cat $RESULT_CACHE >> index.html
    echo "</body></html>" >> index.html

    scp index.html ec2-user@$TOCI_RESULTS_SERVER:/var/www/html/toci/index.html
    ssh ec2-user@$TOCI_RESULTS_SERVER "chmod -R 775 /var/www/html/toci/*"

fi

if [ ${TOCI_REMOVE:-1} == 1 ] ; then
    rm -rf $TOCI_WORKING_DIR $TOCI_LOG_DIR
fi

echo $STATUS
