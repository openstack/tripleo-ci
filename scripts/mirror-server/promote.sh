#!/bin/bash -ex

# Here be the promote script
# 1. Find all metadata files newer then the one currently promoted
# 2. If any of them have all the jobs reported back that we're interested in then promote it
#    o Bumb current-tripleo on the delorean server
#    o Bump current-tripleo on this server
# ./promote.sh linkname jobname [jobname] ...

# Yes this doesn't attempt to remove anything, that will be a exercise for later

BASEDIR=/var/www/html/builds
CURRENT=$BASEDIR/$1
CURRENT_META=$BASEDIR/current-tripleo/metadata.txt

shift

# Working with reletive paths is easier as we need to set reletive links on the delorean server
cd $BASEDIR

if [ -f $CURRENT_META ] ; then
    DIRS2TEST=$(find . -newer $CURRENT_META -name metadata.txt | xargs --no-run-if-empty ls -t)
else
    # We haven't had a successful promote yet, check the last 7 days for a success
    DIRS2TEST=$(find . -mtime -7 -name metadata.txt | xargs --no-run-if-empty ls -t)
fi
[ -z "$DIRS2TEST" ] && exit 0

for DIR in $DIRS2TEST ; do
    OK=0
    for JOB in $@ ; do
        grep "$JOB=SUCCESS" $DIR || OK=1
    done
    [ $OK == 1 ] && continue

    DIR=$(dirname $DIR)
    ssh -t -o StrictHostKeyChecking=no -p 3300 promoter@trunk.rdoproject.org sudo /usr/local/bin/promote.sh $(basename $DIR) centos-master current-tripleo
    ln -snf $DIR $CURRENT
    break
done
