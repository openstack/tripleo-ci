#!/usr/bin/env bash
set -eux
set -o pipefail
export ANSIBLE_NOCOLOR=1

LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
WORKING_DIR="$HOME"
LOGS_DIR=$WORKSPACE/logs


## Signal to toci_gate_test.sh we've started by
touch /tmp/toci.started

export DEFAULT_ARGS="
    --no-clone
    --working-dir $LOCAL_WORKING_DIR
    --retain-inventory
    --teardown none
    --extra-vars tripleo_root=$TRIPLEO_ROOT
    --extra-vars working_dir=$WORKING_DIR
    --extra-vars validation_args='--validation-errors-nonfatal'
    --release tripleo-ci/$QUICKSTART_RELEASE
"

# --install-deps arguments installs deps and then quits, no other arguments are
# processed.
QUICKSTART_PREPARE_CMD="
    ./quickstart.sh
    --install-deps
"

QUICKSTART_INSTALL_CMD="
    ./quickstart.sh
    --bootstrap
    --tags $TAGS
    $DEFAULT_ARGS
    $NODES_ARGS
    $ENV_VARS
    $FEATURESET_CONF
    $EXTRA_VARS
    --playbook $PLAYBOOK
    $UNDERCLOUD
"

QUICKSTART_COLLECTLOGS_CMD="
    ./quickstart.sh
    $DEFAULT_ARGS
    --extra-vars @$COLLECT_CONF
    --tags all
    $NODES_ARGS
    $ENV_VARS
    $FEATURESET_CONF
    $EXTRA_VARS
    --playbook collect-logs.yml
    --extra-vars artcl_collect_dir=$LOGS_DIR
    $UNDERCLOUD
"
mkdir -p $LOCAL_WORKING_DIR
# TODO(gcerami) parametrize hosts
cp $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/${ENVIRONMENT}_hosts $LOCAL_WORKING_DIR/hosts
cp $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/playbooks/* $TRIPLEO_ROOT/tripleo-quickstart/playbooks/

pushd $TRIPLEO_ROOT/tripleo-quickstart/

$QUICKSTART_PREPARE_CMD

# Use $REMAINING_TIME of infra to calculate maximum time for remaning part of job
# Leave 15 minutes for quickstart logs collection
REMAINING_TIME=${REMAINING_TIME:-180}
TIME_FOR_DEPLOY=$(( REMAINING_TIME - ($(date +%s) - START_JOB_TIME)/60 - 10 ))
/usr/bin/timeout --preserve-status ${TIME_FOR_DEPLOY}m  $QUICKSTART_INSTALL_CMD \
    2>&1 | tee $LOGS_DIR/quickstart_install.log && exit_value=0 || exit_value=$?
# Print status of playbook run
[[ "$exit_value" == 0 ]] && echo "Playbook run passed successfully" || echo "Playbook run failed"
## LOGS COLLECTION

# workaround to stop collecting same host twice
sed -i 's/hosts: all:!localhost/hosts: all:!localhost:!127.0.0.2/' $LOCAL_WORKING_DIR/playbooks/collect-logs.yml || true

$QUICKSTART_COLLECTLOGS_CMD \
    > $LOGS_DIR/quickstart_collect_logs.log || \
    echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

# Temporary workaround to make postci log visible as it was before
cp $LOGS_DIR/undercloud/var/log/postci.txt.gz $LOGS_DIR/ || true

if [[ -e $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ]]; then
    cp $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
elif [[ -e $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ]]; then
    cp $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
fi

# Copy tempest.html to root dir
cp $LOGS_DIR/undercloud/home/$USER/tempest/tempest.html.gz ${LOGS_DIR} || true

# Copy tempest and .testrepository directory to /opt/stack/new/tempest and
# unzip
sudo mkdir -p /opt/stack/new
sudo cp -Rf $LOGS_DIR/undercloud/home/jenkins/tempest /opt/stack/new || true
sudo gzip -d -r /opt/stack/new/tempest/.testrepository || true

export ARA_DATABASE="sqlite:///$LOCAL_WORKING_DIR/ara.sqlite"
$LOCAL_WORKING_DIR/bin/ara generate html $LOGS_DIR/ara_oooq || true
gzip --best --recursive $LOGS_DIR/ara_oooq || true
popd

# record the size of the logs directory
# -L, --dereference     dereference all symbolic links
du -L -ch $LOGS_DIR/* | sort -rh | head -n 200 &> $LOGS_DIR/log-size.txt || true

if [[ "$PERIODIC" == 1 && -e $WORKSPACE/hash_info.sh ]] ; then
    if [[ "$exit_value" == 0 ]]; then
        echo "REPORTING SUCCESS TO DLRN API"
        SUCCESS="true"
    else
        echo "REPORTING FAILURE TO DLRN API"
        SUCCESS="false"
    fi

    source $WORKSPACE/hash_info.sh
    sudo pip install dlrnapi-client
    dlrnapi --url $DLRNAPI_URL \
        --username review_rdoproject_org \
        report-result \
        --commit-hash $COMMIT_HASH \
        --distro-hash $DISTRO_HASH \
        --job-id $TOCI_JOBTYPE \
        --info-url "https://logs.rdoproject.org/${LOG_PATH}" \
        --timestamp $(date +%s) \
        --success $SUCCESS
fi

echo 'Quickstart completed.'
exit $exit_value
