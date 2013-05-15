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

