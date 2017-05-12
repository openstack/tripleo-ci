#!/usr/bin/env bash
set -eux
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
# Mirrors
# NOTE(pabelanger): We have access to AFS mirrors, lets use them.
source /etc/nodepool/provider
source /etc/ci/mirror_info.sh

source $(dirname $0)/scripts/common_vars.bash
NODEPOOL_MIRROR_HOST=${NODEPOOL_MIRROR_HOST:-mirror.$NODEPOOL_REGION.$NODEPOOL_CLOUD.openstack.org}
NODEPOOL_MIRROR_HOST=$(echo $NODEPOOL_MIRROR_HOST|tr '[:upper:]' '[:lower:]')
export CENTOS_MIRROR=http://$NODEPOOL_MIRROR_HOST/centos
export EPEL_MIRROR=http://$NODEPOOL_MIRROR_HOST/epel
export START_JOB_TIME=$(date +%s)

if [ $NODEPOOL_CLOUD == 'tripleo-test-cloud-rh1' ]; then
    source $(dirname $0)/scripts/rh1.env

    # In order to save space remove the cached git repositories, at this point in
    # CI the ones we are interested in have been cloned to /opt/stack/new. We
    # can also remove some distro images cached on the images.
    sudo rm -rf /opt/git /opt/stack/cache/files/mysql.qcow2 /opt/stack/cache/files/ubuntu-12.04-x86_64.tar.gz
fi

# Clean any cached yum metadata, it maybe stale
sudo yum clean all

# NOTE(pabelanger): Current hack to make centos-7 dib work.
# TODO(pabelanger): Why is python-requests installed from pip?
sudo rm -rf /usr/lib/python2.7/site-packages/requests
sudo rpm -e --nodeps python-requests || :
sudo rpm -e --nodeps python2-requests || :
sudo yum -y install python-requests

# Remove metrics from a previous run
rm -f /tmp/metric-start-times /tmp/metrics-data

# JOB_NAME used to be available from jenkins, we need to create it ourselves until
# we remove our reliance on it.
if [[ -z "${JOB_NAME-}" ]]; then
    JOB_NAME=${WORKSPACE%/}
    export JOB_NAME=${JOB_NAME##*/}
fi

# cd to toci directory so relative paths work
cd $(dirname $0)

# Only define $http_proxy if it is unset (use "-" instead of ":-" in the
# parameter expansion). This will allow an external script to override using a
# proxy by setting export http_proxy=""
export http_proxy=${http_proxy-"http://192.168.1.100:3128/"}

export GEARDSERVER=${TEBROKERIP-192.168.1.1}
export MIRRORSERVER=${MIRRORIP-192.168.1.101}

export CACHEUPLOAD=0
export INTROSPECT=0
export NODECOUNT=2
export PACEMAKER=0
export UNDERCLOUD_MAJOR_UPGRADE=0
export OVERCLOUD_MAJOR_UPGRADE=0
export MAJOR_UPGRADE=0
export UPGRADE_RELEASE=
export UPGRADE_ENV=
# Whether or not we deploy an Overcloud
export OVERCLOUD=1
# NOTE(bnemec): At this time, the undercloud install + image build is taking from
# 1 hour to 1 hour and 15 minutes on the jobs I checked.  The devstack gate timeout
# is 170 minutes, so subtracting 90 should leave us an hour and 20 minutes for
# the deploy.  Hopefully that's enough, while still leaving some cushion to come
# in under the gate timeout so we can collect logs.
OVERCLOUD_DEPLOY_TIMEOUT=$((DEVSTACK_GATE_TIMEOUT-90))
# NOTE(bnemec): Hard-coding this to 45 minutes based on current Graphite metrics
OVERCLOUD_UPDATE_TIMEOUT=45
export OVERCLOUD_SSH_USER=${OVERCLOUD_SSH_USER:-"jenkins"}
export OVERCLOUD_DEPLOY_ARGS=${OVERCLOUD_DEPLOY_ARGS:-""}
export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --libvirt-type=qemu -t $OVERCLOUD_DEPLOY_TIMEOUT -e /usr/share/openstack-tripleo-heat-templates/environments/debug.yaml"
export OVERCLOUD_UPDATE_ARGS=
export OVERCLOUD_PINGTEST_ARGS="--skip-pingtest-cleanup"
export UNDERCLOUD_SSL=0
export UNDERCLOUD_HEAT_CONVERGENCE=0
export UNDERCLOUD_IDEMPOTENT=0
export UNDERCLOUD_SANITY_CHECK=0
export TRIPLEO_SH_ARGS=
export NETISO_V4=0
export NETISO_V6=0
export RUN_PING_TEST=1
export RUN_TEMPEST_TESTS=0
export OVB=0
export UCINSTANCEID=NULL
export TOCIRUNNER="./toci_instack_ovb.sh"
export MULTINODE=0
export OVERCLOUD_ROLES=""
# Whether or not we run TripleO using OpenStack Infra nodes
export OSINFRA=0
export CONTROLLER_HOSTS=
export COMPUTE_HOSTS=
export SUBNODES_SSH_KEY=
export TEST_OVERCLOUD_DELETE=0
export OOOQ=0
export DEPLOY_OVB_EXTRA_NODE=0
export CONTAINERS=0
export CA_SERVER=0
export UNDERCLOUD_TELEMETRY=0
export UNDERCLOUD_UI=0
export UNDERCLOUD_VALIDATIONS=0
export UNDERCLOUD_CONTAINERS=0
export PREDICTABLE_PLACEMENT=0
export OPSTOOLS_REPO_ENABLED=0
export POSTCI=1
export BOOTSTRAP_SUBNODES_MINIMAL=1

if [[ $TOCI_JOBTYPE =~ upgrades ]]; then
    # We deploy a master Undercloud and an Overcloud with the
    # previous release. The pingtest is disable because it won't
    # work with the few services deployed.
    if [ "$STABLE_RELEASE" = "ocata" ]; then
        UPGRADE_RELEASE=newton
    elif [ -z $STABLE_RELEASE ]; then
        UPGRADE_RELEASE=ocata
    fi
fi

if [[ $TOCI_JOBTYPE =~ scenario ]]; then
    export MULTINODE_ENV_NAME=${TOCI_JOBTYPE#periodic-}

    # enable opstools repository for scenario001
    if [[ "$MULTINODE_ENV_NAME" =~ scenario001-multinode ]]; then
        OPSTOOLS_REPO_ENABLED=1
    fi

    export MULTINODE_ENV_NAME=${MULTINODE_ENV_NAME%-upgrades}
else
    export MULTINODE_ENV_NAME='multinode'
fi

if [[ $TOCI_JOBTYPE =~ upgrades ]]; then
    MULTINODE_ENV_PATH=$TRIPLEO_ROOT/$UPGRADE_RELEASE/usr/share/openstack-tripleo-heat-templates/ci/environments/$MULTINODE_ENV_NAME.yaml
else
    MULTINODE_ENV_PATH=/usr/share/openstack-tripleo-heat-templates/ci/environments/$MULTINODE_ENV_NAME.yaml
fi

if [[ "$TOCI_JOBTYPE" =~ "periodic" && "$TOCI_JOBTYPE" =~ "-ha" ]]; then
    TEST_OVERCLOUD_DELETE=1
elif [[ "$TOCI_JOBTYPE" =~ "periodic" && "$TOCI_JOBTYPE" =~ "-nonha" ]]; then
    UNDERCLOUD_IDEMPOTENT=1
fi

# Test version of ssh package for bug https://bugzilla.redhat.com/show_bug.cgi?id=1415218
rpm -q wget || sudo yum install -y wget
http_proxy= wget -P /tmp -T 60 --tries=3 --progress=dot:mega http://66.187.229.139/test/openssh-6.6.1p1-33.el7.x86_64.rpm
http_proxy= wget -P /tmp -T 60 --tries=3 --progress=dot:mega http://66.187.229.139/test/openssh-server-6.6.1p1-33.el7.x86_64.rpm
sudo rpm -ivh --force /tmp/openssh-6.6.1p1-33.el7.x86_64.rpm /tmp/openssh-server-6.6.1p1-33.el7.x86_64.rpm

# start dstat early
# TODO add it to the gate image building
rpm -q dstat nmap-ncat || sudo yum install -y dstat nmap-ncat #nc is for metrics
mkdir -p "$WORKSPACE/logs"
dstat -tcmndrylpg --top-cpu-adv --top-io-adv --nocolor | tee --append $WORKSPACE/logs/dstat.log > /dev/null &
disown

# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        updates)
            if [[ "$TOCI_JOBTYPE" =~ 'ovb-updates' ]] ; then
                NODECOUNT=3
                if [[ "${STABLE_RELEASE}" =~ ^mitaka$ ]] ; then
                    ENDPOINT_LIST_LOCATION=$TRIPLEO_ROOT/tripleo-ci/test-environments
                    CA_ENVIRONMENT_FILE=inject-trust-anchor-ipv6.yaml
                else
                    ENDPOINT_LIST_LOCATION=/usr/share/openstack-tripleo-heat-templates/environments
                    CA_ENVIRONMENT_FILE=inject-trust-anchor-hiera-ipv6.yaml
                fi
                OVERCLOUD_DEPLOY_ARGS="
                    $OVERCLOUD_DEPLOY_ARGS
                    -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml
                    -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation-v6.yaml
                    -e $TRIPLEO_ROOT/tripleo-ci/test-environments/ipv6-network-templates/network-environment.yaml
                    -e $TRIPLEO_ROOT/tripleo-ci/test-environments/net-iso.yaml
                    -e $TRIPLEO_ROOT/tripleo-ci/test-environments/enable-tls-ipv6.yaml
                    -e $ENDPOINT_LIST_LOCATION/tls-endpoints-public-ip.yaml
                    -e $TRIPLEO_ROOT/tripleo-ci/test-environments/$CA_ENVIRONMENT_FILE
                    --ceph-storage-scale 1
                    -e /usr/share/openstack-tripleo-heat-templates/environments/storage-environment.yaml
                "
                OVERCLOUD_UPDATE_ARGS="-e /usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS"
                NETISO_V6=1
                PACEMAKER=1
            elif [[ "$TOCI_JOBTYPE" =~ 'nonha-multinode-updates' ]] ; then
                OVERCLOUD_UPDATE_ARGS="-e /usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS"
            fi
            ;;
        upgrades)
            MAJOR_UPGRADE=1
            if [ $TOCI_JOBTYPE == 'undercloud-upgrades' ] ; then
                # We want to start by installing an Undercloud
                # from the previous stable release.
                if [ "$STABLE_RELEASE" = "ocata" ]; then
                    STABLE_RELEASE=newton
                elif [ "$STABLE_RELEASE" = "newton" ]; then
                    STABLE_RELEASE=mitaka
                elif [ -z $STABLE_RELEASE ]; then
                    #TODO(emilien) switch to pike when released
                    STABLE_RELEASE=ocata
                fi
                UNDERCLOUD_MAJOR_UPGRADE=1
                export UNDERCLOUD_SANITY_CHECK=1
            fi
            if [[ $TOCI_JOBTYPE =~ 'multinode-upgrades' ]] ; then
                OVERCLOUD_MAJOR_UPGRADE=1
                # We still bootstrap subnodes manually for multinode-upgrades
                # because we are deploying Newton initially.
                BOOTSTRAP_SUBNODES_MINIMAL=0
                UNDERCLOUD_SSL=0
                export UNDERCLOUD_SANITY_CHECK=0
                if [[ $TOCI_JOBTYPE == 'multinode-upgrades' ]] ; then
                   export UPGRADE_ENV=/usr/share/openstack-tripleo-heat-templates/ci/environments/multinode_major_upgrade.yaml
                else
                   export UPGRADE_ENV=/usr/share/openstack-tripleo-heat-templates/ci/environments/$MULTINODE_ENV_NAME.yaml
                fi
                OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --libvirt-type=qemu -t $OVERCLOUD_DEPLOY_TIMEOUT -r $TRIPLEO_ROOT/tripleo-ci/test-environments/upgrade_roles_data.yaml --overcloud-ssh-user $OVERCLOUD_SSH_USER --validation-errors-nonfatal"
            fi
            ;;
        ha)
            NODECOUNT=4
            # In ci our overcloud nodes don't have access to an external netwrok
            # --ntp-server is here to make the deploy command happy, the ci env
            # is on virt so the clocks should be in sync without it.
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --control-scale 3 --ntp-server 0.centos.pool.ntp.org -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/network-templates/network-isolation-absolute.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/network-templates/network-environment.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/net-iso.yaml"
            NETISO_V4=1
            PACEMAKER=1
            PREDICTABLE_PLACEMENT=1
            ;;
        nonha)
            if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
                ENDPOINT_LIST_LOCATION=$TRIPLEO_ROOT/tripleo-ci/test-environments
                CA_ENVIRONMENT_FILE=inject-trust-anchor.yaml
            else
                ENDPOINT_LIST_LOCATION=/usr/share/openstack-tripleo-heat-templates/environments
                CA_ENVIRONMENT_FILE=inject-trust-anchor-hiera.yaml
            fi
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/enable-tls.yaml -e $ENDPOINT_LIST_LOCATION/tls-endpoints-public-ip.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/$CA_ENVIRONMENT_FILE --ceph-storage-scale 1 -e /usr/share/openstack-tripleo-heat-templates/environments/storage-environment.yaml"
            INTROSPECT=1
            NODECOUNT=3
            UNDERCLOUD_SSL=1
            UNDERCLOUD_TELEMETRY=1
            UNDERCLOUD_UI=1
            UNDERCLOUD_VALIDATIONS=1
            ;;
        containers)
            CONTAINERS=1
            UNDERCLOUD_CONTAINERS=1
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS \
            -e /usr/share/openstack-tripleo-heat-templates/environments/docker.yaml \
            -e /usr/share/openstack-tripleo-heat-templates/environments/docker-network.yaml \
            -e ~/containers-default-parameters.yaml"
            ;;
        ovb)
            OVB=1

            # The test env broker needs to know the instanceid of the this node so it can attach it to the provisioning network
            UCINSTANCEID=$(http_proxy= curl http://169.254.169.254/openstack/2015-10-15/meta_data.json | python -c 'import json, sys; print json.load(sys.stdin)["uuid"]')
            ;;
        ipv6)
            NETISO_V4=0
            NETISO_V6=1
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS  -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation-v6.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/ipv6-network-templates/network-environment.yaml"
            ;;
        convergence)
            UNDERCLOUD_HEAT_CONVERGENCE=1
            ;;
        multinode)
            MULTINODE=1
            TOCIRUNNER="./toci_instack_osinfra.sh"
            OSINFRA=1
            UNDERCLOUD_SSL=0
            INTROSPECT=0
            SUBNODES_SSH_KEY=/etc/nodepool/id_rsa
            OVERCLOUD_DEPLOY_ARGS="--libvirt-type=qemu -t $OVERCLOUD_DEPLOY_TIMEOUT"

            if [[ "$TOCI_JOBTYPE" =~ "3nodes" ]]; then
                NODECOUNT=2
                PACEMAKER=1
                OVERCLOUD_ROLES="ControllerApi Controller"
                export ControllerApi_hosts=$(sed -n 1,1p /etc/nodepool/sub_nodes)
                export Controller_hosts=$(sed -n 2,2p /etc/nodepool/sub_nodes)
                OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/deployed-server-environment.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/multinode-3nodes.yaml --compute-scale 0 --overcloud-ssh-user $OVERCLOUD_SSH_USER --validation-errors-nonfatal -r /usr/share/openstack-tripleo-heat-templates/ci/environments/multinode-3nodes.yaml"
            else
                NODECOUNT=1
                CONTROLLER_HOSTS=$(sed -n 1,1p /etc/nodepool/sub_nodes)
                OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/deployed-server-environment.yaml -e $MULTINODE_ENV_PATH --compute-scale 0 --overcloud-ssh-user $OVERCLOUD_SSH_USER --validation-errors-nonfatal"
            fi

            if [ "$STABLE_RELEASE" = "newton" ]; then
                BOOTSTRAP_SUBNODES_MINIMAL=0
            else
                BOOTSTRAP_SUBNODES_MINIMAL=1
                OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/deployed-server-bootstrap-environment-centos.yaml "
            fi
            ;;
        undercloud)
            TOCIRUNNER="./toci_instack_osinfra.sh"
            NODECOUNT=0
            OVERCLOUD=0
            OSINFRA=1
            RUN_PING_TEST=0
            INTROSPECT=0
            UNDERCLOUD_SSL=1
            UNDERCLOUD_TELEMETRY=1
            UNDERCLOUD_UI=1
            UNDERCLOUD_VALIDATIONS=1
            export UNDERCLOUD_SANITY_CHECK=1
            ;;
        periodic)
            export DELOREAN_REPO_URL=https://trunk.rdoproject.org/centos7/consistent
            export DELOREAN_STABLE_REPO_URL=https://trunk.rdoproject.org/centos7-$STABLE_RELEASE/consistent/
            CACHEUPLOAD=1
            OVERCLOUD_PINGTEST_ARGS=
            ;;
        mitaka)
            # This is handled in tripleo.sh (it always uses centos7-$STABLE_RELEASE/current)
            # where $STABLE_RELEASE is derived in toci_instack.sh
            unset DELOREAN_REPO_URL
            ;;
        tempest)
            export RUN_TEMPEST_TESTS=1
            export RUN_PING_TEST=0
            ;;
        oooq)
            export OOOQ=1
            if [[ "$TOCI_JOBTYPE" =~ "multinode" ]]; then
                TOCIRUNNER="./toci_instack_oooq_multinode.sh"
            else
                TOCIRUNNER="./toci_instack_oooq.sh"
            fi
            PREDICTABLE_PLACEMENT=0
            POSTCI=0
            ;;
        fakeha)
            NODECOUNT=2
            # In ci our overcloud nodes don't have access to an external network
            # --ntp-server is here to make the deploy command happy, the ci env
            # is on virt so the clocks should be in sync without it.
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --control-scale 1 --ntp-server 0.centos.pool.ntp.org -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-pacemaker.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/network-templates/network-isolation-absolute.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/network-templates/network-environment.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/net-iso.yaml"
            NETISO_V4=1
            PACEMAKER=1
            ;;
        caserver)
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/services/haproxy-public-tls-certmonger.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/tls-everywhere-endpoints-dns.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/enable-internal-tls.yaml"
            # This is created in scripts/deploy.sh as part of the CA_SERVER
            # section
            OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/cloud-names.yaml -e $TRIPLEO_ROOT/keystone-ldap.yaml"
            CA_SERVER=1
            DEPLOY_OVB_EXTRA_NODE=1
            ;;
    esac
done

if [[ $PREDICTABLE_PLACEMENT == 1 ]]; then
    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/ips-from-pool-all.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/hostname-map.yaml -e $TRIPLEO_ROOT/tripleo-ci/test-environments/scheduler-hints.yaml"
fi
# Limit worker counts to avoid overloading our limited resources
if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config-mitaka-and-below.yaml"
elif [[ "${OVERCLOUD_MAJOR_UPGRADE}" == "1" ]]; then
    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml"
else
    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml"
fi
# If we're running an update job, regenerate the args to reflect the above changes
if [ -n "$OVERCLOUD_UPDATE_ARGS" ]; then
    OVERCLOUD_UPDATE_ARGS="-e /usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS"
    # We need a shorter timeout for the update step.  80 minutes puts us past
    # the gate timeout in most cases.
    OVERCLOUD_UPDATE_ARGS=$(echo "$OVERCLOUD_UPDATE_ARGS" | sed "s/-t $OVERCLOUD_DEPLOY_TIMEOUT/-t $OVERCLOUD_UPDATE_TIMEOUT/")
fi

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
# ./testenv-client kill everything in its own process group it it hits a timeout
# run it in a separate group to avoid getting killed along with it
set -m

if [ "$DEPLOY_OVB_EXTRA_NODE" = '1' ]; then
    # This is usually done in the undercloud install, but we need it at this
    # point since we want access to the extra node
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
    SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"
    TEST_ENV_EXTRA_ARGS=("--create-undercloud" "--ssh-key" "$SSH_KEY")
else
    TEST_ENV_EXTRA_ARGS=()
fi

source $TRIPLEO_ROOT/tripleo-ci/scripts/metrics.bash
start_metric "tripleo.testenv.${TOCI_JOBTYPE}.wait.seconds"
if [ -z "${TE_DATAFILE:-}" -a "$OSINFRA" = "0" ] ; then
    # NOTE(pabelanger): We need gear for testenv, but this really should be
    # handled by tox.
    sudo pip install gear
    # Kill the whole job if it doesn't get a testenv in 20 minutes as it likely will timout in zuul
    ( sleep 1200 ; [ ! -e /tmp/toci.started ] && sudo kill -9 $$ ) &

    # TODO(bnemec): Add jobs that use public-bond
    NETISO_ENV="none"
    if [ $NETISO_V4 -eq 1 -o $NETISO_V6 -eq 1 ]; then
        NETISO_ENV="multi-nic"
    fi
    if [ ${#TEST_ENV_EXTRA_ARGS[@]} -eq 0 ]; then
        ./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS \
            --envsize $NODECOUNT --ucinstance $UCINSTANCEID \
            --net-iso $NETISO_ENV -- $TOCIRUNNER
    else
        ./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS \
            --envsize $NODECOUNT --ucinstance $UCINSTANCEID \
            --net-iso $NETISO_ENV "${TEST_ENV_EXTRA_ARGS[@]}" -- $TOCIRUNNER
    fi
else
    $TOCIRUNNER
fi
