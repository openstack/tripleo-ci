#!/usr/bin/env bash

set -xe
. toci_functions.sh

# Get the tripleO repo's
for repo in 'tripleo/incubator' 'tripleo/bm_poseur' 'stackforge/diskimage-builder' 'stackforge/tripleo-image-elements' 'stackforge/tripleo-heat-templates' ; do
    if [ ${TOCI_GIT_CHECKOUT:-1} == 1 ] ; then
      get_get_repo $repo
    else
      if [ ! -d "$TOCI_WORK_DIR/$repo" ]; then
        echo "Please checkout $repo to $TOCI_WORK_DIR or enabled TOCI_GIT_CHECKOUT."
      fi
    fi
done

#only patch if we do the git checkout
if [ ${TOCI_GIT_CHECKOUT:-1} == 1 ] ; then
  # patches can be added to git repo's like this, this just a temp measure we need to make faster progress
  # until we get up and runing properly
  apply_patches incubator incubator*
  apply_patches bm_poseur bm_poseur*
  apply_patches diskimage-builder diskimage-builder*
  apply_patches tripleo-image-elements tripleo-image-elements*
  apply_patches tripleo-heat-templates tripleo-heat-templates*
fi
