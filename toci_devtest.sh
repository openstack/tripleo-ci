#!/usr/bin/env bash

set -eux

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

export PATH=/sbin:/usr/sbin:$PATH

# Place a file in the logs directory containing details from the current job,
# we can later use this to test if nodes are being reused, bug 1370275.
mkdir -p $WORKSPACE/logs/
if [ -e $WORKSPACE/logs/already-used ] ; then
    echo "This node was used already"
    cat $WORKSPACE/logs/already-used
    exit 1
fi
echo -e "$LOG_PATH\n$ZUUL_UUID" > $WORKSPACE/logs/already-used

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

# Pin to a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to pin too
# $3 : bug id of reason for the pin (used to skip revert if found in commit
#      that triggers ci).
function pin(){
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=/opt/stack/new/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping pin because bug fix $3 was found in git message."
        return 0
    fi

    pushd /opt/stack/new/$1
    git reset --hard $2
    popd
}

# Add temporary reverts here e.g.
# temprevert <projectname> <commit-hash-to-revert> <bugnumber>

TRIPLEO_DEBUG=${TRIPLEO_DEBUG:-}
PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress --key-default '')
SSH_USER=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-user --type username)
HOST_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key host-ip --type netaddress)
ENV_NUM=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key env-num --type int)

if [ "$TRIPLEO_DEBUG" = "1" ]; then
    TRIPLEO_DEBUG="--debug-logging"
fi

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

    # devstack-gate leaves some of these repo's in a detached head state (bug 1364345)
    # dib defaults to using master so we have to explicitly set it.
    # We can't use the git sha1 in the REPOREF because git didn't get the
    # ability to fetch a sha1 ref until v1.8.3 (precise has 1.7.9), instead
    # we create and use a branch
    git --git-dir=$GITDIR --work-tree=$PROJDIR checkout -b ci-branch
    export DIB_REPOREF_$PROJNAME=ci-branch
done

# Cherry-pick a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : Gerrit refspec to cherry pick
function cherrypick(){
    local PROJ_NAME=$1
    local REFSPEC=$2
    local GIT_REPO_LOCATION="DIB_REPOLOCATION_${PROJ_NAME//[^A-Za-z0-9]/_}"

    pushd ${!GIT_REPO_LOCATION}
    git fetch https://review.openstack.org/openstack/$PROJ_NAME "$REFSPEC" && git cherry-pick FETCH_HEAD || true
    popd
}

# Add cherrypick's here e.g.
# cherrypick <projectname> <gerrit-refspec>
# https://review.openstack.org/#/c/173236/
# patch to fix the pin qemu-img on Fedora 21
cherrypick tripleo-image-elements refs/changes/36/173236/1
#https://review.openstack.org/173014 (update packages first)
cherrypick diskimage-builder refs/changes/14/173014/3

# Create a local pypi mirror of python packages that are being tested
# TODO : Should probably split this out into a seperate file
export TRIPLEO_ROOT=/opt/stack/new/
MIRROR_ROOT=~/.cache/image-create/pypi/mirror/

# We don't want this left behind if ever we start reusing VM's
rm -rf $MIRROR_ROOT

# echo's out a project name from a ref
# $1 : e.g. openstack/nova:master:refs/changes/87/64787/3 returns nova
function filterref(){
    PROJ=${1%%:*}
    PROJ=${PROJ##*/}
    echo $PROJ
}

# Test if this is a project we want to build a package for
# NB. keep the leading and trailing spaces, keeps the matching simpler
BUILDPACKAGES=" os-apply-config os-cloud-config os-collect-config os-net-config \
os-refresh-config oslo.concurrency oslo.config oslo.db oslo.i18n \
oslo.log oslo.messaging oslo.middleware oslo.rootwrap oslo.serialization \
oslo.utils oslo.vmware pbr python-ceilometerclient python-cinderclient \
python-glanceclient python-heatclient python-ironicclient \
python-keystoneclient python-neutronclient python-novaclient \
python-openstackclient python-saharaclient python-swiftclient \
python-troveclient python-zaqarclient "
function buildpackage(){
    [[ "$BUILDPACKAGES" =~ " $1 "  ]] && return 0
    return 1
}

# If this is a job to test master of everything we get a list of all git repo's
if [ -z "${ZUUL_CHANGES:-}" ] ; then
    echo "No change ids specified, building all projects in $TRIPLEO_ROOT"
    ZUUL_CHANGES=$(find $TRIPLEO_ROOT -maxdepth 2 -type d -name .git -printf "%h ")
fi

mkdir -p $MIRROR_ROOT
cd $MIRROR_ROOT
# pip doesn't use the index from the extra index in order to query for case
# mismatches, so any requirments with mismatches need to be pulled into
# the local repo
export PIP_INDEX_URL="http://$PYPIMIRROR/pypi/simple/"
# markupsafe : Case incorrect in jinja2 (fixed upstream but not released)
# pbr is required as .pydistutils.cfg doesn't support a extra-index-url
# sysv-ipc   : The "-" is a "_" on pypi.o.o
# xstatic-*  : Case incorrect (https://review.openstack.org/#/c/130287)
ALWAYS_MIRROR_PKGS="markupsafe pbr sysv-ipc xstatic xstatic-angular xstatic-angular-cookies xstatic-angular-mock xstatic-bootstrap-datepicker xstatic-bootstrap-scss xstatic-d3 xstatic-hogan xstatic-font-awesome xstatic-jasmine xstatic-jquery xstatic-jquery-migrate xstatic-jquery.quicksearch xstatic-jquery.tablesorter xstatic-jquery-ui xstatic-jsencrypt xstatic-qunit xstatic-rickshaw xstatic-spin"
for P in $ALWAYS_MIRROR_PKGS ; do
    mkdir -p $P
    pip install -d $P $P
done


# Config for our CI pypi mirror
export no_proxy=127.0.0.1,$PYPIMIRROR
export PIP_INDEX_URL="http://127.0.0.1:8765/"
export PIP_EXTRA_INDEX_URL="http://$PYPIMIRROR/pypi/simple/"

# Start our http pypi mirror
cd $MIRROR_ROOT
python -m SimpleHTTPServer 8765 1>$TRIPLEO_ROOT/pypi_mirror.log 2>$TRIPLEO_ROOT/pypi_mirror_error.log &
sleep 2

# loop through each of the projects listed in ZUUL_CHANGES if it is a project we
# typically pull in as a pip dependency then build it and add it to the mirror,
# e.g. ZUUL_CHANGES=openstack/cinder:master:refs/changes/61/71461/4^opensta...
for PROJ in ${ZUUL_CHANGES//^/ } ; do

    PROJ=$(filterref $PROJ)
    buildpackage $PROJ || continue

    PROJDIR=$TRIPLEO_ROOT/$PROJ
    cd $PROJDIR

    # We don't want this left behind if ever we start reusing VM's
    rm -rf $PROJDIR/dist

    # We're building pre-release packages but not all the tripleo pip installs
    # include --pre so giving them a fake release number
    git tag -f -m 999.999.999 999.999.999

    # build and get the name of the package
    python setup.py sdist
    cd dist
    PACKAGE=$(ls *)

    # Place package in the mirror along with the index pip is expecting
    mkdir -p $MIRROR_ROOT/$PROJ
    mv $PROJDIR/dist/$PACKAGE $MIRROR_ROOT/$PROJ/$PACKAGE
done

# Everything is now in place to build images using the local repositories

function get_state_from_host(){
    local SSH_CMD
    SSH_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=Verbose -o PasswordAuthentication=no'
    TEMPDIR=$(ssh ${SSH_OPTIONS} $2 mktemp -d)
    REMOTE_FILENAME=$TEMPDIR/$1_logs.tar.xz
    MKTAR_CMD="( set -x;
                 export PATH=\$PATH:/sbin
                 ps -efZ;
                 ls -Z /var/run/;
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
               sudo XZ_OPT=-3 tar -cJf $REMOTE_FILENAME \
                 --exclude=udev/hwdb.bin \
                 --exclude=selinux/targeted \
                 --exclude=etc/services \
                 --exclude=etc/pki \
                 /var/log /etc /mnt/state/var/log"
    ssh ${SSH_OPTIONS} $2 "${MKTAR_CMD}"
    scp ${SSH_OPTIONS} $2:$REMOTE_FILENAME $WORKSPACE/logs/$1_logs.tar.xz
    # Extract the logs so we can add them to logstash.openstack.org for analysis
    mkdir $WORKSPACE/logs/$1_logs
    if tar xJvf  $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs var/log/host_info.txt --strip-components=2; then
        if tar tf $WORKSPACE/logs/$1_logs.tar.xz  var/log/upstart >/dev/null 2>&1; then
            tar xJvf  $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs var/log/upstart --strip-components=3
            # Extract logs for individual services from syslog to the logs directory
            tar xJvf $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs "var/log/syslog" --strip-components=2
            for SERVICE in $(awk 'gsub(":|\\[.*", " ", $5) {print $5}' $WORKSPACE/logs/$1_logs/syslog | sort -u) ; do
                awk "\$5 ~ \"^${SERVICE}[:\\\\[]\"" $WORKSPACE/logs/$1_logs/syslog > $WORKSPACE/logs/$1_logs/${SERVICE//\//_}.log
            done
            rm -f $WORKSPACE/logs/$1_logs/syslog
        else
            if tar tf $WORKSPACE/logs/$1_logs.tar.xz "var/log/audit/audit.log" >/dev/null 2>&1; then
                tar xJvf $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs "var/log/audit/audit.log" --strip-components=3
            fi
            tar xJvf $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs "var/log/journal/*/system.journal" --strip-components=4
            for UNIT in $(journalctl --file $WORKSPACE/logs/$1_logs/system.journal -F _SYSTEMD_UNIT) ; do
                journalctl --file $WORKSPACE/logs/$1_logs/system.journal -u $UNIT > $WORKSPACE/logs/$1_logs/${UNIT/.service/.log}
            done
            rm -f $WORKSPACE/logs/$1_logs/system.journal
        fi
    else
        echo Could not unpack $WORKSPACE/logs/$1_logs.tar.xz
        ls -l $WORKSPACE/logs/$1_logs.tar.xz
        file $WORKSPACE/logs/$1_logs.tar.xz
    fi
    if tar tf $WORKSPACE/logs/$1_logs.tar.xz  mnt/state/var/log >/dev/null 2>&1; then
        mkdir $WORKSPACE/logs/$1_logs/mnt
        tar xJvf  $WORKSPACE/logs/$1_logs.tar.xz -C $WORKSPACE/logs/$1_logs/mnt mnt/state/var/log --strip-components=4
    fi
}

# Kill any VM's in the test env that we may have started, freeing up RAM
# for other tests running on the TE host.
function destroy_vms(){
    ssh $SSH_USER@$HOST_IP virsh destroy seed_${ENV_NUM} || true
    for i in $(seq 0 14) ; do
        ssh $SSH_USER@$HOST_IP virsh destroy baremetalbrbm${ENV_NUM}_${i} || true
    done
}

function get_state_from_hosts(){
    get_state_from_host seed root@$SEED_IP &> $WORKSPACE/logs/get_state_from_host.log
    # If this isn't a seed job get logs of running instances on the seed
    if [ "seed" != "$TRIPLEO_TEST" ]; then
        source $TRIPLEO_ROOT/tripleo-incubator/seedrc || true
        nova list
        heat stack-show $TRIPLEO_TEST
        heat resource-list $TRIPLEO_TEST
        heat event-list $TRIPLEO_TEST
        for INSTANCE in $(nova list | grep ACTIVE | awk '{printf"%s=%s\n", $4, $12}') ; do
            IP=${INSTANCE//*=}
            NAME=${INSTANCE//=*}
            NAME=${NAME%-*}
            get_state_from_host $NAME heat-admin@$IP &>> $WORKSPACE/logs/get_state_from_host.log || true
        done
    fi
}

function cleanup(){
    get_state_from_hosts || true
    destroy_vms &> $WORKSPACE/logs/destroy_vms.log
}

source $TRIPLEO_ROOT/tripleo-incubator/scripts/devtest_variables.sh
devtest_setup.sh --trash-my-machine
devtest_ramdisk.sh
echo "Running $TRIPLEO_TEST test run"
trap "cleanup" EXIT
devtest_seed.sh $TRIPLEO_DEBUG
export no_proxy=${no_proxy:-},192.0.2.1
source $TRIPLEO_ROOT/tripleo-incubator/seedrc
if [ "undercloud" = "$TRIPLEO_TEST" ]; then
    devtest_undercloud.sh $TRIPLEO_DEBUG $TE_DATAFILE
fi
if [ "overcloud" = "$TRIPLEO_TEST" ]; then
    # Register more nodes with the seed.
    setup-baremetal --service-host seed --nodes <(jq '.nodes - [.nodes[0]]' $TE_DATAFILE)
    devtest_overcloud.sh $TRIPLEO_DEBUG
fi
echo 'Run completed.'
