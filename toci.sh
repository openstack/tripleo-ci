#!/usr/bin/env bash

. toci_functions.sh

export STARTTIME=$(date)
export TOCI_SOURCE_DIR=$PWD

# env specific to this run, can contain
# TOCI_RESULTS_SERVER, http_proxy, TOCI_UPLOAD, TOCI_REMOVE,
source ~/.toci

export TOCI_GIT_CHECKOUT

# All temp files should go here
export TOCI_WORKING_DIR=${TOCI_WORKING_DIR:-$(mktemp -d --tmpdir toci_working_XXXXXXX)}
mkdir -p $TOCI_WORKING_DIR
# Any files to be uploaded to results server goes here
export TOCI_LOG_DIR=${TOCI_LOG_DIR:-$(mktemp -d --tmpdir toci_logs_XXXXXXX)}
mkdir -p $TOCI_LOG_DIR
# Files that should be cached between runs should go in here
# e.g. downloaded images, git repo's etc...
export TOCI_CACHE_DIR=/var/tmp/toci_cache

export TOCI_ARCH=${TOCI_ARCH:-'i686'}
export TOCI_DIB_ARCH='i386'
if [ "$TOCI_ARCH" == 'x86_64' ]; then
  export TOCI_DIB_ARCH='amd64'
fi

export TOCI_DISTROELEMENT=${TOCI_DISTROELEMENT:-'fedora disable-selinux'}

RESULT_CACHE=$TOCI_CACHE_DIR/results_cache.html

echo "Starting run $STARTTIME ( $TOCI_WORKING_DIR $TOCI_LOG_DIR )"

# If running in cron $USER isn't setup
export USER=${USER:-$(whoami)}

mkdir -p $TOCI_CACHE_DIR

STATUS=0

mark_time Starting git
timeout --foreground 60m ./toci_git.sh > $TOCI_LOG_DIR/git.out 2>&1 || STATUS=1

# Add incubator scripts to path
export PATH=$PATH:$TOCI_WORKING_DIR/incubator/scripts

if [ $STATUS == 0 ] ; then
  mark_time Starting setup
  timeout --foreground 60m ./toci_setup.sh > $TOCI_LOG_DIR/setup.out 2>&1 || STATUS=1
fi
if [ $STATUS == 0 ] ; then
    mark_time Starting test
    timeout --foreground 60m ./toci_test.sh > $TOCI_LOG_DIR/test.out 2>&1 || STATUS=1
fi
if [ ${TOCI_CLEANUP:-1} == 1 ] ; then
    mark_time Starting cleanup
    timeout --foreground 60m ./toci_cleanup.sh > $TOCI_LOG_DIR/cleanup.out 2>&1 || STATUS=1
fi
mark_time Finished

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

    # Send a irc message
    if [ -n "$TOCI_IRC" -a $STATUS != 0 ] ; then
        send_irc $TOCI_IRC ERROR during toci run, see http://$TOCI_RESULTS_SERVER/toci/$(basename $TOCI_LOG_DIR)/
    fi

if [ ${TOCI_REMOVE:-1} == 1 ] ; then
    rm -rf $TOCI_WORKING_DIR $TOCI_LOG_DIR
fi

declare | grep -e "^PATH=" -e "^http.*proxy" -e "^TOCI_" -e '^DIB_' | sed  -e 's/^/export /g' > $TOCI_WORKING_DIR/toci_env
echo $STATUS
exit $STATUS
