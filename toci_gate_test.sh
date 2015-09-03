#!/usr/bin/env bash

set -eu

# Clean any cached yum metadata, it maybe stale
sudo yum clean all

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# Switch to instack ci once we drop support for tripleo-incubator
# we can drop the dual code path
case $TOCI_JOBTYPE in
    overcloud-f21-nonha|overcloud-f21puppet-ceph)
        ./toci_gate_test_instack.sh $@
        exit 0
        ;;
esac

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
export DIB_CLOUD_INIT_ETC_HOSTS="localhost"
export TRIPLEO_TEST=${TRIPLEO_TEST:-"overcloud"}
export USE_CIRROS=${USE_CIRROS:-"1"}
export USE_MERGEPY=${USE_MERGEPY:-0}
export OVERCLOUD_CONTROLSCALE=${OVERCLOUD_CONTROLSCALE:-"1"}
export OVERCLOUD_COMPUTESCALE=${OVERCLOUD_COMPUTESCALE:-"1"}
export TRIPLEO_DEBUG=${TRIPLEO_DEBUG:-""}
export OVERCLOUD_STACK_TIMEOUT="35"
export OVERCLOUD_CUSTOM_HEAT_ENV=${OVERCLOUD_CUSTOM_HEAT_ENV:-""}

# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        undercloud)
            export TRIPLEO_TEST=undercloud
            ;;
        ha)
            export OVERCLOUD_CONTROLSCALE=3
            export OVERCLOUD_STACK_TIMEOUT="90"
            export TRIPLEO_DEBUG=1
            export OVERCLOUD_CUSTOM_HEAT_ENV="$OVERCLOUD_CUSTOM_HEAT_ENV /opt/stack/new/tripleo-heat-templates/environments/puppet-pacemaker.yaml /opt/stack/new/l3ha.yaml"
            cat >> /opt/stack/new/l3ha.yaml <<EOF
parameters:
  NeutronL3HA: true
  NeutronAllowL3AgentFailover: false
EOF
            ;;
        ceph)
            export OVERCLOUD_STACK_TIMEOUT="90"
            export OVERCLOUD_CUSTOM_HEAT_ENV="$OVERCLOUD_CUSTOM_HEAT_ENV /opt/stack/new/tripleo-heat-templates/environments/puppet-ceph-devel.yaml"
            ;;
        vlan)
            export TRIPLEO_TEST=vlan
            ;;
        f20|f21)
            export DIB_RELEASE=21
            ;;
        f20puppet|f21puppet)
            export DIB_RELEASE=21
            export TRIPLEO_ROOT=/opt/stack/new/ #FIXME: also defined in toci_devtest
            export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-puppet-elements/elements:$TRIPLEO_ROOT/heat-templates/hot/software-config/elements:$TRIPLEO_ROOT/tripleo-image-elements/elements
            export DELOREAN_REPO_URL="http://trunk.rdoproject.org/f21/ba/d8/bad85a2b10274bbe22d626228eac32dbb3f82293_1bcc81bc"
            export RDO_RELEASE=kilo
            export DIB_COMMON_ELEMENTS='stackuser os-net-config delorean-repo rdo-release'
            export ROOT_DISK=40
            export DIB_DEFAULT_INSTALLTYPE=package
            export RESOURCE_REGISTRY_PATH="$TRIPLEO_ROOT/tripleo-heat-templates/overcloud-resource-registry-puppet.yaml"
            export DIB_INSTALLTYPE_puppet_modules=source
            export DIB_CLOUD_INIT_ETC_HOSTS=""
            export OVERCLOUD_DISK_IMAGES_CONFIG=$TRIPLEO_ROOT/tripleo-incubator/scripts/overcloud_puppet_disk_images.yaml
            export OVERCLOUD_CUSTOM_HEAT_ENV="$OVERCLOUD_CUSTOM_HEAT_ENV /opt/stack/new/tripleo-heat-templates/environments/mongodb-nojournal.yaml"
            ;;
        precise)
            export USE_MERGEPY=1
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
    # Pin to a specific fedora mirror to avoid temporary Fedora infra problems
    export DIB_DISTRIBUTION_MIRROR=http://dl.fedoraproject.org/pub/fedora/linux

    for FILE in /etc/yum.repos.d/fedora.repo /etc/yum.repos.d/fedora-updates.repo /etc/yum.repos.d/fedora-updates-testing.repo; do
        sudo sed -e "s|^#baseurl=http://download.fedoraproject.org/pub/fedora/linux|baseurl=$DIB_DISTRIBUTION_MIRROR|;/^metalink/d" -i $FILE
    done

    # TODO : This should read the ARCH of the test being targeted
    FEDORA_IMAGE=$(wget -q http://dl.fedoraproject.org/pub/fedora/linux/updates/$DIB_RELEASE/Images/x86_64/ -O - | grep -o -E 'href="([^"#]+qcow2)"' | cut -d'"' -f2)
    if [ -n "$FEDORA_IMAGE" ]; then
        wget --progress=dot:mega http://dl.fedoraproject.org/pub/fedora/linux/updates/$DIB_RELEASE/Images/x86_64/$FEDORA_IMAGE
    else
        # No Fedora update images are available. Use the release...
        FEDORA_IMAGE=fedora-$DIB_RELEASE.x86_64.qcow2
        wget --progress=dot:mega http://cloud.fedoraproject.org/$FEDORA_IMAGE
    fi
    export DIB_LOCAL_IMAGE=$PWD/$FEDORA_IMAGE
fi

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
set -m
./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_devtest.sh
