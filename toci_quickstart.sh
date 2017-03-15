#!/usr/bin/env bash
set -eux
set -o pipefail
export ANSIBLE_NOCOLOR=1

LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
WORKING_DIR="$HOME"
LOGS_DIR=$WORKSPACE/logs
QUICKSTART_INSTALL_TIMEOUT=$((DEVSTACK_GATE_TIMEOUT-10))


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
    --release tripleo-ci/${STABLE_RELEASE:-master}
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
    $FEATURESET_CONF
    $EXTRA_VARS
    --playbook $PLAYBOOK
    $UNDERCLOUD
"

QUICKSTART_COLLECTLOGS_CMD="
    ./quickstart.sh
    $DEFAULT_ARGS
    $EXTRA_VARS
    --extra-vars @$COLLECT_CONF
    --tags all
    $NODES_ARGS
    $FEATURESET_CONF
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

# Save time for log collection
/usr/bin/timeout --preserve-status ${QUICKSTART_INSTALL_TIMEOUT}m $QUICKSTART_INSTALL_CMD \
    2>&1 | tee $LOGS_DIR/quickstart_install.log && exit_value=0 || exit_value=$?

## LOGS COLLECTION

# workaround to stop collecting same host twice
sed -i 's/hosts: all:!localhost/hosts: all:!localhost:!127.0.0.2/' $LOCAL_WORKING_DIR/playbooks/collect-logs.yml || true

$QUICKSTART_COLLECTLOGS_CMD \
    > $LOGS_DIR/quickstart_collect_logs.log || \
    echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

export ARA_DATABASE="sqlite:///$LOCAL_WORKING_DIR/ara.sqlite"
$LOCAL_WORKING_DIR/bin/ara generate $LOGS_DIR/ara || true
popd

echo 'Quickstart completed.'
exit $exit_value
