#!/usr/bin/env bash

set -xe
. toci_functions.sh

# install deps on host machine
cd $TOCI_WORKING_DIR/incubator
./scripts/install-dependencies

id | grep libvirt || ( echo "You have been added to the libvirt group, this script will now exit but will succeed if run again in a new shell" ; exit 1 )

# looks like libvirt somtimes takes a little time to start
wait_for 3 3 ls /var/run/libvirt/libvirt-sock

cd $TOCI_WORKING_DIR/bm_poseur
sudo ./bm_poseur --bridge-ip=none create-bridge || true

if [ -f /etc/init.d/libvirt-bin ]; then
  sudo service libvirt-bin restart
else
  sudo service libvirtd restart
fi

cd $TOCI_WORKING_DIR/incubator
sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/boot-stack/config.json
ELEMENTS_PATH=$TOCI_WORKING_DIR/tripleo-image-elements/elements \
DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder \
    scripts/boot-elements boot-stack -o bootstrap

cd $TOCI_WORKING_DIR
export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements
./diskimage-builder/bin/disk-image-create -u -a i386 -o $TOCI_WORKING_DIR/incubator/notcompute stackuser boot-stack heat-cfntools quantum-network-node
./diskimage-builder/bin/disk-image-create -u -a i386 -o $TOCI_WORKING_DIR/incubator/compute stackuser nova-compute heat-cfntools

cd $TOCI_WORKING_DIR/incubator
BOOTSTRAP_IP=`scripts/get-vm-ip bootstrap`

# Get logs from the node on error
trap get_state_from_host ERR

# We're going to wait for it to finish firstboot
wait_for 60 10 ssh_noprompt root@$BOOTSTRAP_IP ls /opt/stack/boot-stack/boot-stack.done

