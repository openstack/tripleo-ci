#!/usr/bin/env bash

set -eux

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

export PATH=/sbin:/usr/sbin:$PATH

# Revert a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to revert
# $3 : bug id of reason for revert (used to skip revert if found in commit
#      that triggers ci).
function temprevert(){
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=/opt/stack/new/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping temprevert because bug fix $3 was found in git message."
        return 0
    fi

    pushd /opt/stack/new/$1
    git revert --no-edit $2 || true
    git reset --hard HEAD # Do this incase the revert fails (hopefully because its not needed)
    popd
}

# Add temporary reverts here e.g.
# temprevert <projectname> <commit-hash-to-revert> <bugnumber>

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress --key-default '')

# The default pip timeout (15 seconds) isn't long enough to cater for our
# occasional network blips, bug #1292141
export PIP_DEFAULT_TIMEOUT=${PIP_DEFAULT_TIMEOUT:-60}

mkdir -p ~/.ssh
echo "$PRIV_SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
# Generate the public key from the private one, this is needed in other parts of devtest
ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
# Ensure there is a newline after the last key
echo >> ~/.ssh/authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# set DIB_REPOLOCATION_<project> for each of the projects cloned by devstack-vm-gate-wrap.sh
# built images will then pull git repository dependencies from local disk.
for GITDIR in $(ls -d /opt/stack/new/*/.git) ; do
    PROJDIR=${GITDIR%/.git}
    PROJNAME=${PROJDIR##*/}
    PROJNAME=${PROJNAME//[^A-Za-z0-9]/_}
    export DIB_REPOLOCATION_$PROJNAME=$PROJDIR
done

function get_state_from_host(){
    mkdir -p $WORKSPACE/logs/
    local SSH_CMD
    SSH_CMD='( set -x;
               export PATH=$PATH:/sbin
               ps -efZ;
               df -h;
               uptime;
               sudo netstat -lpn;
               sudo iptables-save;
               sudo ovs-vsctl show;
               ip addr;
               free -h;
               dpkg -l || rpm -qa;
               sudo os-collect-config --print;
             ) 2>&1 | sudo dd of=/var/log/host_info.txt &> /dev/null;
             sudo XZ_OPT=-3 tar -cJf - \
               --exclude=udev/hwdb.bin \
               --exclude=selinux/targeted \
               --exclude=etc/services \
               --exclude=etc/pki \
               /var/log /etc /mnt/state/var/log || true'
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=QUIET \
        -o PasswordAuthentication=no $2 \
        "${SSH_CMD}" > $WORKSPACE/logs/$1_logs.tar.xz

    # Extract the logs so we can add them to logstash.openstack.org for analysis
    mkdir $WORKSPACE/logs/$1_logs
    tar xJvf  $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs var/log/host_info.txt --strip-components=2
    if tar tf $WORKSPACE/logs/$1_logs.tar.xz  var/log/upstart >/dev/null 2>&1; then
        tar xJvf  $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs var/log/upstart --strip-components=3
    else
        tar xJvf $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs "var/log/journal/*/system.journal" --strip-components=4
        for UNIT in $(journalctl --file $WORKSPACE/logs/$1_logs/system.journal -F _SYSTEMD_UNIT) ; do
            journalctl --file $WORKSPACE/logs/$1_logs/system.journal -u $UNIT > $WORKSPACE/logs/$1_logs/${UNIT/.service/.log}
        done
        rm -f $WORKSPACE/logs/$1_logs/system.journal
    fi
}

function get_state_from_hosts(){
    get_state_from_host seed root@$SEED_IP &> $WORKSPACE/logs/get_state_from_host.log
    # If this isn't a seed job get logs of running instances on the seed
    if [ "seed" != "$TRIPLEO_TEST" ]; then
        source $TRIPLEO_ROOT/tripleo-incubator/seedrc || true
        nova list
        for INSTANCE in $(nova list | grep ACTIVE | awk '{printf"%s=%s\n", $4, $12}') ; do
            IP=${INSTANCE//*=}
            NAME=${INSTANCE//=*}
            NAME=${NAME%-*}
            get_state_from_host $NAME heat-admin@$IP &>> $WORKSPACE/logs/get_state_from_host.log || true
        done
    fi
}

export TRIPLEO_ROOT=/opt/stack/new/
source $TRIPLEO_ROOT/tripleo-incubator/scripts/devtest_variables.sh
devtest_setup.sh --trash-my-machine
devtest_ramdisk.sh
echo "Running $TRIPLEO_TEST test run"
trap "get_state_from_hosts" EXIT
devtest_seed.sh
export no_proxy=${no_proxy:-},192.0.2.1
source $TRIPLEO_ROOT/tripleo-incubator/seedrc
if [ "undercloud" = "$TRIPLEO_TEST" ]; then
    devtest_undercloud.sh $TE_DATAFILE
fi
if [ "overcloud" = "$TRIPLEO_TEST" ]; then
    # Register more nodes with the seed.
    setup-baremetal --service-host seed --nodes <(jq '.nodes - [.nodes[0]]' $TE_DATAFILE)
    devtest_overcloud.sh
fi
echo 'Run completed.'
