#!/bin/bash

set -eux

# Source deploy.env if it exists. It should exist if we are running under
# tripleo-ci
export TRIPLEO_ROOT=${TRIPLEO_ROOT:-"/opt/stack/new"}
if [ -f "$TRIPLEO_ROOT/tripleo-ci/deploy.env" ]; then
    source $TRIPLEO_ROOT/tripleo-ci/deploy.env
fi

# Temporary fix for https://bugs.launchpad.net/tripleo/+bug/1606685
sudo yum erase -y epel-release nodejs nodejs-devel nodejs-packaging || :

# Copied from toci_gate_test.sh...need to apply this fix on subnodes as well
# TODO(pabelanger): Why is python-requests installed from pip?
sudo rm -rf /usr/lib/python2.7/site-packages/requests

# Clear out any puppet modules on the node placed their by infra configuration
sudo rm -rf /etc/puppet/modules/*

# This will remove any puppet configuration done my infra setup
sudo yum -y remove puppet facter hiera

# Update everything
sudo yum -y update
# instack-undercloud will pull in all the needed deps
# git needed since puppet modules installed from source
# openstack-tripleo-common needed for the tripleo-build-images command
sudo yum -y install instack-undercloud git openstack-tripleo-common

export ELEMENTS_PATH="/usr/share/diskimage-builder/elements:/usr/share/instack-undercloud:/usr/share/tripleo-image-elements:/usr/share/tripleo-puppet-elements:/usr/share/openstack-heat-templates/software-config/elements"

export DIB_INSTALLTYPE_puppet_modules=source

sudo yum -y install openstack-tripleo-common

ELEMENTS=$(\
tripleo-build-images \
  --image-json-output \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | map(select(.imagename == "overcloud")) | .[0].elements | map(.+" ") | add' \
  | sed 's/"//g')

# delorean-repo is excluded b/c we've already run --repo-setup on this node and
# we don't want to overwrite that.
sudo -E instack \
  -e centos7 \
     enable-packages-install \
     install-types \
     $ELEMENTS \
  -k extra-data \
     pre-install \
     install \
     post-install \
  -b 05-fstab-rootfs-label \
     00-fix-requiretty \
     90-rebuild-ramdisk \
     00-usr-local-bin-secure-path \
  -x delorean-repo \
  -d

PACKAGES=$(\
tripleo-build-images \
  --image-json-output \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | map(select(.imagename == "overcloud")) | .[0].packages | .[] | tostring' \
  | sed 's/"//g')

# Install additional packages expected by the image
sudo yum -y install $PACKAGES

sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo setenforce 0
