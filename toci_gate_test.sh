#!/usr/bin/env bash
set -eux

# Clean any cached yum metadata, it maybe stale
sudo yum clean all

# Remove metrics from a previous run
rm -f /tmp/metric-start-times /tmp/metrics-data

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# Mirrors
# This Fedora Mirror is in the same data center as our CI rack
export FEDORA_MIRROR=http://dl.fedoraproject.org/pub/fedora/linux
# We don't seem to have a CentOS mirror in the data center, so we need to pick
# one that has reasonable connectivity to our rack.  Provide a few options in
# case one of them goes down.
for mirror in http://mirror.hmc.edu/centos/ http://mirrors.usc.edu/pub/linux/distributions/centos/ http://mirror.centos.org/centos/; do
    if curl -L -f -m 10 $mirror > /dev/null 2>&1; then
        export CENTOS_MIRROR=$mirror
        break
    fi
done
# This EPEL Mirror is in the same data center as our CI rack
export EPEL_MIRROR=http://dl.fedoraproject.org/pub/epel

export http_proxy=http://192.168.1.100:3128/
export GEARDSERVER=192.168.1.1
export MIRRORSERVER=192.168.1.101

export CACHEUPLOAD=0
export INTROSPECT=0
export NODECOUNT=2
export PACEMAKER=0
# NOTE(bnemec): At this time, the undercloud install + image build is taking from
# 1 hour to 1 hour and 15 minutes on the jobs I checked.  The devstack gate timeout
# is 170 minutes, so subtracting 90 should leave us an hour and 20 minutes for
# the deploy.  Hopefully that's enough, while still leaving some cushion to come
# in under the gate timeout so we can collect logs.
OVERCLOUD_DEPLOY_TIMEOUT=$((DEVSTACK_GATE_TIMEOUT-90))
export OVERCLOUD_DEPLOY_ARGS="--libvirt-type=qemu -t $OVERCLOUD_DEPLOY_TIMEOUT"
export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /opt/stack/new/tripleo-ci/test-environments/swap-partition.yaml"
export OVERCLOUD_UPDATE_ARGS=
export TRIPLEO_SH_ARGS=
export NETISO_V4=0
export NETISO_V6=0

# Set the fedora mirror, this is more reliable then relying on the repolist returned by metalink
sudo sed -i -e "s|^#baseurl=http://download.fedoraproject.org/pub/fedora/linux|baseurl=$FEDORA_MIRROR|;/^metalink/d" /etc/yum.repos.d/fedora*.repo

# start dstat early
# TODO add it to the gate image building
sudo yum install -y dstat nmap-ncat #nc is for metrics
mkdir -p "$WORKSPACE/logs"
dstat -tcmndrylpg --output "$WORKSPACE/logs/dstat-csv.log" >/dev/null &
disown

# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        overcloud)
            ;;
        upgrades)
            NODECOUNT=3
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml --ceph-storage-scale 1 -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation-v6.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/net-multiple-nics-v6.yaml -e /opt/stack/new/tripleo-ci/test-environments/net-iso.yaml"
            OVERCLOUD_UPDATE_ARGS="-e /usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS"
            NETISO_V6=1
            PACEMAKER=1
            ;;
        ha)
            NODECOUNT=4
            # In ci our overcloud nodes don't have access to an external netwrok
            # --ntp-server is here to make the deploy command happy, the ci env
            # is on virt so the clocks should be in sync without it.
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --control-scale 3 --ntp-server 0.centos.pool.ntp.org -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/net-multiple-nics.yaml -e /opt/stack/new/tripleo-ci/test-environments/net-iso.yaml"
            NETISO_V4=1
            PACEMAKER=1
            ;;
        nonha)
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /opt/stack/new/tripleo-ci/test-environments/enable-tls.yaml -e /opt/stack/new/tripleo-ci/test-environments/inject-trust-anchor.yaml --ceph-storage-scale 1 -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-ceph-devel.yaml"
            INTROSPECT=1
            NODECOUNT=3
            ;;
        containers)
            # TODO : remove this when the containers job is passing again
            exit 1
            TRIPLEO_SH_ARGS="--use-containers"
            ;;
        periodic)
            export DELOREAN_REPO_URL=http://trunk.rdoproject.org/centos7/consistent
            CACHEUPLOAD=1
            ;;
        liberty|mitaka)
            # This is handled in tripleo.sh (it always uses centos7-$STABLE_RELEASE/current)
            # where $STABLE_RELEASE is derived in toci_instack.sh
            unset DELOREAN_REPO_URL
            ;;
    esac
done

# print the final values of control variables to console
env | grep -E "(TOCI_JOBTYPE)="

# Allow the instack node to have traffic forwards through here
sudo iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
echo 1 | sudo dd of=/proc/sys/net/ipv4/ip_forward

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
# ./testenv-client kill everything in its own process group it it hits a timeout
# run it in a separate group to avoid getting killed along with it
set -m

source /opt/stack/new/tripleo-ci/scripts/metrics.bash
start_metric "tripleo.testenv.wait.seconds"
if [ -z ${TE_DATAFILE:-} ] ; then
    # Kill the whole job if it doesn't get a testenv in 20 minutes as it likely will timout in zuul
    ( sleep 1200 ; [ ! -e /tmp/toci.started ] && sudo kill -9 $$ ) &
    ./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_instack.sh
else
    LEAVE_RUNNING=1 ./toci_instack.sh
fi
