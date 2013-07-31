#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR

# Were going to cache images here
mkdir -p $TOCI_WORKING_DIR/image_cache

# install deps on host machine, this script also restarts libvirt so we have to wait for it to be ready
install-dependencies
wait_for 3 3 ls /var/run/libvirt/libvirt-sock

setup-network

id | grep libvirt || ( echo "You have been added to the libvirt group, this script will now exit but will succeed if run again in a new shell" ; exit 1 )

if [ -f /etc/init.d/libvirt-bin ]; then
  sudo service libvirt-bin restart
else
  sudo service libvirtd restart
fi

# set default arch for flavors in boot-stack
if [ "$TOCI_ARCH" != "i386" ]; then
  sed -i "s/\"arch\":.*,/\"arch\": \"$TOCI_ARCH\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/seed-stack-config/config.json
fi

# custom power driver config
if [ -n "$TOCI_PM_DRIVER" ]; then
  sed -i "s/\"power_manager\":.*,/\"power_manager\": \"$TOCI_PM_DRIVER\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/seed-stack-config/config.json
fi

sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" $TOCI_WORKING_DIR/tripleo-image-elements/elements/seed-stack-config/config.json

# Create a deployment ramdisk + kernel
#$TOCI_WORKING_DIR/diskimage-builder/bin/ramdisk-image-create -x -a $TOCI_DIB_ARCH $TOCI_DISTROELEMENT deploy -o deploy-ramdisk
$TOCI_WORKING_DIR/diskimage-builder/bin/ramdisk-image-create -x -a $TOCI_DIB_ARCH ubuntu deploy -o deploy-ramdisk


# If using Fedora keep using F18 for now
if [[ "$TOCI_DISTROELEMENT" =~ fedora ]] ; then
    export DIB_CLOUD_IMAGES=http://mattdm.fedorapeople.org/cloud-images
    export DIB_RELEASE=Fedora18
    export BASE_IMAGE_FILE=Fedora18-Cloud-$TOCI_ARCH-latest.qcow2
fi

# Boot a seed vm
EXTRA_ELEMENTS=$TOCI_DISTROELEMENT $TOCI_WORKING_DIR/tripleo-incubator/scripts/boot-seed-vm

# Make the tripleo image elements accessible to diskimage-builder
export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements

$TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -a $TOCI_DIB_ARCH -o $TOCI_WORKING_DIR/undercloud $TOCI_DISTROELEMENT boot-stack nova-baremetal heat-localip heat-cfntools stackuser
