#!/bin/bash

# Keep X number of testenv workers running, each testenv worker exists after processing a single job
BASEPATH=$(realpath $(dirname $0)/../..)
ENVFILE=$BASEPATH/scripts/rh2.env


TENUM=0
while true ; do
    NUMCURRENTJOBS=$(jobs -p -r | wc -l)
    source $ENVFILE
    if [ $NUMCURRENTJOBS -lt $TOTALOVBENVS ] ; then
        TENUM=$(($TENUM+1))
        echo "Starting testenv-worker $TENUM"
        python $BASEPATH/scripts/te-broker/testenv-worker --tenum $TENUM $BASEPATH/scripts/te-broker/create-env $BASEPATH/scripts/te-broker/destroy-env &
    fi
    # Trottle a little so we don't end up hitting the openstack APIs too hard
    sleep 10
done
