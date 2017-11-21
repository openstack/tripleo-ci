#!/bin/bash

set -eux

export STABLE_RELEASE=${STABLE_RELEASE:-""}

# Source deploy.env if it exists. It should exist if we are running under
# tripleo-ci
export TRIPLEO_ROOT=${TRIPLEO_ROOT:-"/opt/stack/new"}
if [ -f "$TRIPLEO_ROOT/tripleo-ci/deploy.env" ]; then
    source $TRIPLEO_ROOT/tripleo-ci/deploy.env
fi

if [[ -e /etc/unbound/conf.d/unbound-logging.conf ]]; then
    sudo sed -i "s/verbosity: .*$/verbosity: 5/g" /etc/unbound/conf.d/unbound-logging.conf
    sudo systemctl restart unbound
fi

# Ensure epel-release is not installed
sudo yum erase -y epel-release || :

# Copied from toci_gate_test.sh...need to apply this fix on subnodes as well
# TODO(pabelanger): Why is python-requests installed from pip?
# TODO(amoralej): remove after https://review.openstack.org/#/c/468872/ is merged
sudo pip uninstall certifi -y || true
sudo pip uninstall urllib3 -y || true
sudo pip uninstall requests -y || true
sudo rpm -e --nodeps python2-certifi || :
sudo rpm -e --nodeps python2-urllib3 || :
sudo rpm -e --nodeps python2-requests || :
sudo yum -y install python-requests python-urllib3

# Clear out any puppet modules on the node placed their by infra configuration
sudo rm -rf /etc/puppet/modules/*

# This will remove any puppet configuration done my infra setup
sudo yum -y remove puppet facter hiera

# Update everything
sudo yum -y update

# git is needed since oooq multinode jobs does a git clone
# See https://bugs.launchpad.net/tripleo-quickstart/+bug/1667043
sudo yum -y install git python-heat-agent*

# create a loop device for ceph-ansible
# device name is static so we know what to point to from ceph-ansible
# job names might change, but multinode implies ceph as per scenario001-multinode.yaml
if [[ "${TOCI_JOBTYPE:-''}" =~ multinode ]]; then
    if [[ ! -e /dev/loop3 ]]; then # ensure /dev/loop3 does not exist before making it
        command -v losetup >/dev/null 2>&1 || { sudo yum -y install util-linux; }
        sudo dd if=/dev/zero of=/var/lib/ceph-osd.img bs=1 count=0 seek=7G
        sudo losetup /dev/loop3 /var/lib/ceph-osd.img
    else
        echo "ERROR: /dev/loop3 already exists, not using it with losetup"
        exit 1
    fi
    sudo lsblk
fi
