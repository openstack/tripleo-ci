#!/usr/bin/env bash

set -xe
. toci_functions.sh

# Get the tripleO repo's
for repo in 'tripleo/incubator' 'tripleo/bm_poseur' 'stackforge/diskimage-builder' 'stackforge/tripleo-image-elements' ; do
    get_get_repo $repo
done

cd $TOCI_WORKING_DIR/tripleo_incubator
# patches can be added to git repo's like this, this just a temp measure we need to make faster progress
# until we get up and runing properly
for PATCH in $TOCI_SOURCE_DIR/patches/incubator* ; do
    git am $PATCH
done

# install deps on host machine
./scripts/install-dependencies

id | grep libvirt || ( echo "You have been added to the libvirt group, this script will now exit but will succeed if run again in a new shell" ; exit 1 )

cd $TOCI_WORKING_DIR/tripleo_bm_poseur
sudo ./bm_poseur --bridge-ip=none create-bridge
sudo service libvirt-bin restart

cd $TOCI_WORKING_DIR/stackforge_diskimage-builder/
bin/disk-image-create -u base -a i386 -o $TOCI_WORKING_DIR/tripleo_incubator/base


cd $TOCI_WORKING_DIR/tripleo_incubator
ELEMENTS_PATH=$TOCI_WORKING_DIR/stackforge_tripleo-image-elements/elements DIB_PATH=$TOCI_WORKING_DIR/stackforge_diskimage-builder scripts/boot-elements boot-stack -o bootstrap
