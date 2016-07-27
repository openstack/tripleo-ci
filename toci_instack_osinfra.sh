#!/usr/bin/env bash
set -eux

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

export IP_DEVICE=${IP_DEVICE:-"eth0"}


source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash
start_metric "tripleo.ci.total.seconds"

mkdir -p $WORKSPACE/logs

MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')
MY_IP_eth1=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}')

export http_proxy=""
export no_proxy=192.0.2.1,$MY_IP,$MY_IP_eth1

# Copy nodepool ssh keys for the jenkins user because apparently id_rsa.pub is
# missing from /home/jenkins/.ssh
cp /etc/nodepool/id_rsa  ~/.ssh/
cp /etc/nodepool/id_rsa.pub  ~/.ssh/

# Clear out any puppet modules on the node placed their by infra configuration
sudo rm -rf /etc/puppet/modules/*

# Setup delorean
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-setup

dummy_ci_repo

# Install all of the repositories we need
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup

# Install some useful/necessary packages
sudo yum -y install wget python-simplejson dstat yum-plugin-priorities
# Need to reinstall requests since it's rm'd in toci_gate_test.sh
sudo rpm -e --nodeps python-requests || :
sudo yum -y install python-requests
# Open up port for delorean yum repo server
sudo iptables -I INPUT -p tcp --dport 8766 -j ACCEPT

trap "[ \$? != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' > $WORKSPACE/logs/postci.log 2>&1" EXIT

delorean_build_and_serve

# Since we've moved a few commands from this spot before the wget, we need to
# sleep a few seconds in order for the SimpleHTTPServer to get setup.
sleep 3

layer_ci_repo

create_dib_vars_for_puppet

echo_vars_to_deploy_env
# We need to override $OVERCLOUD_VALIDATE_ARGS to be empty so that the
# validations that check for the correct number of ironic nodes does not fail
# the deploy.
echo 'export OVERCLOUD_VALIDATE_ARGS=""' >> $TRIPLEO_ROOT/tripleo-ci/deploy.env

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

# This will remove any puppet configuration done by infra setup
sudo yum -y remove puppet facter hiera

# TODO: remove later, this is for live debugging
sudo cat /etc/nodepool/*

if [ -s /etc/nodepool/sub_nodes ]; then
    for ip in $(cat /etc/nodepool/sub_nodes); do
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
            $TRIPLEO_ROOT/tripleo-ci/deploy.env $ip:
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo cp deploy.env $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done

    $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --multinode

    # This needs to be done after the --multinode setup otherwise /etc/hosts will
    # get overwritten
    hosts='127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6'
    for ip in $(cat /etc/nodepool/sub_nodes); do
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            /bin/bash -c "echo \"$hosts\" > hosts"
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo cp hosts /etc/hosts
    done
fi

# Add a simple system utilisation logger process
sudo dstat -tcmndrylpg --output /var/log/dstat-csv.log >/dev/null &
# Install our test cert so SSL tests work
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

$TRIPLEO_ROOT/tripleo-ci/scripts/deploy.sh

exit 0
echo 'Run completed.'
