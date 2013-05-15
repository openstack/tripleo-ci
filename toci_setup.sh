#!/usr/bin/env bash

set -xe
. toci_functions.sh

# Get the tripleO repo's
for repo in 'tripleo/incubator' 'tripleo/bm_poseur' 'stackforge/diskimage-builder' 'stackforge/tripleo-image-elements' ; do
    get_get_repo $repo
done

# install deps on host machine
cd $TOCI_WORKING_DIR/tripleo_incubator
./scripts/install-dependencies

