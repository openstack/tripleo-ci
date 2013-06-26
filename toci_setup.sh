#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR

# install deps on host machine
install-dependencies
setup-network

id | grep libvirt || ( echo "You have been added to the libvirt group, this script will now exit but will succeed if run again in a new shell" ; exit 1 )

# looks like libvirt somtimes takes a little time to start
wait_for 3 3 ls /var/run/libvirt/libvirt-sock

sudo $TOCI_WORKING_DIR/bm_poseur/bm_poseur --bridge-ip=none create-bridge || true

if [ -f /etc/init.d/libvirt-bin ]; then
  sudo service libvirt-bin restart
else
  sudo service libvirtd restart
fi

# set default arch for flavors in boot-stack
if [ "$TOCI_ARCH" != "i386" ]; then
  sed -i "s/\"arch\":.*,/\"arch\": \"$TOCI_ARCH\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/boot-stack/config.json
fi

# custom power driver config
if [ -n "$TOCI_PM_DRIVER" ]; then
  sed -i "s/\"power_manager\":.*,/\"power_manager\": \"$TOCI_PM_DRIVER\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/boot-stack/config.json
fi

sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/boot-stack/config.json
ELEMENTS_PATH=$TOCI_WORKING_DIR/tripleo-image-elements/elements \
DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder \
    $TOCI_WORKING_DIR/incubator/scripts/boot-elements boot-stack -o seed -a "$TOCI_DIB_ARCH"

export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements
$TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -u -a $TOCI_DIB_ARCH -o $TOCI_WORKING_DIR/notcompute stackuser boot-stack heat-cfntools quantum-network-node
$TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -u -a $TOCI_DIB_ARCH -o $TOCI_WORKING_DIR/compute stackuser nova-compute heat-cfntools quantum-openvswitch-agent

BOOTSTRAP_IP=`$TOCI_WORKING_DIR/incubator/scripts/get-vm-ip seed`

export no_proxy=$no_proxy,$SEED_IP

# Get logs from the node on error
trap get_state_from_host ERR

# We're going to wait for it to finish firstboot
wait_for 60 10 ssh_noprompt root@$BOOTSTRAP_IP ls /opt/stack/boot-stack/boot-stack.done

