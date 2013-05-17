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

# Load the base image into glance
export DIB_PATH=$TOCI_WORKING_DIR/stackforge_diskimage-builder
./scripts/load-image base.qcow2

# place the bootstrap public key on host so that it can admin virt
ssh_noprompt root@$BOOTSTRAP_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

# Now we have to wait for the bm poseur to appear on the compute node and for the compute node to then
# update the scheduler
wait_for 20 10 ssh_noprompt root@$BOOTSTRAP_IP grep \'record updated for\' /var/log/upstart/nova-compute.log -A 100 \| grep \'Updating host status\'

# I've tried all kinds of things to wait for before doing the nova boot and can't find a reliable combination,
# I suspect I need to watch the scheduler and compute log to follow a chain of events,
# but for now I'm tired so I'm going to
sleep 67

nova boot --flavor 256 --image base --key_name default bmtest

# ping the node TODO : make this more readable and output less errors
wait_for 20 10 ssh_noprompt root@$BOOTSTRAP_IP 'source ~/stackrc ; ping -c 1 $(nova list | grep ctlplane | sed -e "s/.*=\(.*\) .*/\1/g")'
