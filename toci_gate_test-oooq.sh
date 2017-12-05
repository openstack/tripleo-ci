#!/usr/bin/env bash

source $(dirname $0)/scripts/common_vars.bash
source $(dirname $0)/scripts/common_functions.sh

set -eux
export START_JOB_TIME=$(date +%s)
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Maintain compatibility with the old jobtypes
if [[ ! $TOCI_JOBTYPE =~ "featureset" ]]; then
    echo "WARNING: USING OLD DEPLOYMENT METHOD. THE OLD DEPLOYMENT METHOD THAT USES tripleo.sh WILL BE DEPRECATED IN THE QUEENS CYCLE"
    echo "TO USE THE NEW DEPLOYMENT METHOD WITH QUICKSTART, SETUP A FEATURESET FILE AND ADD featuresetXXX TO THE JOB TYPE"
    exec $TRIPLEO_ROOT/tripleo-ci/toci_gate_test-orig.sh
fi

source $TRIPLEO_ROOT/tripleo-ci/scripts/oooq_common_functions.sh

if [ -f /etc/nodepool/provider ] ; then
    # this sets
    # NODEPOOL_PROVIDER (e.g tripleo-test-cloud-rh1)
    # NODEPOOL_CLOUD (e.g.tripleo-test-cloud-rh1)
    # NODEPOOL_REGION (e.g. regionOne)
    # NODEPOOL_AZ
    source /etc/nodepool/provider

    # source variables common across all the scripts.
    source /etc/ci/mirror_info.sh

    # set up distribution mirrors in openstack
    NODEPOOL_MIRROR_HOST=${NODEPOOL_MIRROR_HOST:-mirror.$NODEPOOL_REGION.$NODEPOOL_CLOUD.openstack.org}
    NODEPOOL_MIRROR_HOST=$(echo $NODEPOOL_MIRROR_HOST|tr '[:upper:]' '[:lower:]')
    export CENTOS_MIRROR=http://$NODEPOOL_MIRROR_HOST/centos
    export EPEL_MIRROR=http://$NODEPOOL_MIRROR_HOST/epel

    # host setup
    export RHCLOUD=''
    if [ ${NODEPOOL_CLOUD:-''} == 'tripleo-test-cloud-rh1' ]; then
        RHCLOUD='rh1'
    elif [ ${NODEPOOL_PROVIDER:-''} == 'rdo-cloud-tripleo' ]; then
        RHCLOUD='rdocloud'
    fi
    if [[ "$RHCLOUD" != '' ]]; then
        source $(dirname $0)/scripts/$RHCLOUD.env

        # In order to save space remove the cached git repositories, at this point in
        # CI the ones we are interested in have been cloned to /opt/stack/new. We
        # can also remove some distro images cached on the images.
        sudo rm -rf /opt/git /opt/stack/cache/files/mysql.qcow2 /opt/stack/cache/files/ubuntu-12.04-x86_64.tar.gz
        mkdir -p $HOME/.ssh/
        cat $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo-cd-admins >> $HOME/.ssh/authorized_keys
    fi
fi

# default $NODEPOOL_PROVIDER if not already set as it's used later
export NODEPOOL_PROVIDER=${NODEPOOL_PROVIDER:-""}

# create logs dir (check if collect-logs doesn't already do this)
mkdir -p $WORKSPACE/logs

# Set job as failed until it's overwritten by pingtest/tempest real test subunit
cat $TRIPLEO_ROOT/tripleo-ci/scripts/fake_fail_subunit | gzip - > $WORKSPACE/logs/testrepository.subunit.gz

# Remove epel, either by epel-release, or unpackaged repo files
rpm -q epel-release && sudo yum -y erase epel-release
sudo rm -f /etc/yum.repos.d/epel*
# Clean any cached yum metadata, it maybe stale
sudo yum clean all

# NOTE(trown): In openstack-infra we have pip already, but this will ensure we
# have it available in other environments.
command -v pip || \
    (curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"; sudo python get-pip.py)

# NOTE(pabelanger): Current hack to make centos-7 dib work.
# TODO(pabelanger): Why is python-requests installed from pip?
# TODO(amoralej): remove after https://review.openstack.org/#/c/468872/ is merged
sudo pip uninstall certifi -y || true
sudo pip uninstall urllib3 -y || true
sudo pip uninstall requests -y || true
sudo rpm -e --nodeps python2-certifi || :
sudo rpm -e --nodeps python2-urllib3 || :
sudo rpm -e --nodeps python2-requests || :
sudo yum -y install python-requests python-urllib3
sudo pip install shyaml


# JOB_NAME used to be available from jenkins, we need to create it ourselves until
# we remove our reliance on it.
# FIXME: JOB_NAME IS USED IN CACHE UPLOAD AND PROMOTION,
# IF WE CHANGE THE JOB NAME, WE MUST UPDATE upload.cgi in mirror server
if [[ -z "${JOB_NAME-}" ]]; then
    JOB_NAME=${WORKSPACE%/}
    export JOB_NAME=${JOB_NAME##*/}
fi

# Sets whether or not this job will upload images.
export PERIODIC=0
# Sets which repositories to use in the job
export QUICKSTART_RELEASE="${STABLE_RELEASE:-master}"
# Stores OVB undercloud instance id
export UCINSTANCEID="null"
# Define environment variables file
export ENV_VARS=""
# Define file with set of features to test
export FEATURESET_FILE=""
export FEATURESET_CONF=""
# Define file with nodes topology
export NODES_FILE=""
# Indentifies which playbook to run
export PLAYBOOK=""
# Set the number of overcloud nodes
export NODECOUNT=0
# Sets the undercloud hostname
export UNDERCLOUD=""
# Select the tags to run
export TAGS=all
# Identify in which environment we're deploying
export ENVIRONMENT=""
# Set the overcloud hosts for multinode
export OVERCLOUD_HOSTS=
export CONTROLLER_HOSTS=
export SUBNODES_SSH_KEY=
OVERCLOUD_DEPLOY_TIMEOUT=$((DEVSTACK_GATE_TIMEOUT-90))
TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
export EXTRA_VARS=${EXTRA_VARS:-""}
export EXTRA_VARS="$EXTRA_VARS --extra-vars deploy_timeout=$OVERCLOUD_DEPLOY_TIMEOUT"
export NODES_ARGS=""
export COLLECT_CONF="$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/collect-logs.yml"


# Assemble quickstart configuration based on job type keywords
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        featureset*)
            FEATURESET_FILE="config/general_config/$JOB_TYPE_PART.yml"
            FEATURESET_CONF="$FEATURESET_CONF --config $FEATURESET_FILE"
        ;;
        ovb)
            OVB=1
            ENVIRONMENT="ovb"
            UCINSTANCEID=$(http_proxy= curl http://169.254.169.254/openstack/2015-10-15/meta_data.json | python -c 'import json, sys; print json.load(sys.stdin)["uuid"]')
            PLAYBOOK="ovb.yml"
            ENV_VARS="$ENV_VARS --environment $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb.yml"
            if [[ -f  "$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb-$RHCLOUD.yml" ]]; then
                ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb-$RHCLOUD.yml"
            fi
            UNDERCLOUD="undercloud"
        ;;
        multinode)
            SUBNODES_SSH_KEY=/etc/nodepool/id_rsa
            ENVIRONMENT="osinfra"
            PLAYBOOK="multinode.yml"
            FEATURESET_CONF="
                --extra-vars @config/general_config/featureset-multinode-common.yml
                $FEATURESET_CONF
            "
            if [[ $NODEPOOL_PROVIDER == "rdo-cloud-tripleo" ]]; then
                ENV_VARS="$ENV_VARS --environment $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode-rdocloud.yml"
            else
                ENV_VARS="$ENV_VARS --environment $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode.yml"
            fi
            UNDERCLOUD="127.0.0.2"
            TAGS="build,undercloud-setup,undercloud-scripts,undercloud-install,undercloud-post-install,tripleo-validations,overcloud-scripts,overcloud-prep-config,overcloud-prep-containers,overcloud-deploy,overcloud-upgrade,overcloud-validate"
            CONTROLLER_HOSTS=$(sed -n 1,1p /etc/nodepool/sub_nodes_private)
            OVERCLOUD_HOSTS=$(cat /etc/nodepool/sub_nodes_private)
        ;;
        singlenode)
            ENVIRONMENT="osinfra"
            UNDERCLOUD="127.0.0.2"
            PLAYBOOK="multinode.yml"
            FEATURESET_CONF="
                --extra-vars @config/general_config/featureset-multinode-common.yml
                $FEATURESET_CONF
            "
            if [[ $NODEPOOL_PROVIDER == "rdo-cloud-tripleo" ]]; then
                ENV_VARS="$ENV_VARS --environment $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode-rdocloud.yml"
            else
                ENV_VARS="$ENV_VARS --environment $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode.yml"
            fi
            TAGS="build,undercloud-setup,undercloud-scripts,undercloud-install,undercloud-validate,images"
        ;;
        periodic)
            PERIODIC=1
            if [[ -z ${DELOREAN_LINK:-''} ]]; then
                QUICKSTART_RELEASE="consistent-${QUICKSTART_RELEASE}"
            else
                QUICKSTART_RELEASE="promotion-testing-hash-${QUICKSTART_RELEASE}"
            fi
        ;;
        gate)
        ;;
        *)
        # the rest should be node configuration
            NODES_FILE="config/nodes/$JOB_TYPE_PART.yml"
        ;;
    esac
done

# Set UPGRADE_RELEASE if applicable
if is_featureset_mixed_upgrade "$TRIPLEO_ROOT/tripleo-quickstart/$FEATURESET_FILE"; then
    export UPGRADE_RELEASE=$(previous_release_from "$STABLE_RELEASE")
    QUICKSTART_RELEASE="$QUICKSTART_RELEASE-undercloud-$UPGRADE_RELEASE-overcloud"
fi

if [[ ! -z $NODES_FILE ]]; then
    pushd $TRIPLEO_ROOT/tripleo-quickstart
    NODECOUNT=$(shyaml get-value node_count < $NODES_FILE)
    popd
    NODES_ARGS="--nodes $NODES_FILE"
fi


pushd $TRIPLEO_ROOT/tripleo-ci
if [ -z "${TE_DATAFILE:-}" -a "$ENVIRONMENT" = "ovb" ] ; then

    export GEARDSERVER=${TEBROKERIP-192.168.1.1}
    # NOTE(pabelanger): We need gear for testenv, but this really should be
    # handled by tox.
    sudo pip install gear
    # Kill the whole job if it doesn't get a testenv in 20 minutes as it likely will timout in zuul
    ( sleep 1200 ; [ ! -e /tmp/toci.started ] && sudo kill -9 $$ ) &

    # We only support multi-nic at the moment
    NETISO_ENV="multi-nic"

    # provision env in rh cloud, then start quickstart
    ./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS \
        --envsize $NODECOUNT --ucinstance $UCINSTANCEID \
        --net-iso $NETISO_ENV -- ./toci_quickstart.sh
else
    # multinode preparation
    # Clear out any puppet modules on the node placed their by infra configuration
    sudo rm -rf /etc/puppet/modules/*

    # Copy nodepool keys to current user
    sudo cp /etc/nodepool/id_rsa* $HOME/.ssh/
    sudo chown $USER:$USER $HOME/.ssh/id_rsa*
    chmod 0600 $HOME/.ssh/id_rsa*
    # pre-ansible requirement
    sudo mkdir -p /root/.ssh/
    cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys
    cat $HOME/.ssh/authorized_keys | sudo tee -a /root/.ssh/authorized_keys
    sudo chmod 0600 /root/.ssh/authorized_keys
    sudo chown root:root /root/.ssh/authorized_keys
    # everything below here *MUST* be translated to a role ASAP
    # empty image to fool overcloud deployment
    # set no_proxy variable
    export IP_DEVICE=${IP_DEVICE:-"eth0"}
    MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')
    MY_IP_eth1=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}') || MY_IP_eth1=""

    export http_proxy=""
    undercloud_net_range="192.168.24."
    undercloud_services_ip=$undercloud_net_range"1"
    undercloud_haproxy_public_ip=$undercloud_net_range"2"
    undercloud_haproxy_admin_ip=$undercloud_net_range"3"
    export no_proxy=$undercloud_services_ip,$undercloud_haproxy_public_ip,$undercloud_haproxy_admin_ip,$MY_IP,$MY_IP_eth1



    # multinode bootstrap script
    export DO_BOOTSTRAP_SUBNODES=${DO_BOOTSTRAP_SUBNODES:-1}
    export BOOTSTRAP_SUBNODES_MINIMAL=0
    if [[ -z $STABLE_RELEASE || "$STABLE_RELEASE" = "ocata" || "$STABLE_RELEASE" = "pike" ]]; then
        BOOTSTRAP_SUBNODES_MINIMAL=1
    fi
    echo_vars_to_deploy_env_oooq
    subnodes_scp_deploy_env
    if [ "$DO_BOOTSTRAP_SUBNODES" = "1" ]; then
        $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh \
            --bootstrap-subnodes \
            2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S |"), $0; fflush(); }' | sudo tee /var/log/bootstrap-subnodes.log \
            || (tail -n 50 /var/log/bootstrap-subnodes.log && false)
    fi


    # finally, run quickstart
    ./toci_quickstart.sh
fi

echo "Run completed"
