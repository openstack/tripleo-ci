#!/usr/bin/env bash

set -xe
. toci_functions.sh

# Get the tripleO repo's
for repo in 'tripleo/incubator' 'tripleo/bm_poseur' 'stackforge/diskimage-builder' 'stackforge/tripleo-image-elements' ; do
    get_get_repo $repo
done

# patches can be added to git repo's like this, this just a temp measure we need to make faster progress
# until we get up and runing properly
apply_patches tripleo_incubator incubator*
apply_patches tripleo_bm_poseur bm_poseur*
apply_patches stackforge_diskimage-builder diskimage-builder*
apply_patches stackforge_tripleo-image-elements tripleo-image-elements*

# install deps on host machine
cd $TOCI_WORKING_DIR/tripleo_incubator
./scripts/install-dependencies

id | grep libvirt || ( echo "You have been added to the libvirt group, this script will now exit but will succeed if run again in a new shell" ; exit 1 )

# looks like libvirt somtimes takes a little time to start
wait_for 3 3 ls /var/run/libvirt/libvirt-sock

cd $TOCI_WORKING_DIR/tripleo_bm_poseur
sudo ./bm_poseur --bridge-ip=none create-bridge
sudo service libvirt-bin restart

cd $TOCI_WORKING_DIR/stackforge_diskimage-builder/
bin/disk-image-create -u base -a i386 -o $TOCI_WORKING_DIR/tripleo_incubator/base


cd $TOCI_WORKING_DIR/tripleo_incubator
sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" $TOCI_WORKING_DIR/stackforge_tripleo-image-elements/elements/boot-stack/config.json
ELEMENTS_PATH=$TOCI_WORKING_DIR/stackforge_tripleo-image-elements/elements \
DIB_PATH=$TOCI_WORKING_DIR/stackforge_diskimage-builder \
    scripts/boot-elements boot-stack -o bootstrap

BOOTSTRAP_IP=`scripts/get-vm-ip bootstrap`
# We're going to wait for it to finish firstboot
wait_for 30 10 ssh_noprompt root@$BOOTSTRAP_IP ls /opt/stack/boot-stack/boot-stack.done

