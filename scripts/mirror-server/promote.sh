#!/bin/bash -ex

# Here be the promote script
# 1. Find all metadata files newer then the one currently promoted
# 2. If any of them have all the jobs reported back that we're interested in then promote it
#    o Bumb current-tripleo on the dlrn server
#    o Bump current-tripleo on this server
# ./promote.sh linkname jobname [jobname] ...

# Yes this doesn't attempt to remove anything, that will be a exercise for later

BASEDIR=/var/www/html/builds
CURRENT=$BASEDIR/$1
CURRENT_META=$BASEDIR/current-tripleo/metadata.txt
JOB_URL=https://ci.centos.org/job/tripleo-dlrn-promote/buildWithParameters

shift

# Working with relative paths is easier as we need to set relative links on the dlrn server
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
    #(trown) Do not echo the curl command so we can keep the RDO_PROMOTE_TOKEN
    # relatively secret. The token only provides access to promote the current-tripleo
    # symlink, and is easy to change, but better to not advertise it in the logs.
    set +x
    source ~/.promoterc
    curl $JOB_URL?token=$RDO_PROMOTE_TOKEN\&tripleo_dlrn_promote_hash=$(basename $DIR)
    set -x
    ln -snf $DIR $CURRENT
    # OVB based CI jobs no longer create a instack image, keep an old one in place until quickstart uses overcloud-full instead
    cp /var/www/html/builds/current-tripleo-20160630/instack.qcow2* /var/www/html/builds/current-tripleo/
    break
done
