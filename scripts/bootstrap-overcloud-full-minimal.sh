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
sudo rm -rf /usr/lib/python2.7/site-packages/requests /usr/lib/python2.7/site-packages/urllib3
sudo rpm -e --nodeps python-requests python-urllib3 || :
sudo rpm -e --nodeps python2-requests python2-urllib3 || :
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
