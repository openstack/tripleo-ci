#!/usr/bin/env bash

set -eu

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# We are currently running a Squid proxy on 192.168.1.100 in both Racks
# and the geard server on 192.168.1.1
export http_proxy=http://192.168.1.100:3128/
export GEARDSERVER=192.168.1.1

# tripleo ci default control variables
export DIB_COMMON_ELEMENTS="common-venv stackuser pypi-openstack"
export OVERCLOUD_CONTROLSCALE=1
export TRIPLEO_TEST=overcloud
export USE_IRONIC=1
export USE_CIRROS=1

# Switch defaults based on the job name
for JOB_NAME_PART in $(sed 's/-/ /g' <<< $JOB_NAME) ; do
    case $JOB_NAME_PART in
        novabm)     export USE_IRONIC=0 ;;
        ha)         export OVERCLOUD_CONTROLSCALE=3 ;;
        undercloud) export TRIPLEO_TEST=undercloud ;;
        vlan)       export TRIPLEO_TEST=vlan ;;
    esac
done

# print the final values of control variables to console
env | grep -E "(DIB_COMMON_ELEMENTS|OVERCLOUD_CONTROLSCALE|TRIPLEO_TEST|USE_IRONIC|USE_CIRROS)="

# This allows communication between tripleo jumphost and the CI host running
# the devtest_seed configuration
sudo iptables -I INPUT -p tcp --dport 27410 -i eth1 -j ACCEPT

# Download a custom Fedora image here. We want to use an explit URL
# so that Squid caches this. I'm doing it here to test things for now...
# Once it works this code actually belongs in prepare_node_tripleo.sh
# in openstack-infra/config so the Slave node will essentially pre-cache
# it for us.
DISTRIB_CODENAME=$(lsb_release -si)
if [ $DISTRIB_CODENAME == 'Fedora' ]; then
    # TODO : This should read the ARCH of the test being targeted
    FEDORA_IMAGE=$(wget -q http://dl.fedoraproject.org/pub/fedora/linux/updates/20/Images/i386/ -O - | grep -o -E 'href="([^"#]+qcow2)"' | cut -d'"' -f2)
    wget --progress=dot:mega http://dl.fedoraproject.org/pub/fedora/linux/updates/20/Images/i386/$FEDORA_IMAGE
    export DIB_LOCAL_IMAGE=$PWD/$FEDORA_IMAGE
fi

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
set -m
./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_devtest.sh
