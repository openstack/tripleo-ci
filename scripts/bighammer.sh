#!/usr/bin/bash
#
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

set -ex

[ -n "$1" ] || ( echo "Usage : $0 <num-runs> <sim-runs>" && exit 1 )

# Creates a template image (if it doesn't exist), then runs an
# overcloud ci job <num-runs> times, <sim-runs> simultaneously.

IMAGE=CentOS-7-x86_64-GenericCloud
USER=centos

# makes some assumptions but good enough for now
nova keypair-add --pub-key ~/.ssh/id_rsa.pub bighammer || true

function tapper(){
    set -x
    NODENAME=test-node-$1

    nova boot --image $IMAGE --flavor undercloud --key-name bighammer $NODENAME
    #trap "nova delete $NODENAME" RETURN ERR
    sleep 60
    if [ "$(nova show $NODENAME | awk '/status/ {print $4}')" != "ACTIVE" ] ; then
          nova show $NODENAME
          return 1
    fi

    IP=$(nova show $NODENAME | awk '/private network/ {print $5}')
    PORTID=$(neutron port-list | grep "$IP\>" | awk '{print $2}')

    FLOATINGIP=$(nova floating-ip-create $EXTNET | grep public | awk '{print $2}')

    [ -z "$FLOATINGIP" ] && echo "No Floating IP..." && exit 1
    #trap "nova delete $NODENAME || true ; sleep 20 ; nova floatingip-delete $FLOATINGIP" RETURN ERR

    nova floating-ip-associate $NODENAME $FLOATINGIP
    sleep 20
    ssh -tt $USER@$FLOATINGIP <<EOF
        set -xe
        sudo yum install -y git screen
        sudo mkdir -p /opt/stack/new
        sudo chown centos /opt/stack/new
        git clone https://git.openstack.org/openstack-infra/tripleo-ci /opt/stack/new/tripleo-ci
        cd /opt/stack/new/tripleo-ci
        DISTRIBUTION=CentOS DISTRIBUTION_MAJOR_VERSION=7 OVERRIDE_ZUUL_BRANCH= ZUUL_BRANCH=master WORKSPACE=/tmp TOCI_JOBTYPE=nonha DEVSTACK_GATE_TIMEOUT=180 ./toci_gate_test.sh
        exit 0
EOF
    set +x
    date
    echo "JOB DONE"
}

TODO=$1
SIM=$2
DONE=0
[ -e logs ] && mv logs logs-$(date +%s)
mkdir -p logs
while true; do
    [ $DONE -ge $TODO ] && echo "Done" && break
    jobs
    if [ $(jobs | wc -l) -lt $SIM ] ; then
        DONE=$((DONE+1))
        echo "Starting job $DONE"
        tapper $DONE &> logs/job-$DONE.log &
    fi
    sleep 10 # Lets not hammer the API all in one go
done

# Wait for the last process to finish
wait
