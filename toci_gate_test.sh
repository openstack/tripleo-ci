#!/usr/bin/env bash

source $(dirname $0)/scripts/common_vars.bash
source $(dirname $0)/scripts/common_functions.sh

set -eux
export START_JOB_TIME=$(date +%s)
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

source $TRIPLEO_ROOT/tripleo-ci/scripts/oooq_common_functions.sh

if [ -f /etc/nodepool/provider ] ; then
    # this sets
    # NODEPOOL_PROVIDER (e.g tripleo-test-cloud-rh1)
    # NODEPOOL_CLOUD (e.g.tripleo-test-cloud-rh1)
    # NODEPOOL_REGION (e.g. regionOne)
    # NODEPOOL_AZ
    source /etc/nodepool/provider

    # source variables common across all the scripts.
    if [ -e /etc/ci/mirror_info.sh ]; then
        source /etc/ci/mirror_info.sh
    fi

    export RHCLOUD=''
    if [[ ${NODEPOOL_PROVIDER:-''} == 'rdo-cloud'* ]]; then
        RHCLOUD='rdocloud'
    elif [ ${NODEPOOL_PROVIDER:-''} == 'vexxhost-nodepool-tripleo' ]; then
        RHCLOUD='vexxhost'
    fi

    if [ -n $RHCLOUD ]; then
        source $(dirname $0)/scripts/$RHCLOUD.env

        # In order to save space remove the cached git repositories, at this point in
        # CI the ones we are interested in have been cloned to /opt/stack/new. We
        # can also remove some distro images cached on the images.
        # rm -rf spawns a separate process for each file, lets use find -delete
        sudo find /opt/git -delete || true
    fi
fi

# default $NODEPOOL_PROVIDER if not already set as it's used later
export NODEPOOL_PROVIDER=${NODEPOOL_PROVIDER:-""}


# create logs dir (check if collect-logs doesn't already do this)
mkdir -p $WORKSPACE/logs

# Set job as failed until it's overwritten by pingtest/tempest real test subunit
cat $TRIPLEO_ROOT/tripleo-ci/scripts/fake_fail_subunit | gzip - > $WORKSPACE/logs/testrepository.subunit.gz


# NOTE(trown): In openstack-infra we have pip already, but this will ensure we
# have it available in other environments.
command -v pip || \
    (curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"; sudo python get-pip.py)

sudo yum -y install python-requests python-urllib3
sudo pip install shyaml



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
TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
export EXTRA_VARS=${EXTRA_VARS:-""}
export VXLAN_VARS=${VXLAN_VARS:-""}
export NODES_ARGS=""
export EXTRANODE=""
export EMIT_RELEASES_EXTRA_ARGS=""
# Set playbook execution status
export PLAYBOOK_DRY_RUN=${PLAYBOOK_DRY_RUN:=0}
export COLLECT_CONF="$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/collect-logs.yml"
LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
LWD=$LOCAL_WORKING_DIR
QUICKSTART_SH_JOBS="ovb-3ctlr_1comp-featureset001 multinode-1ctlr-featureset010"

export RELEASES_FILE_OUTPUT=$WORKSPACE/logs/releases.sh
export RELEASES_SCRIPT=$TRIPLEO_ROOT/tripleo-ci/scripts/emit_releases_file/emit_releases_file.py
export RELEASES_SCRIPT_LOGFILE=$WORKSPACE/logs/emit_releases_file.log

# Assemble quickstart configuration based on job type keywords
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        featureset*)
            FEATURESET_FILE="$LWD/config/general_config/$JOB_TYPE_PART.yml"
            # featurset_file is not yet in its final destination so we
            # have to use current_featureset_file.
            CURRENT_FEATURESET_FILE="$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/$JOB_TYPE_PART.yml"
            FEATURESET_CONF="$FEATURESET_CONF --extra-vars @$FEATURESET_FILE"
            MIXED_UPGRADE_TYPE=''
            # Order matters.  ffu featureset has both mixed version and ffu_overcloud_upgrade.
            if is_featureset ffu_overcloud_upgrade "${CURRENT_FEATURESET_FILE}"; then
                MIXED_UPGRADE_TYPE='ffu_upgrade'
            elif  is_featureset mixed_upgrade  "${CURRENT_FEATURESET_FILE}"; then
                MIXED_UPGRADE_TYPE='mixed_upgrade'
            elif is_featureset overcloud_update "${CURRENT_FEATURESET_FILE}"; then
                TAGS="$TAGS,overcloud-update"
            elif is_featureset undercloud_upgrade "${CURRENT_FEATURESET_FILE}"; then
                TAGS="$TAGS,undercloud-upgrade"
                export UPGRADE_RELEASE=$QUICKSTART_RELEASE
                export QUICKSTART_RELEASE=$(previous_release_mixed_upgrade_case "${UPGRADE_RELEASE}")
            fi
            # The case is iterating over TOCI_JOBTYPE which is
            # standalone-featureset.  So featureset comes after and we
            # can override TAGS safely.
            if is_featureset standalone_upgrade "${CURRENT_FEATURESET_FILE}" ; then
                # We don't want "build" as it would wrongly build test
                # package under the N-1 version.
                TAGS="standalone,standalone-upgrade"
            fi
            # Set UPGRADE_RELEASE if applicable
            if [ -n "${MIXED_UPGRADE_TYPE}" ]; then
                export UPGRADE_RELEASE=$(previous_release_from "${STABLE_RELEASE}" "${MIXED_UPGRADE_TYPE}")
                QUICKSTART_RELEASE="$QUICKSTART_RELEASE-undercloud-$UPGRADE_RELEASE-overcloud"
                # Run overcloud-upgrade tag only in upgrades jobs
                TAGS="$TAGS,overcloud-upgrade"
            fi
        ;;
        ovb)
            OVB=1
            ENVIRONMENT="ovb"
            METADATA_FILENAME='/mnt/config/openstack/latest/meta_data.json'
            if sudo test -f $METADATA_FILENAME; then
                METADATA=$(sudo cat /mnt/config/openstack/latest/meta_data.json)
                set +x
                UCINSTANCEID=$(echo $METADATA | python -c 'import json, sys; print json.load(sys.stdin)["uuid"]')
                set -x
            else
                UCINSTANCEID=$(http_proxy= curl http://169.254.169.254/openstack/2015-10-15/meta_data.json | python -c 'import json, sys; print json.load(sys.stdin)["uuid"]')
            fi
            if [[ " $QUICKSTART_SH_JOBS " =~ " $TOCI_JOBTYPE " ]]; then
                export PLAYBOOKS=${PLAYBOOKS:-"baremetal-full-deploy.yml"}
            else
                export PLAYBOOKS=${PLAYBOOKS:-"ovb-setup.yml baremetal-full-undercloud.yml baremetal-full-overcloud-prep.yml baremetal-full-overcloud.yml baremetal-full-overcloud-validate.yml browbeat-minimal.yml"}
            fi
            ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb.yml"
            if [[ -f  "$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb-$RHCLOUD.yml" ]]; then
                ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/ovb-$RHCLOUD.yml"
            fi
            UNDERCLOUD="undercloud"
        ;;
        multinode)
            SUBNODES_SSH_KEY=/etc/nodepool/id_rsa
            ENVIRONMENT="osinfra"
            if [[ " $QUICKSTART_SH_JOBS " =~ " $TOCI_JOBTYPE " ]]; then
                export PLAYBOOKS=${PLAYBOOKS:-"multinode.yml"}
            else
                export PLAYBOOKS=${PLAYBOOKS:-"quickstart.yml multinode-undercloud.yml multinode-overcloud-prep.yml multinode-overcloud.yml multinode-overcloud-update.yml multinode-overcloud-upgrade.yml multinode-validate.yml"}
            fi
            FEATURESET_CONF=" --extra-vars @$LWD/config/general_config/featureset-multinode-common.yml $FEATURESET_CONF"
            ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode.yml"
            if [[ $NODEPOOL_PROVIDER == "rdo-cloud"* ]]; then
                ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode-rdocloud.yml"
            fi
            UNDERCLOUD="127.0.0.2"
            TAGS="build,undercloud-setup,undercloud-scripts,undercloud-install,undercloud-post-install,tripleo-validations,overcloud-scripts,overcloud-prep-config,overcloud-prep-containers,overcloud-deploy,overcloud-post-deploy,overcloud-validate"
            CONTROLLER_HOSTS=$(sed -n 1,1p /etc/nodepool/sub_nodes_private)
            OVERCLOUD_HOSTS=$(cat /etc/nodepool/sub_nodes_private)
        ;;
        singlenode)
            ENVIRONMENT="osinfra"
            UNDERCLOUD="127.0.0.2"
            if [[ " $QUICKSTART_SH_JOBS " =~ " $TOCI_JOBTYPE " ]]; then
                export PLAYBOOKS=${PLAYBOOKS:-"multinode.yml"}
            else
                export PLAYBOOKS=${PLAYBOOKS:-"quickstart.yml multinode-undercloud.yml multinode-undercloud-upgrade.yml multinode-overcloud-prep.yml multinode-overcloud.yml multinode-overcloud-upgrade.yml multinode-validate.yml"}
            fi
            FEATURESET_CONF=" --extra-vars @$LWD/config/general_config/featureset-multinode-common.yml $FEATURESET_CONF"
            ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode.yml"
            if [[ $NODEPOOL_PROVIDER == "rdo-cloud"* ]]; then
                ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode-rdocloud.yml"
            fi
            TAGS="build,undercloud-setup,undercloud-scripts,undercloud-install,undercloud-validate,images"
        ;;
        standalone)
            ENVIRONMENT="osinfra"
            UNDERCLOUD="127.0.0.2"
            # Adding upgrade playbook here to be consistant with the v3 definition.
            export PLAYBOOKS=${PLAYBOOKS:-"quickstart.yml multinode-standalone.yml multinode-standalone-upgrade.yml "}
            FEATURESET_CONF=" --extra-vars @$LWD/config/general_config/featureset-multinode-common.yml $FEATURESET_CONF"
            ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode.yml"
            if [[ $NODEPOOL_PROVIDER == "rdo-cloud"* ]]; then
                ENV_VARS="$ENV_VARS --extra-vars @$TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/multinode-rdocloud.yml"
            fi
            TAGS="build,standalone"
        ;;
        periodic)
            PERIODIC=1
            QUICKSTART_RELEASE="promotion-testing-hash-${QUICKSTART_RELEASE}"
            EMIT_RELEASES_EXTRA_ARGS="$EMIT_RELEASES_EXTRA_ARGS --is-periodic"
        ;;
        gate)
        ;;
        dryrun)
            PLAYBOOK_DRY_RUN=1
        ;;
        *)
        # the rest should be node configuration
            NODES_FILE="$TRIPLEO_ROOT/tripleo-quickstart/config/nodes/$JOB_TYPE_PART.yml"
        ;;
    esac
done


if [[ -f "$RELEASES_SCRIPT" ]] && [[ $FEATURESET_FILE =~  010|011|037|047|050|056 ]]; then

    python $RELEASES_SCRIPT \
        --stable-release ${STABLE_RELEASE:-"master"} \
        --featureset-file $TRIPLEO_ROOT/tripleo-quickstart/config/general_config/$(basename $FEATURESET_FILE) \
        --output-file $RELEASES_FILE_OUTPUT \
        --log-file $RELEASES_SCRIPT_LOGFILE \
        $EMIT_RELEASES_EXTRA_ARGS
fi


if [[ ! -z $NODES_FILE ]]; then
    pushd $TRIPLEO_ROOT/tripleo-quickstart
    NODECOUNT=$(shyaml get-value node_count < $NODES_FILE)
    popd
    NODES_ARGS="--extra-vars @$NODES_FILE"
    for PART in $(sed 's/_/ /g' <<< "$NODES_FILE") ; do
        if [[ "$PART" == *"supp"* ]]; then
            EXTRANODE=" --extra-nodes ${PART//[!0-9]/} "
        fi;
    done
fi

# Import gated tripleo-upgrade in oooq for upgrades/updates jobs
if [[ -d $TRIPLEO_ROOT/tripleo-upgrade ]]; then
    echo "file://${TRIPLEO_ROOT}/tripleo-upgrade/#egg=tripleo-upgrade" >> ${TRIPLEO_ROOT}/tripleo-quickstart/quickstart-extras-requirements.txt
else
    # Otherwise, if not importing it, oooq will fail when loading
    # tripleo-upgrade role in the playbook.
    echo "git+https://opendev.org/openstack/tripleo-upgrade.git@${ZUUL_BRANCH}#egg=tripleo-upgrade" >> ${TRIPLEO_ROOT}/tripleo-quickstart/quickstart-extras-requirements.txt
fi

# Import gated external repo in oooq
for EXTERNAL_REPO in 'browbeat' 'tripleo-ha-utils' 'tripleo-quickstart-extras'; do
    if [[ -d $TRIPLEO_ROOT/$EXTERNAL_REPO ]]; then
        sed -i "s#git+https://opendev.org/openstack/$EXTERNAL_REPO#file://${TRIPLEO_ROOT}/$EXTERNAL_REPO#1" ${TRIPLEO_ROOT}/tripleo-quickstart/quickstart-extras-requirements.txt
    fi
done

# Start time tracking
export STATS_TESTENV=$(date +%s)
pushd $TRIPLEO_ROOT/tripleo-ci
if [ -e $WORKSPACE/instackenv.json -a "$ENVIRONMENT" = "ovb" ] ; then
    echo "Running without te-broker"
    export TE_DATAFILE=$WORKSPACE/instackenv.json
    ./toci_quickstart.sh
elif [ "$ENVIRONMENT" = "ovb" ] ; then
    # We only support multi-nic at the moment
    NETISO_ENV="multi-nic"
    ./toci_quickstart.sh
else

    # Copy nodepool keys to current user
    sudo cp /etc/nodepool/id_rsa* $HOME/.ssh/
    sudo chown $USER:$USER $HOME/.ssh/id_rsa*
    chmod 0600 $HOME/.ssh/id_rsa*
    cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys
    # pre-ansible requirement
    sudo mkdir -p /root/.ssh/
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

    # finally, run quickstart
    ./toci_quickstart.sh
fi

echo "Run completed"
echo "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.logs.size_mb" "$(du -sm $WORKSPACE/logs | awk {'print $1'})" "$(date +%s)" | nc 66.187.229.172 2003 || true
