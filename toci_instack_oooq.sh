#!/usr/bin/env bash
set -eux
set -o pipefail
# TODO(sshnaidm): when transitioning to oooq, remove this file
# move only necessary to toci_gate_test.sh

## Signal to toci_gate_test.sh we've started by
touch /tmp/toci.started

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

# TODO(sshnaidm): remove this immediately when settings are in yaml files
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
#source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash

EXTRA_ARGS=""

# TODO(sshnaidm): To create tripleo-ci special yaml config files in oooq
# for every TOCI_JOBTYPE, i.e. ovb-nonha-ipv6.yml

if [[ $CONTAINERS == 1 ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/containers_minimal.yml"}
    EXTRA_ARGS="$EXTRA_ARGS -e run_tempest=false"
elif [[ "$TOCI_JOBTYPE" =~ "-nonha-tempest" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal_pacemaker.yml"}
elif [[ "$TOCI_JOBTYPE" =~ "-ha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/ha.yml"}
elif [[ "$TOCI_JOBTYPE" =~ "-nonha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
else
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
fi

# TODO(sshnaidm): to move these variables to jobs yaml config files (see above)
if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
    export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config-mitaka-and-below.yaml"
else
    export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml"
fi
# force ansible to not output console color codes
export ANSIBLE_NOCOLOR=1
export OPT_WORKDIR=${WORKSPACE}/.quickstart
export OOOQ_LOGS=${WORKSPACE}/logs/oooq
export OOO_WORKDIR_LOCAL=$HOME
export OOOQ_DEFAULT_ARGS=" --working-dir $OPT_WORKDIR --retain-inventory -T none -e working_dir=$OOO_WORKDIR_LOCAL -R ${STABLE_RELEASE:-master}"
export OOOQ_ARGS=" --config $CONFIG \
-e @$TRIPLEO_ROOT/tripleo-quickstart/config/release/tripleo-ci/${STABLE_RELEASE:-master}.yml \
-e @$TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/ovb-settings.yml \
-e @$TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/${TOCI_JOBTYPE}.yml \
-e tripleo_root=$TRIPLEO_ROOT"
export PLAYBOOK=" --playbook ovb-playbook.yml --requirements requirements.txt --requirements quickstart-extras-requirements.txt "

# TODO(sshnaidm): when collect-logs role will have the same functionality,
# replace postci function with this role (see in the end of file).
trap "exit_val=\$?; [ \$exit_val != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci \$exit_val 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' > $WORKSPACE/logs/postci.log 2>&1" EXIT

[[ ! -e $OPT_WORKDIR ]] && mkdir -p $OPT_WORKDIR && sudo chown -R ${USER}: $OPT_WORKDIR
sudo mkdir -p $OOOQ_LOGS && sudo chown -R ${USER}: $OOOQ_LOGS
# TODO(sshnaidm): check why it's not cloned
[[ ! -e $TRIPLEO_ROOT/tripleo-quickstart ]] && /usr/zuul-env/bin/zuul-cloner --workspace ${TRIPLEO_ROOT} https://git.openstack.org/openstack tripleo-quickstart
[[ ! -e $TRIPLEO_ROOT/tripleo-quickstart-extras ]] && /usr/zuul-env/bin/zuul-cloner --workspace ${TRIPLEO_ROOT} https://git.openstack.org/openstack tripleo-quickstart-extras

# make the requirements point to local checkout of tripleo-quickstart-extras
echo "file://${TRIPLEO_ROOT}/tripleo-quickstart-extras/#egg=tripleo-quickstart-extras" > ${TRIPLEO_ROOT}/tripleo-quickstart/quickstart-extras-requirements.txt

cp $TRIPLEO_ROOT/tripleo-ci/scripts/hosts $OPT_WORKDIR/hosts

cp $TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/*y*ml $TRIPLEO_ROOT/tripleo-quickstart/playbooks/
$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --install-deps

pushd $TRIPLEO_ROOT/tripleo-quickstart/

# Use $REMAINING_TIME of infra to calculate maximum time for remaning part of job
# Leave 15 minutes for quickstart logs collection
REMAINING_TIME=${REMAINING_TIME:-180}
TIME_FOR_DEPLOY=$(( REMAINING_TIME - ($(date +%s) - START_JOB_TIME)/60 - 15 ))
/usr/bin/timeout --preserve-status ${TIME_FOR_DEPLOY}m $TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh  --bootstrap --no-clone \
        -t all \
        $PLAYBOOK $OOOQ_ARGS \
        $OOOQ_DEFAULT_ARGS $EXTRA_ARGS undercloud 2>&1 \
        | tee $OOOQ_LOGS/quickstart_install.log && exit_value=0 || exit_value=$?

tar -czf $OOOQ_LOGS/quickstart.tar.gz $OPT_WORKDIR

# TODO(sshnaidm): fix this either in role or quickstart.sh
# it will not duplicate logs from undercloud and 127.0.0.2
sed -i 's/hosts: all:!localhost/hosts: all:!localhost:!127.0.0.2/' $OPT_WORKDIR/playbooks/collect-logs.yml || true

# TODO(sshnaidm): to move postci functionality into collect-logs role
$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --bootstrap --no-clone \
        $OOOQ_DEFAULT_ARGS \
        $OOOQ_ARGS \
        --playbook collect-logs.yml \
        -e artcl_collect_dir=$OOOQ_LOGS \
        undercloud &> $OOOQ_LOGS/quickstart_collectlogs.log ||
        echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

# Copy testrepository.subunit to root log dir in order to be consumed by
# openstack-health
cp $OOOQ_LOGS/undercloud/home/jenkins/tempest/testrepository.subunit.gz ${WORKSPACE}/logs || true

export ARA_DATABASE="sqlite:///${OPT_WORKDIR}/ara.sqlite"
$OPT_WORKDIR/bin/ara generate html $OOOQ_LOGS/ara || true
popd

echo 'Run completed.'
exit $exit_value
