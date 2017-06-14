#!/bin/bash

set -eux

export STABLE_RELEASE=${STABLE_RELEASE:-""}

# Source deploy.env if it exists. It should exist if we are running under
# tripleo-ci
export TRIPLEO_ROOT=${TRIPLEO_ROOT:-"/opt/stack/new"}
if [ -f "$TRIPLEO_ROOT/tripleo-ci/deploy.env" ]; then
    source $TRIPLEO_ROOT/tripleo-ci/deploy.env
fi

# Ensure epel-release is not installed
sudo yum erase -y epel-release || :

# Copied from toci_gate_test.sh...need to apply this fix on subnodes as well
# TODO(pabelanger): Why is python-requests installed from pip?
# Reinstall python-requests if it was already installed, otherwise it will be
# installed later when other packages are installed.
# TODO(amoralej): remove after https://review.openstack.org/#/c/468872/ is merged
sudo pip uninstall certifi -y || true
sudo pip uninstall urllib3 -y || true
sudo pip uninstall requests -y || true
sudo rpm -e --nodeps python2-certifi || :
sudo rpm -e --nodeps python2-urllib3 || :
sudo rpm -e --nodeps python2-requests || :
sudo yum -y install python-requests python-urllib3


# Remove the anything on the infra image template that might interfere with CI
# Note for tripleo-quickstart: this task is already managed in tripleo-ci-setup-playbook.yml
sudo yum remove -y facter puppet hiera puppetlabs-release rdo-release centos-release-[a-z]*
sudo rm -rf /etc/puppet /etc/hiera.yaml

# Update everything
sudo yum -y update
# instack-undercloud will pull in all the needed deps
# git needed since puppet modules installed from source
# openstack-tripleo-common needed for the tripleo-build-images command
sudo yum -y install instack-undercloud git openstack-tripleo-common

# detect the real path depending on diskimage-builder version
COMMON_ELEMENTS_PATH=$(python -c '
try:
    import diskimage_builder.paths
    diskimage_builder.paths.show_path("elements")
except:
    print("/usr/share/diskimage-builder/elements")
')
export ELEMENTS_PATH="${COMMON_ELEMENTS_PATH}:/usr/share/instack-undercloud:/usr/share/tripleo-image-elements:/usr/share/tripleo-puppet-elements"

if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
ELEMENTS=$(\
tripleo-build-images \
  --image-json-output \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | map(select(.imagename == "overcloud-full")) | .[0].elements | map(.+" ") | add' \
  | sed 's/"//g')
else
ELEMENTS=$(\
tripleo-build-images \
  --image-json-output \
  --image-name overcloud-full \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | .[0].elements | map(.+" ") | add' \
  | sed 's/"//g')
fi


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

if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
PACKAGES=$(\
tripleo-build-images \
  --image-json-output \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | map(select(.imagename == "overcloud-full")) | .[0].packages | .[] | tostring' \
  | sed 's/"//g')
else
PACKAGES=$(\
tripleo-build-images \
  --image-json-output \
  --image-name overcloud-full \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images-centos7.yaml \
  --image-config-file /usr/share/tripleo-common/image-yaml/overcloud-images.yaml \
  | jq '. | .[0].packages | .[] | tostring' \
  | sed 's/"//g')
fi

# Install additional packages expected by the image
sudo yum -y install $PACKAGES

sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo setenforce 0
