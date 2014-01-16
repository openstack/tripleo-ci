#!/usr/bin/env bash

set -e

. toci_functions.sh

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)

echo $PRIV_SSH_KEY | base64 -d > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

source ~/tripleo/tripleo-incubator/scripts/devtest_variables.sh
devtest_setup.sh --trash-my-machine
devtest_ramdisk.sh
devtest_seed.sh
echo 'Run completed.'
