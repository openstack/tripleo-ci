#!/usr/bin/env bash

set -e

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# Enable precise-backports so we can install jq
sudo sed -i -e 's/# \(deb .*precise-backports main \)/\1/g' /etc/apt/sources.list
sudo apt-get update
# TODO : remove these when the equivalent merges into openstack-infra/config
sudo DEBIAN_FRONTEND=noninteractive apt-get \
  --option "Dpkg::Options::=--force-confold" \
  --assume-yes install python-pip libffi-dev
sudo pip install gear os-apply-config

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

./testenv-client -b $GEARDSERVER:4730 -- ./toci_devtest.sh
