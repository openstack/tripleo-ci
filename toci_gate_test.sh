#!/usr/bin/env bash

set -eu

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# Once rh1 migrates to the 172.16.0.0/22 network we can remove the
# 192.168.1.0/24 entries
export http_proxy=http://192.168.1.100:3128/
export GEARDSERVER=192.168.1.1
export PYPIMIRROR=192.168.1.101
# TODO : make this the default once rh1 has switched over
if [[ $NODE_NAME =~ .*tripleo-test-cloud-hp1* ]] ; then
    export http_proxy=http://172.16.3.253:3128/
    export GEARDSERVER=172.16.3.254
    export PYPIMIRROR=172.16.3.252
fi

# tripleo ci default control variables
export DIB_COMMON_ELEMENTS="common-venv stackuser"
export TRIPLEO_TEST=${TRIPLEO_TEST:-"overcloud"}
export USE_CIRROS=${USE_CIRROS:-"1"}
export OVERCLOUD_CONTROLSCALE=${OVERCLOUD_CONTROLSCALE:-"1"}
export TRIPLEO_DEBUG=${TRIPLEO_DEBUG:-""}

# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        undercloud)
            export TRIPLEO_TEST=undercloud
            ;;
        ha)
            export OVERCLOUD_CONTROLSCALE=3
            export TRIPLEO_DEBUG=1
            ;;
        vlan)
            export TRIPLEO_TEST=vlan
            ;;
    esac
done

# print the final values of control variables to console
env | grep -E "(DIB_COMMON_ELEMENTS|OVERCLOUD_CONTROLSCALE|TRIPLEO_TEST|USE_CIRROS|TRIPLEO_DEBUG)="

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
