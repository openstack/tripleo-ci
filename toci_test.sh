#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR/tripleo_incubator
BOOTSTRAP_IP=`scripts/get-vm-ip bootstrap`

scp_noprompt root@$BOOTSTRAP_IP:stackrc $TOCI_WORKING_DIR/stackrc
sed -i "s/localhost/$BOOTSTRAP_IP/" $TOCI_WORKING_DIR/stackrc
source $TOCI_WORKING_DIR/stackrc

unset http_proxy
nova list
