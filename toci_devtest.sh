#!/usr/bin/env bash

set -ex

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress --key-default '')

mkdir -p ~/.ssh
echo "$PRIV_SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
# Generate the public key from the private one, this is needed in other parts of devtest
ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# set DIB_REPOLOCATION_<project> for each of the projects cloned by devstack-vm-gate-wrap.sh
# built images will then pull git repository dependencies from local disk.
for GITDIR in $(ls -d /opt/stack/new/*/.git) ; do
    PROJDIR=${GITDIR%/.git}
    PROJNAME=${PROJDIR##*/}
    PROJNAME=${PROJNAME//[-.]/_}
    export DIB_REPOLOCATION_$PROJNAME=$PROJDIR
done

function get_state_from_host(){
    mkdir -p $WORKSPACE/logs/
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET -o PasswordAuthentication=no $2 \
        "( set -x ; ps -ef ; df -h ; uptime ; sudo netstat -lpn ; sudo iptables-save ; sudo ovs-vsctl show ; ip addr ; dpkg -l || rpm -qa) > /var/log/host_info.txt 2>&1 ; sudo tar -czf - --exclude=udev/hwdb.bin --exclude=selinux/targeted /var/log /etc || true" > $WORKSPACE/logs/$1_logs.tgz
}

export TRIPLEO_ROOT=/opt/stack/new/
source $TRIPLEO_ROOT/tripleo-incubator/scripts/devtest_variables.sh
devtest_setup.sh --trash-my-machine
devtest_ramdisk.sh
echo "Running $TRIPLEO_TEST test run"
trap "get_state_from_host seed root@$SEED_IP" EXIT
devtest_seed.sh
export no_proxy=${no_proxy:-},192.0.2.1
source $TRIPLEO_ROOT/tripleo-incubator/seedrc
if [ "seed" != "$TRIPLEO_TEST" ]; then
    trap "get_state_from_host seed root@$SEED_IP ; get_state_from_host undercloud heat-admin@192.0.2.2" EXIT
    devtest_undercloud.sh $TE_DATAFILE
fi
if [ "overcloud" = "$TRIPLEO_TEST" ]; then
    devtest_overcloud.sh $TE_DATAFILE
fi
echo 'Run completed.'
