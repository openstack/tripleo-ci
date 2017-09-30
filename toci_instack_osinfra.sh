#!/usr/bin/env bash
set -eux
set -o pipefail

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

export IP_DEVICE=${IP_DEVICE:-"eth0"}


source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash
start_metric "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.ci.total.seconds"

mkdir -p $WORKSPACE/logs

MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')
MY_IP_eth1=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}') || MY_IP_eth1=""

export http_proxy=""
undercloud_net_range="192.168.24."
undercloud_services_ip=$undercloud_net_range"1"
undercloud_haproxy_public_ip=$undercloud_net_range"2"
undercloud_haproxy_admin_ip=$undercloud_net_range"3"
export no_proxy=$undercloud_services_ip,$undercloud_haproxy_public_ip,$undercloud_haproxy_admin_ip,$MY_IP,$MY_IP_eth1

# Copy nodepool ssh keys for the current user because apparently id_rsa.pub is
# missing from ~/.ssh
cp /etc/nodepool/id_rsa  ~/.ssh/
cp /etc/nodepool/id_rsa.pub  ~/.ssh/

# Remove the anything on the infra image template that might interfere with CI
# Note for tripleo-quickstart: this task is already managed in tripleo-ci-setup-playbook.yml
sudo yum remove -y facter puppet hiera puppetlabs-release rdo-release centos-release-[a-z]*
sudo rm -rf /etc/puppet /etc/hiera.yaml

# Setup delorean
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-setup

dummy_ci_repo

# Install all of the repositories we need
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup

# Install some useful/necessary packages
# TODO(amoralej): remove after https://review.openstack.org/#/c/468872/ is merged
sudo pip uninstall certifi -y || true
sudo pip uninstall urllib3 -y || true
sudo pip uninstall requests -y || true
sudo rpm -e --nodeps python2-certifi || :
sudo rpm -e --nodeps python2-urllib3 || :
sudo rpm -e --nodeps python2-requests || :
sudo yum -y install python-requests python-urllib3
# Open up port for delorean yum repo server
sudo iptables -I INPUT -p tcp --dport 8766 -j ACCEPT

trap "exit_val=\$?; [ \$exit_val != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci \$exit_val 2>&1 | awk '{ print strftime(\"%Y-%m-%d %H:%M:%S.000\"), \"|\", \$0; fflush(); }' > $WORKSPACE/logs/postci.log 2>&1; stop_dstat" EXIT

# Tempreverts/cherry-picks/pins go here.  For example:
# temprevert tripleo-common af27127508eabf2b6873713e5e1507fa92b5f5b3 1623606

delorean_build_and_serve

# Since we've moved a few commands from this spot before the wget, we need to
# sleep a few seconds in order for the SimpleHTTPServer to get setup.
sleep 3

layer_ci_repo

echo_vars_to_deploy_env
# We need to override $OVERCLOUD_VALIDATE_ARGS to be empty so that the
# validations that check for the correct number of ironic nodes does not fail
# the deploy.
echo 'export OVERCLOUD_VALIDATE_ARGS=""' >> $TRIPLEO_ROOT/tripleo-ci/deploy.env

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

# TODO: remove later, this is for live debugging
sudo cat /etc/nodepool/*

if [ -s /etc/nodepool/sub_nodes_private ]; then
    for ip in $(cat /etc/nodepool/sub_nodes_private); do
        sanitized_address=$(sanitize_ip_address $ip)
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo yum remove -y facter puppet hiera puppetlabs-release rdo-release centos-release-[a-z]*
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo rm -rf /etc/puppet /etc/hiera.yaml
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo yum -y install wget
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo wget http://$MY_IP:8766/current/delorean-ci.repo -O /etc/yum.repos.d/delorean-ci.repo
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo sed -i -e \"s%baseurl=.*%baseurl=http://$MY_IP:8766/current/%\" /etc/yum.repos.d/delorean-ci.repo
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo sed -i -e 's%priority=.*%priority=1%' /etc/yum.repos.d/delorean-ci.repo
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo mkdir -p $TRIPLEO_ROOT/tripleo-ci
        scp $SSH_OPTIONS -i /etc/nodepool/id_rsa \
            $TRIPLEO_ROOT/tripleo-ci/deploy.env ${sanitized_address}:
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo cp deploy.env $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done

    subnodes_scp_deploy_env

    if [ "$OVERCLOUD_MAJOR_UPGRADE" = "1" ]; then
        # If upgrading the overcloud, we want to bootstrap the subnodes at the
        # release defined by $UPGRADE_RELEASE
        # Save the current value of $STABLE_RELEASE
        CURR_STABLE_RELEASE=$STABLE_RELEASE
        # Set $STABLE_RELEASE to the release at which we want to start the subnodes
        STABLE_RELEASE=$UPGRADE_RELEASE
        # Update and copy deploy.env to the subnodes
        echo_vars_to_deploy_env
        subnodes_scp_deploy_env
        # Reset $STABLE_RELEASE
        STABLE_RELEASE=$CURR_STABLE_RELEASE
        # Update the local deploy.env only so that the undercloud will install
        # at the current $STABLE_RELEASE
        echo_vars_to_deploy_env

        # Disable the delorean-ci repo for the initial overcloud deploy, as
        # ZUUL_REFS, and thus the contents of delorean-ci can only reference
        # patches for the current branch, not UPGRADE_RELEASE
        if [ -s /etc/nodepool/sub_nodes_private ]; then
          for ip in $(cat /etc/nodepool/sub_nodes_private); do
            ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
              sudo sed -i -e \"s/enabled=1/enabled=0/\" /etc/yum.repos.d/delorean-ci.repo
          done
        fi
    fi

    $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --multinode-setup
    echo "INFO: Check /var/log/boostrap-subnodes.log for boostrap subnodes output"
    if [ "$DO_BOOTSTRAP_SUBNODES" = "1" ]; then
        $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --bootstrap-subnodes 2>&1 | sudo dd of=/var/log/bootstrap-subnodes.log || (tail -n 50 /var/log/bootstrap-subnodes.log && false)
    fi

    # This needs to be done after the --multinode-setup otherwise /etc/hosts will
    # get overwritten
    hosts=$(mktemp)
    cat >$hosts<<EOF
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1        localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
    for ip in $(cat /etc/nodepool/sub_nodes_private); do
        sanitized_address=$(sanitize_ip_address $ip)
        scp $SSH_OPTIONS -i /etc/nodepool/id_rsa $hosts ${sanitized_address}:hosts
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo cp hosts /etc/hosts
    done
fi

# Install our test cert so SSL tests work
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert-ipv6.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

# The mitaka branch of instack-undercloud does not have the net-config override
# feature, so we need to add a dummy interface so that os-net-config can
# add it to the br-ctlplane bridge.
if [ "$STABLE_RELEASE" = "mitaka" ]; then
    if ! ip link show ci-dummy; then
        sudo ip link add ci-dummy type dummy
    fi
fi

# Use $REMAINING_TIME of infra to calculate maximum time for remaning part of job
# Leave 10 minutes for postci function
REMAINING_TIME=${REMAINING_TIME:-180}
TIME_FOR_DEPLOY=$(( REMAINING_TIME - ($(date +%s) - START_JOB_TIME)/60 - 10 ))
/usr/bin/timeout --preserve-status ${TIME_FOR_DEPLOY}m $TRIPLEO_ROOT/tripleo-ci/scripts/deploy.sh
exit 0
echo 'Run completed.'
