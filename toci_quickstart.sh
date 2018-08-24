#!/usr/bin/env bash
set -eux
set -o pipefail
export ANSIBLE_NOCOLOR=1
[[ -n ${STATS_TESTENV:-''} ]] && export STATS_TESTENV=$(( $(date +%s) - STATS_TESTENV ))
export STATS_OOOQ=$(date +%s)

LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
WORKING_DIR="$HOME"
LOGS_DIR=$WORKSPACE/logs

source $TRIPLEO_ROOT/tripleo-ci/scripts/oooq_common_functions.sh

## Signal to toci_gate_test.sh we've started by
touch /tmp/toci.started

export DEFAULT_ARGS="--extra-vars local_working_dir=$LOCAL_WORKING_DIR \
    --extra-vars virthost=$UNDERCLOUD \
    --inventory $LOCAL_WORKING_DIR/hosts \
    --extra-vars tripleo_root=$TRIPLEO_ROOT \
    --extra-vars working_dir=$WORKING_DIR \
    --skip-tags "tripleo-validations,teardown-all" \
"

# --install-deps arguments installs deps and then quits, no other arguments are
# processed.
QUICKSTART_PREPARE_CMD="
    ./quickstart.sh
    --install-deps
"

QUICKSTART_VENV_CMD="
    ./quickstart.sh
    --bootstrap
    --no-clone
    --working-dir $LOCAL_WORKING_DIR
    --playbook noop.yml
    --retain-inventory
    $UNDERCLOUD
"

QUICKSTART_INSTALL_CMD="
    $LOCAL_WORKING_DIR/bin/ansible-playbook
    --tags $TAGS
"

QUICKSTART_COLLECTLOGS_CMD="$LOCAL_WORKING_DIR/bin/ansible-playbook \
    $LOCAL_WORKING_DIR/playbooks/collect-logs.yml \
    -vv \
    --extra-vars @$LOCAL_WORKING_DIR/config/release/tripleo-ci/$QUICKSTART_RELEASE.yml \
    $FEATURESET_CONF \
    $ENV_VARS \
    $EXTRA_VARS \
    $DEFAULT_ARGS \
    --extra-vars @$COLLECT_CONF \
    --extra-vars artcl_collect_dir=$LOGS_DIR \
    --tags all \
"

export QUICKSTART_DEFAULT_RELEASE_ARG="--extra-vars @$LOCAL_WORKING_DIR/config/release/tripleo-ci/${DISTRIBUTION:-CentOS}-${DISTRIBUTION_MAJOR_VERSION:-7}/$QUICKSTART_RELEASE.yml"

declare -A RELEASE_ARGS=()

if [[ -f "$RELEASES_FILE_OUTPUT" ]]; then

    source $RELEASES_FILE_OUTPUT

    declare -A RELEASE_ARGS=(
        ["multinode-undercloud.yml"]=$(get_extra_vars_from_release \
            $UNDERCLOUD_INSTALL_RELEASE $UNDERCLOUD_INSTALL_HASH)
        ["multinode-undercloud-upgrade.yml"]=$(get_extra_vars_from_release \
            $UNDERCLOUD_TARGET_RELEASE $UNDERCLOUD_TARGET_HASH)
        ["multinode-overcloud-prep.yml"]=$(get_extra_vars_from_release \
            $OVERCLOUD_DEPLOY_RELEASE $OVERCLOUD_DEPLOY_HASH)
        ["multinode-overcloud.yml"]=$(get_extra_vars_from_release \
            $OVERCLOUD_DEPLOY_RELEASE $OVERCLOUD_DEPLOY_HASH)
        ["multinode-overcloud-update.yml"]=$(get_extra_vars_from_release \
            $OVERCLOUD_DEPLOY_RELEASE $OVERCLOUD_DEPLOY_HASH)
        ["multinode-overcloud-upgrade.yml"]=$(get_extra_vars_from_release \
            $OVERCLOUD_TARGET_RELEASE $OVERCLOUD_TARGET_HASH)
        ["multinode-validate.yml"]=$(get_extra_vars_from_release \
            $OVERCLOUD_TARGET_RELEASE $OVERCLOUD_TARGET_HASH)
    )

fi

declare -A PLAYBOOKS_ARGS=(
    ["baremetal-full-overcloud.yml"]=" --extra-vars validation_args='--validation-errors-nonfatal' "
    ["multinode-overcloud.yml"]=" --extra-vars validation_args='--validation-errors-nonfatal' "
    ["multinode.yml"]=" --extra-vars validation_args='--validation-errors-nonfatal' "
)

mkdir -p $LOCAL_WORKING_DIR
# TODO(gcerami) parametrize hosts
cp $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/${ENVIRONMENT}_hosts $LOCAL_WORKING_DIR/hosts
pushd $TRIPLEO_ROOT/tripleo-quickstart/

$QUICKSTART_PREPARE_CMD
$QUICKSTART_VENV_CMD

# Only ansible-playbook command will be used from this point forward, so we
# need some variables from quickstart.sh
OOOQ_DIR=$TRIPLEO_ROOT/tripleo-quickstart/
export OPT_WORKDIR=$LOCAL_WORKING_DIR
export ANSIBLE_CONFIG=$OOOQ_DIR/ansible.cfg
export ARA_DATABASE="sqlite:///${LOCAL_WORKING_DIR}/ara.sqlite"
export VIRTUAL_ENV_DISABLE_PROMPT=1
# Workaround for virtualenv issue https://github.com/pypa/virtualenv/issues/1029
set +u
source $LOCAL_WORKING_DIR/bin/activate
set -u
source $OOOQ_DIR/ansible_ssh_env.sh
[[ -n ${STATS_OOOQ:-''} ]] && export STATS_OOOQ=$(( $(date +%s) - STATS_OOOQ ))

# Debug step capture env variables
if [[ "$PLAYBOOK_DRY_RUN" == "1" ]]; then
    echo "-- Capture Environment Variables Used ---------"
    echo "$(env)" | tee -a $LOGS_DIR/toci_env_args_output.log
    declare -p | tee -a $LOGS_DIR/toci_env_args_output.log
fi

echo "-- Playbooks Output --------------------------"
for playbook in $PLAYBOOKS; do
    echo "$QUICKSTART_INSTALL_CMD \
        ${RELEASE_ARGS[$playbook]:=$QUICKSTART_DEFAULT_RELEASE_ARG} \
        $NODES_ARGS \
        $FEATURESET_CONF \
        $ENV_VARS \
        $EXTRA_VARS \
        $VXLAN_VARS \
        $DEFAULT_ARGS \
        $LOCAL_WORKING_DIR/playbooks/$playbook ${PLAYBOOKS_ARGS[$playbook]:-}" \
        | sed  's/--/\n--/g' \
        | tee -a $LOGS_DIR/playbook_executions.log
    echo "# --------------------------------------- " \
        | tee -a $LOGS_DIR/playbook_executions.log
done

if [[ "$PLAYBOOK_DRY_RUN" == "1" ]]; then
    exit_value=0
else
    ## LOGS COLLECTION PREPARE
    create_collect_logs_script

    for playbook in $PLAYBOOKS; do
        echo "${RELEASE_ARGS[$playbook]:=$QUICKSTART_DEFAULT_RELEASE_ARG}"
        run_with_timeout $START_JOB_TIME $QUICKSTART_INSTALL_CMD \
           "${RELEASE_ARGS[$playbook]:=$QUICKSTART_DEFAULT_RELEASE_ARG}" \
           $NODES_ARGS \
           $FEATURESET_CONF \
           $ENV_VARS \
           $EXTRA_VARS \
           $VXLAN_VARS \
           $DEFAULT_ARGS \
           --extra-vars ci_job_end_time=$(( START_JOB_TIME + REMAINING_TIME*60 )) \
            $LOCAL_WORKING_DIR/playbooks/$playbook "${PLAYBOOKS_ARGS[$playbook]:-}" \
            2>&1 | tee -a $LOGS_DIR/quickstart_install.log && exit_value=0 || exit_value=$?

        # Print status of playbook run
        [[ "$exit_value" == 0 ]] && echo "Playbook run of $playbook passed successfully"
        [[ "$exit_value" != 0 ]] && echo "Playbook run of $playbook failed" && break
    done

    [[ "$exit_value" == 0 ]] && echo "Playbook run passed successfully" || echo "Playbook run failed"

    ## LOGS COLLECTION RUN (if applicable)
    if [[ "${NODEPOOL_PROVIDER:-''}" == "rdo-cloud-tripleo" ]] || \
       [[ "${NODEPOOL_PROVIDER:-''}" == "vexxhost-rdo-ca-ymq-1" ]] ; then
        if [[ "$TOCI_JOBTYPE" =~ "ovb" ]]; then
            bash $LOGS_DIR/collect_logs.sh
            # rename script to not to run it in multinode jobs
            mv $LOGS_DIR/collect_logs.sh $LOGS_DIR/ovb_collect_logs.sh
        fi
    fi


fi

popd

sudo unbound-control dump_cache > /tmp/dns_cache.txt
sudo chown ${USER}: /tmp/dns_cache.txt
cat /tmp/dns_cache.txt | gzip - > $LOGS_DIR/dns_cache.txt.gz

if [[ "$PERIODIC" == 1 && -e $WORKSPACE/hash_info.sh ]] ; then
    echo export JOB_EXIT_VALUE=$exit_value >> $WORKSPACE/hash_info.sh
fi

mkdir -p $LOGS_DIR/quickstart_files
find $LOCAL_WORKING_DIR -maxdepth 1 -type f -not -name "*sqlite" | while read i; do gzip -cf $i > $LOGS_DIR/quickstart_files/$(basename $i).txt.gz; done
echo 'Quickstart completed.'
exit $exit_value
