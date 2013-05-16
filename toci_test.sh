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

sudo $TOCI_WORKING_DIR/tripleo_bm_poseur/bm_poseur --vms 1 --arch i686 create-vm
MAC=`$TOCI_WORKING_DIR/tripleo_bm_poseur/bm_poseur get-macs`

nova keypair-add --pub-key ~/.ssh/id_rsa.pub default
nova baremetal-node-create ubuntu 1 512 10 $MAC

for x in {0..30} ; do
  ssh_noprompt root@$BOOTSTRAP_IP grep 'Free VCPUS: 1' /var/log/upstart/nova-compute.log  && break || true
  sleep 10
done
