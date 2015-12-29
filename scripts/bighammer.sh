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

[ -n "$1" ] || ( echo "Usage : $0 <baseimageid> <num-runs> <sim-runs>" && exit 1 )

# Creates a template image (if it doesn't exist), then runs an
# overcloud ci job <num-runs> times, <sim-runs> simultaneously.

IMAGEID=$1

USER=fedora
if nova image-list | grep $IMAGEID | grep -i ubuntu ; then
    USER=ubuntu
fi

# makes some assumptions but good enough for now
nova keypair-add --pub-key ~/.ssh/id_rsa.pub bighammer || true

NETLIST=$(neutron net-list)
DEFAULTNET=$(echo "$NETLIST" | grep default-net | awk '{print $2}')
TESTNET=$(echo "$NETLIST" | grep tripleo-bm-test | awk '{print $2}')
EXTNET=$(echo "$NETLIST" | grep ext-net | awk '{print $2}')

TEMPLATENAME="$IMAGEID-template"
if !  nova image-list | grep $TEMPLATENAME ; then
    nova boot --image $IMAGEID --flavor m1.large --nic net-id=$DEFAULTNET --key-name bighammer template-builder
    sleep 60

    IP=$(nova show template-builder | awk '/default-net/ {print $5}')
    PORTID=$(neutron port-list | grep "$IP\>" | awk '{print $2}')

    FLOATINGIPOUT=$(neutron floatingip-create $EXTNET)
    FLOATINGIP=$(echo "$FLOATINGIPOUT" | grep floating_ip_address | awk '{print $4}')
    FLOATINGIPID=$(echo "$FLOATINGIPOUT" | grep " id " | awk '{print $4}')

    neutron floatingip-associate $FLOATINGIPID $PORTID
    sleep 90
    ssh -t -t $USER@$FLOATINGIP <<EOF
        set -ex

        sudo mkdir /etc/nodepool
        sudo chmod 0777 /etc/nodepool

        mkdir tmp
        sudo yum install -y git || sudo apt-get install -y git
        git clone https://git.openstack.org/openstack-infra/project-config tmp/config

        sudo cp -r tmp/config/nodepool/scripts /opt/nodepool-scripts
        sudo chmod -R a+rx /opt/nodepool-scripts

        cd /opt/nodepool-scripts
        sudo yum install -y libxml2-devel libxslt-devel
        sudo ./prepare_node_tripleo.sh
        exit 0
EOF

    nova image-create --poll template-builder $TEMPLATENAME
    nova delete template-builder
    sleep 20
    neutron floatingip-delete $FLOATINGIPID
fi

function tapper(){
    set -x
    NODENAME=test-node-$1

    nova boot --image $TEMPLATENAME --flavor m1.large --nic net-id=$DEFAULTNET --nic net-id=$TESTNET --key-name bighammer $NODENAME
    trap "nova delete $NODENAME" RETURN ERR
    sleep 180
    if [ "$(nova show $NODENAME | awk '/status/ {print $4}')" != "ACTIVE" ] ; then
          nova show $NODENAME
          return 1
    fi

    IP=$(nova show $NODENAME | awk '/default-net/ {print $5}')
    PORTID=$(neutron port-list | grep "$IP\>" | awk '{print $2}')

    FLOATINGIPOUT=$(neutron floatingip-create $EXTNET)
    FLOATINGIP=$(echo "$FLOATINGIPOUT" | grep floating_ip_address | awk '{print $4}')
    FLOATINGIPID=$(echo "$FLOATINGIPOUT" | grep " id " | awk '{print $4}')

    [ -z "$FLOATINGIP" ] && echo "No Floating IP..." && exit 1
    trap "nova delete $NODENAME || true ; sleep 20 ; neutron floatingip-delete $FLOATINGIPID" RETURN ERR

    neutron floatingip-associate $FLOATINGIPID $PORTID
    sleep 120
    ssh fedora@$FLOATINGIP sudo cp ~fedora/.ssh/authorized_keys ~jenkins/.ssh/authorized_keys
    date
    ssh -t jenkins@$FLOATINGIP <<EOF
        set -xe
        export PYTHONUNBUFFERED=true
        export DEVSTACK_GATE_TIMEOUT=240
        export DEVSTACK_GATE_TEMPEST=0
        export DEVSTACK_GATE_EXERCISES=0
        export GEARDSERVER=172.16.3.254
        export DIB_COMMON_ELEMENTS="common-venv stackuser pypi-openstack"
        export TRIPLEO_TEST=overcloud

        sudo chown -hR jenkins /opt/git
        function gate_hook {
            bash -xe /opt/stack/new/tripleo-ci/toci_gate_test.sh
        }
        export -f gate_hook

        export ZUUL_BRANCH=master
        export WORKSPACE=~/workspace
        export GIT_ORIGIN=git://git.openstack.org
        export ZUUL_PROJECT=openstack-infra/devstack-gate
        export BRANCH=master
        export ZUUL_URL=http://zuul.openstack.org/p

        mkdir -p ~/workspace
        cd ~/workspace
        git clone git://git.openstack.org/openstack-infra/devstack-gate
        cp devstack-gate/devstack-vm-gate-wrap.sh ./safe-devstack-vm-gate-wrap.sh
        ./safe-devstack-vm-gate-wrap.sh
EOF
    set +x
    date
    echo "JOB DONE"
}

TODO=$2
SIM=$3
DONE=0
[ -e logs ] && mv logs logs-$(date +%s)
mkdir -p logs
while true; do
    [ $DONE -ge $TODO ] && echo "Done" && break
    sleep 60 # Lets not hammer the API all in one go
    jobs
    if [ $(jobs | wc -l) -lt $SIM ] ; then
        DONE=$((DONE+1))
        echo "Starting job $DONE"
        tapper $DONE &> logs/job-$DONE.log &
    fi
done

# Wait for the last process to finish
wait
