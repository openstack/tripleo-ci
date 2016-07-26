#!/bin/bash

# taken from openstack-virtual-baremetal/bin/install_openstackbmc.sh
yum -y update centos-release # required for rdo-release install to work
yum install -y https://rdo.fedorapeople.org/rdo-release.rpm
yum install -y python-pip python-crypto os-net-config python-novaclient python-neutronclient git jq
pip install pyghmi

# the CI cloud is using a unsafe disk caching mode, so this sync will be ignored by the host
# we're syncing data on the VM, then give the host 5 seconds to write it to disk and hope its long enough
sync
sleep 5

touch /var/tmp/ready
