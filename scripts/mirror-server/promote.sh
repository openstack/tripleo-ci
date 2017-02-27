#!/bin/bash
set -ex

# Here be the promote script
# 1. Find all metadata files newer then the one currently promoted
# 2. If any of them have all the jobs reported back that we're interested in then promote it
#    o Bumb current-tripleo on the dlrn server
#    o Bump current-tripleo on this server
# ./promote.sh release linkname promote-jobname test-jobname [test-jobname] ...

RELEASE=$1
LINKNAME=$2
PROMOTE_JOBNAME=$3

BASEDIR=/var/www/html/builds-$RELEASE
CURRENT=$BASEDIR/$LINKNAME
CURRENT_META=$CURRENT/metadata.txt
JOB_URL=https://ci.centos.org/job/$PROMOTE_JOBNAME/buildWithParameters

shift
shift
shift

# Working with relative paths is easier as we need to set relative links on the dlrn server
pushd $BASEDIR

mkdir -p $CURRENT

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
    break
done

# Remove any files older then 1 day that arn't one of the current pins
find */*/* -type f -name metadata.txt -mtime +0 \
    -not -samefile $LINKNAME/metadata.txt | \
    xargs --no-run-if-empty dirname | \
    xargs --no-run-if-empty -t rm -rf
# Remove all empty nested directories
find . -type d -empty -delete

popd
