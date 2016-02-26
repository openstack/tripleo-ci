#!/bin/bash

# bootstrap a tripleo-ci infrastructure server, this selects which puppet manifest
# to run based on the hostname e.g. to create a mirror server then one can simply
# nova boot --image <id> --flavor <id> --user-data scripts/deploy-server.sh --nic net-id=<id> --nic net-id=<id>,v4-fixed-ip=192.168.1.101 mirror-server


yum install -y puppet git

echo puppetlabs-apache adrien-filemapper | xargs -n 1 sudo puppet module install

sudo git clone https://github.com/puppetlabs/puppetlabs-vcsrepo.git /etc/puppet/modules/vcsrepo

if [ -e /sys/class/net/eth1 ] ; then
     echo -e 'DEVICE=eth1\nBOOTPROTO=dhcp\nONBOOT=yes\nPERSISTENT_DHCLIENT=yes\nPEERDNS=no' > /etc/sysconfig/network-scripts/ifcfg-eth1
     ifdown eth1
     ifup eth1
fi

curl http://git.openstack.org/cgit/openstack-infra/tripleo-ci/plain/scripts/$(hostname)/$(hostname).pp | puppet apply
