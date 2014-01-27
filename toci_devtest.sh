#!/usr/bin/env bash

set -ex

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)

mkdir -p ~/.ssh
echo $PRIV_SSH_KEY | base64 -d > ~/.ssh/id_rsa
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

export TRIPLEO_ROOT=/opt/stack/new/
source $TRIPLEO_ROOT/tripleo-incubator/scripts/devtest_variables.sh
devtest_setup.sh --trash-my-machine
devtest_ramdisk.sh
devtest_seed.sh
echo 'Run completed.'
