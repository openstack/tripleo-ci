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
    --extra-vars validation_args='--validation-errors-nonfatal' \
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
    $LOCAL_WORKING_DIR/playbooks/$PLAYBOOK
    --extra-vars @$LOCAL_WORKING_DIR/config/release/tripleo-ci/$QUICKSTART_RELEASE.yml
    $NODES_ARGS
    $FEATURESET_CONF
    $ENV_VARS
    $EXTRA_VARS
    $DEFAULT_ARGS
    --tags $TAGS
    --skip-tags teardown-all
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
    --skip-tags teardown-all \
"

mkdir -p $LOCAL_WORKING_DIR
# TODO(gcerami) parametrize hosts
cp $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/config/testenv/${ENVIRONMENT}_hosts $LOCAL_WORKING_DIR/hosts
cp $TRIPLEO_ROOT/tripleo-ci/toci-quickstart/playbooks/* $TRIPLEO_ROOT/tripleo-quickstart/playbooks/

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


run_with_timeout $START_JOB_TIME $QUICKSTART_INSTALL_CMD --extra-vars ci_job_end_time=$(( START_JOB_TIME + REMAINING_TIME*60 )) \
    2>&1 | tee $LOGS_DIR/quickstart_install.log && exit_value=0 || exit_value=$?

# Print status of playbook run
[[ "$exit_value" == 0 ]] && echo "Playbook run passed successfully" || echo "Playbook run failed"
## LOGS COLLECTION

cat <<EOF > $LOGS_DIR/collect_logs.sh
#!/bin/bash
set -x

export NODEPOOL_PROVIDER=${NODEPOOL_PROVIDER:-''}
export STATS_TESTENV=${STATS_TESTENV:-''}
export STATS_OOOQ=${STATS_OOOQ:-''}
export START_JOB_TIME=${START_JOB_TIME:-''}
export ZUUL_PIPELINE=${ZUUL_PIPELINE:-''}
export DEVSTACK_GATE_TIMEOUT=${DEVSTACK_GATE_TIMEOUT:-''}
export REMAINING_TIME=${REMAINING_TIME:-''}
export LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
export OPT_WORKDIR=$LOCAL_WORKING_DIR
export WORKING_DIR="$HOME"
export LOGS_DIR=$WORKSPACE/logs
export VIRTUAL_ENV_DISABLE_PROMPT=1
export ANSIBLE_CONFIG=$OOOQ_DIR/ansible.cfg
export ARA_DATABASE=sqlite:///${LOCAL_WORKING_DIR}/ara.sqlite
export ZUUL_CHANGES=${ZUUL_CHANGES:-''}
export NODES_FILE=${NODES_FILE:-''}
export TOCI_JOBTYPE=$TOCI_JOBTYPE
export STABLE_RELEASE=${STABLE_RELEASE:-''}
export QUICKSTART_RELEASE=${QUICKSTART_RELEASE:-''}

set +u
source $LOCAL_WORKING_DIR/bin/activate
set -u
source $OOOQ_DIR/ansible_ssh_env.sh

/usr/bin/timeout --preserve-status 40m $QUICKSTART_COLLECTLOGS_CMD  > $LOGS_DIR/quickstart_collect_logs.log || \
    echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

cp $LOGS_DIR/undercloud/var/log/postci.txt.gz $LOGS_DIR/ || true

if [[ -e $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ]]; then
    cp $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
elif [[ -e $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ]]; then
    cp $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
elif [[ -e $LOGS_DIR/undercloud/home/$USER/undercloud_sanity.subunit.gz ]]; then
    cp $LOGS_DIR/undercloud/home/$USER/undercloud_sanity.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
fi

# Copy tempest.html to root dir
cp $LOGS_DIR/undercloud/home/$USER/tempest/tempest.html.gz ${LOGS_DIR} || true

# Copy tempest and .testrepository directory to /opt/stack/new/tempest and
# unzip
sudo mkdir -p /opt/stack/new
sudo cp -Rf $LOGS_DIR/undercloud/home/$USER/tempest /opt/stack/new || true
sudo gzip -d -r /opt/stack/new/tempest/.testrepository || true

# record the size of the logs directory
# -L, --dereference     dereference all symbolic links
# Note: tail -n +1 is to prevent the error 'Broken Pipe' e.g. 'sort: write failed: standard output: Broken pipe'

du -L -ch $LOGS_DIR/* | tail -n +1 | sort -rh | head -n 200 &> $LOGS_DIR/log-size.txt || true
EOF

if [ ${NODEPOOL_PROVIDER:-''} == 'rdo-cloud-tripleo' ] || [ ${NODEPOOL_PROVIDER:-''} =='tripleo-test-cloud-rh1' ]; then
    bash $LOGS_DIR/collect_logs.sh
    # rename script to not to run it in multinode jobs
    mv $LOGS_DIR/collect_logs.sh $LOGS_DIR/ovb_collect_logs.sh
fi

export ARA_DATABASE="sqlite:///$LOCAL_WORKING_DIR/ara.sqlite"
$LOCAL_WORKING_DIR/bin/ara generate html $LOGS_DIR/ara_oooq || true
gzip --best --recursive $LOGS_DIR/ara_oooq || true
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
