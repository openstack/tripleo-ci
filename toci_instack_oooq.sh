#!/usr/bin/env bash
set -eux
set -o pipefail
# TODO(sshnaidm): when transitioning to oooq, remove this file
# move only necessary to toci_gate_test.sh

## Signal to toci_gate_test.sh we've started by
touch /tmp/toci.started

exit_value=0
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
elif [[ "$TOCI_JOBTYPE" =~ "-nonha-tempest" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal_pacemaker.yml"}
    EXTRA_ARGS="$EXTRA_ARGS -e test_ping=false -e tempest_config=true -e run_tempest=true -e test_regex='.*' -e enable_cinder_backup=true"
elif [[ "$TOCI_JOBTYPE" =~ "-ha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/ha.yml"}
elif [[ "$TOCI_JOBTYPE" =~ "-nonha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
else
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
fi

# TODO(sshnaidm): to move these variables to jobs yaml config files (see above)
if [[ "${STABLE_RELEASE}" =~ ^(liberty|mitaka)$ ]] ; then
    export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config-mitaka-and-below.yaml"
else
    export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml"
fi
export OPT_WORKDIR=${WORKSPACE}/.quickstart
export OOOQ_LOGS=${WORKSPACE}/logs/oooq
export OOO_WORKDIR_LOCAL=$HOME
export OOOQ_DEFAULT_ARGS=" --working-dir $OPT_WORKDIR --retain-inventory -T none -e working_dir=$OOO_WORKDIR_LOCAL -R ${STABLE_RELEASE:-master}"
export OOOQ_ARGS=" --config $CONFIG \
-e @$TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/ovb-settings.yml \
-e tripleo_root=$TRIPLEO_ROOT \
-e undercloud_hieradata_override_file=~/quickstart-hieradata-overrides.yaml"
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
# TODO(sshnaidm): fix inventory and collect-logs roles with prepares ssh.config.ansible,
sed -i '/ansible_user: stack/d' $TRIPLEO_ROOT/tripleo-quickstart/roles/common/defaults/main.yml

$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh  --bootstrap --no-clone \
        -t all \
        $PLAYBOOK $OOOQ_ARGS \
        $OOOQ_DEFAULT_ARGS undercloud 2>&1 \
        | tee $OOOQ_LOGS/quickstart_install.log && exit_value=0 || exit_value=$?

# TODO(sshnaidm): to include this in general ovb-playbook(?)
if [[ -e ${OOO_WORKDIR_LOCAL}/overcloudrc ]]; then
    $TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --bootstrap \
        $OOOQ_DEFAULT_ARGS \
        -t all  \
        --playbook tempest.yml  \
        --extra-vars run_tempest=True  \
        -e test_regex='.*smoke' $EXTRA_ARGS \
         undercloud 2>&1 | tee $OOOQ_LOGS/quickstart_tempest.log && tempest_exit_value=0 || tempest_exit_value=$?
fi

# TODO(sshnaidm): to prepare collect-logs role for tripleo-ci specific paths
# and remove this function then
collect_oooq_logs

# TODO(sshnaidm): fix this either in role or quickstart.sh
# it will not duplicate logs from undercloud and 127.0.0.2
sed -i 's/hosts: all:!localhost/hosts: all:!localhost:!127.0.0.2/' $OPT_WORKDIR/playbooks/collect-logs.yml ||:

# TODO(sshnaidm): to move postci functionality into collect-logs role
$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --bootstrap --no-clone \
        $OOOQ_DEFAULT_ARGS \
        $OOOQ_ARGS \
        --playbook collect-logs.yml \
        -e artcl_collect_dir=$OOOQ_LOGS/collected_logs \
        undercloud > $OOOQ_LOGS/quickstart_collectlogs.log || true

export ARA_DATABASE="sqlite:///${OPT_WORKDIR}/ara.sqlite"
$OPT_WORKDIR/bin/ara generate $OOOQ_LOGS/ara || true
popd

echo 'Run completed.'
# TODO(sshnaidm): remove this when we're sure there's enough space
# Watch free space, the outage could break jobs
sudo df -h
if [[ "$exit_value" != 0 ]]; then
    exit $exit_value
elif [[ "$tempest_exit_value" != 0 ]]; then
    exit $tempest_exit_value
fi
