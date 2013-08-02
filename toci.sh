#!/usr/bin/env bash

export TOCI_SOURCE_DIR=$(realpath $(dirname $0))

# setup toci env variables
source $TOCI_SOURCE_DIR/toci-defaults                            # defaults for env variables toci expects
[ -e $TOCI_SOURCE_DIR/tocirc ] && source $TOCI_SOURCE_DIR/tocirc # env variables you may want to setup for this run
[ -e ~/.toci ] && source ~/.toci                                 # your local toci env setup

. $TOCI_SOURCE_DIR/toci_functions.sh

check_dependencies

mkdir -p $TOCI_WORKING_DIR $TOCI_LOG_DIR $TOCI_CACHE_DIR

echo "Starting run $STARTTIME ( $TOCI_WORKING_DIR $TOCI_LOG_DIR )"

# On Exit write relevant toci env to a rc file
trap get_tocienv EXIT

STATUS=0

mark_time Starting git
./toci_git.sh > $TOCI_LOG_DIR/git.out 2>&1 || STATUS=1

# set d-i-b env variables to fetch git repositories from local caches
for repo in $TOCI_WORKING_DIR/*/.git ; do
    repo_dir=$(dirname $repo)
    repo_name=$(basename $repo_dir)
    if [[ "^(tripleo-incubator|bm_poseur|diskimage-builder|tripleo-image-elements|tripleo-heat-templates)$" =~ "$repo_name" ]] ; then
        continue
    fi
    export DIB_REPOLOCATION_$repo_name=$repo_dir
done

mark_time Starting pre-cleanup
./toci_cleanup.sh > $TOCI_LOG_DIR/cleanup.out 2>&1
if [ $STATUS == 0 ] ; then
  mark_time Starting setup
  ./toci_setup.sh > $TOCI_LOG_DIR/setup.out 2>&1 || STATUS=1
fi

if [ $STATUS == 0 ] ; then
    mark_time Starting test
    ./toci_test.sh > $TOCI_LOG_DIR/test.out 2>&1 || STATUS=1
fi

if [ $TOCI_CLEANUP == 1 ] ; then
    mark_time Starting cleanup
    ./toci_cleanup.sh >> $TOCI_LOG_DIR/cleanup.out 2>&1 || STATUS=1
fi

mark_time Finished

if [ $TOCI_UPLOAD == 1 ] ; then
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

if [ $TOCI_REMOVE == 1 ] ; then
    rm -rf $TOCI_WORKING_DIR $TOCI_LOG_DIR
fi

if [ $STATUS != 0 ] ; then
    echo ERROR
fi
exit $STATUS
