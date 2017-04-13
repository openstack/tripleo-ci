#!/usr/bin/env bash
set -eux
set -o pipefail

## Signal to toci_gate_test.sh we've started by
touch /tmp/toci.started

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

# TODO(sshnaidm): remove this immediately when settings are in yaml files
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
#source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash

# Clear out any puppet modules on the node placed their by infra configuration
sudo rm -rf /etc/puppet/modules/*

# Copy nodepool public key to jenkins user
sudo cp /etc/nodepool/id_rsa.pub $HOME/.ssh/
sudo chown $USER:$USER $HOME/.ssh/id_rsa.pub

# TODO(sshnaidm): To create tripleo-ci special yaml config files in oooq
# for every TOCI_JOBTYPE, i.e. ovb-nonha-ipv6.yml
if [[ "$TOCI_JOBTYPE" =~ "multinode" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_CI_DIR/tripleo-ci/scripts/quickstart/multinode-settings.yml"}
elif [[ "$TOCI_JOBTYPE" =~ "-ha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/ha.yml"}
elif [[ "$TOCI_JOBTYPE" =~ "-nonha" ]]; then
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
else
    CONFIG=${CONFIG:-"$TRIPLEO_ROOT/tripleo-quickstart/config/general_config/minimal.yml"}
fi

# This needs to be set for tripleo.sh's pingtest to be passed the correct template
# See tripleo.sh $TENANT_PINGTEST_TEMPLATE for more details
MULTINODE_ENV_NAME=${MULTINODE_ENV_NAME/-oooq/}

# Generate a scenario quickstart ARGs snippet
if [[ "$TOCI_JOBTYPE" =~ "scenario" ]]; then
    SCENARIO_ARGS="--extra-vars @${SCENARIO_ARGS:-$TRIPLEO_ROOT/tripleo-quickstart-extras/config/general_config/${TOCI_JOBTYPE/-oooq*/}.yml}"
fi

# Add jenkin user's SSH key to root authorized_keys for Ansible to run
sudo mkdir -p /root/.ssh/
sudo cp ${HOME}/.ssh/authorized_keys /root/.ssh/
sudo chmod 0600 /root/.ssh/authorized_keys
sudo chown root:root /root/.ssh/authorized_keys

# TODO(bkero): Use an ansible role to create this file
sudo yum install -y qemu-img
qemu-img create -f qcow2 $HOME/overcloud-full.qcow2 1G

# Bootstrap the subnodes
$TRIPLEO_CI_DIR/tripleo-ci/scripts/tripleo.sh --bootstrap-subnodes 2>&1 | sudo dd of=/var/log/bootstrap-subnodes.log || (tail -n 50 /var/log/bootstrap-subnodes.log && false)

# Install our test cert so SSL tests work
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert-ipv6.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

# TODO(sshnaidm): to move these variables to jobs yaml config files (see above)
if [[ "${STABLE_RELEASE}" =~ ^(liberty|mitaka)$ ]] ; then
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

export OOOQ_ARGS=" --working-dir ${OPT_WORKDIR} \
                   -e working_dir=${OOO_WORKDIR_LOCAL} \
                   --bootstrap \
                   --no-clone \
                   --retain-inventory \
                   --tags build,undercloud-setup,undercloud-scripts,undercloud-install,undercloud-post-install,overcloud-scripts,overcloud-deploy,overcloud-validate \
                   --teardown none \
                   --release ${STABLE_RELEASE:-master} \
                   --config ${CONFIG} \
                   --extra-vars @$TRIPLEO_ROOT/tripleo-quickstart/config/release/tripleo-ci/${STABLE_RELEASE:-master}.yml \
                   ${SCENARIO_ARGS:-""} \
                   --playbook multinode-playbook.yml \
                   --requirements requirements.txt \
                   --requirements quickstart-extras-requirements.txt \
                   127.0.0.2"

#shopt -s extglob
#rm -rf /opt/stack/new/!(tripleo-ci|tripleo-quickstart|tripleo-quickstart-extras)
# End of cleaning
# HINT: If there's no enough space, remove swap file in /root/

# TODO(sshnaidm): when collect-logs role will have the same functionality,
# replace postci function with this role (see in the end of file).
trap "exit_val=\$?; [ \$exit_val != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci \$exit_val 2>&1 | awk '{ print strftime(\"%Y-%m-%d %H:%M:%S.000\"), \"|\", \$0; fflush(); }' > $WORKSPACE/logs/postci.log 2>&1" EXIT

mkdir -p $WORKSPACE/logs

export IP_DEVICE=${IP_DEVICE:-"eth0"}
MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')
MY_IP_eth1=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}') || MY_IP_eth1=""

export http_proxy=""
undercloud_net_range="192.168.24."
undercloud_services_ip=$undercloud_net_range"1"
undercloud_haproxy_public_ip=$undercloud_net_range"2"
undercloud_haproxy_admin_ip=$undercloud_net_range"3"
export no_proxy=$undercloud_services_ip,$undercloud_haproxy_public_ip,$undercloud_haproxy_admin_ip,$MY_IP,$MY_IP_eth1

[[ ! -e $OPT_WORKDIR ]] && mkdir -p $OPT_WORKDIR && sudo chown -R ${USER}: $OPT_WORKDIR
sudo mkdir $OOOQ_LOGS && sudo chown -R ${USER}: $OOOQ_LOGS

# make the requirements point to local checkout of tripleo-quickstart-extras
echo "file://${TRIPLEO_ROOT}/tripleo-quickstart-extras/#egg=tripleo-quickstart-extras" > ${TRIPLEO_ROOT}/tripleo-quickstart/quickstart-extras-requirements.txt

# TODO(bkero): Correct this with a dynamic inventory configuration
sed -i 's/^undercloud ansible_host=undercloud/undercloud ansible_host=127.0.0.2/' $TRIPLEO_ROOT/tripleo-ci/scripts/hosts

cp $TRIPLEO_ROOT/tripleo-ci/scripts/hosts $OPT_WORKDIR/hosts
cp $TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/*y*ml $TRIPLEO_ROOT/tripleo-quickstart/playbooks/
$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --install-deps

pushd $TRIPLEO_ROOT/tripleo-quickstart/

# We wrap the quickstart call in a timeout, so that we can get logs if the
# deploy hangs.  90m = 90 minutes = 1.5 hours
/usr/bin/timeout --preserve-status 90m \
    $TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh \
    ${OOOQ_ARGS} 2>&1 | tee $OOOQ_LOGS/quickstart_install.log && exit_value=0 || exit_value=$?


sudo journalctl -u os-collect-config | sudo tee /var/log/os-collect-config.txt

tar -czf $OOOQ_LOGS/quickstart.tar.gz $OPT_WORKDIR

# TODO(sshnaidm): fix this either in role or quickstart.sh
# it will not duplicate logs from undercloud and 127.0.0.2
sed -i 's/hosts: all:!localhost/hosts: all:!localhost:!127.0.0.2/' $OPT_WORKDIR/playbooks/collect-logs.yml || true

$TRIPLEO_ROOT/tripleo-quickstart/quickstart.sh --bootstrap --no-clone \
        $OOOQ_DEFAULT_ARGS \
        --playbook collect-logs.yml \
        -e artcl_collect_dir=$OOOQ_LOGS \
        -e @$TRIPLEO_ROOT/tripleo-ci/scripts/quickstart/multinode-settings.yml \
        --config $CONFIG \
        -e tripleo_root=$TRIPLEO_ROOT \
        127.0.0.2 &> $OOOQ_LOGS/quickstart_collectlogs.log ||
        echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

export ARA_DATABASE="sqlite:///${OPT_WORKDIR}/ara.sqlite"
$OPT_WORKDIR/bin/ara generate html $OOOQ_LOGS/ara || true
popd

echo 'Run completed.'
# TODO(sshnaidm): remove this when we're sure there's enough space
# Watch free space, the outage could break jobs
sudo df -h
exit $exit_value
