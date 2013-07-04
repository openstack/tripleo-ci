#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR
SEED_IP=`$TOCI_WORKING_DIR/incubator/scripts/get-vm-ip seed`

# Get logs from the node on exit
trap get_state_from_host EXIT

scp_noprompt root@$SEED_IP:stackrc $TOCI_WORKING_DIR/seedrc
sed -i "s/localhost/$SEED_IP/" $TOCI_WORKING_DIR/seedrc
source $TOCI_WORKING_DIR/seedrc

export no_proxy=$no_proxy,$SEED_IP

nova list

#Adds nova keypair
user-config

if [ -n "$TOCI_MACS" ]; then
  MACS=( $TOCI_MACS )
  IPS=( $TOCI_PM_IPS )
  USERS=( $TOCI_PM_USERS )
  PASSWORDS=( $TOCI_PM_PASSWORDS )
  COUNT=0
  for MAC in "${MACS[@]}"; do
    nova baremetal-node-create --pm_address=${IPS[$COUNT]} --pm_user=${USERS[$COUNT]} --pm_password=${PASSWORDS[$COUNT]} ubuntu 1 512 20 $MAC
    COUNT=$(( $COUNT + 1 ))
  done
else
  create-nodes 1 512 10 3
  export MACS=$($TOCI_WORKING_DIR/bm_poseur/bm_poseur get-macs)
  setup-baremetal 1 512 10 seed
fi

# Load images into glance
export DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder
$TOCI_WORKING_DIR/incubator/scripts/load-image notcompute.qcow2
#$TOCI_WORKING_DIR/incubator/scripts/load-image compute.qcow2

keystone role-create --name heat_stack_user

# place the bootstrap public key on host so that it can admin virt
ssh_noprompt root@$SEED_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

sudo ip route del 192.0.2.0/24 dev virbr0 || true
sudo ip route add 192.0.2.0/24 dev virbr0 via $SEED_IP

# Now we have to wait for the bm poseur to appear on the compute node and for the compute node to then
# update the scheduler
if [ -d /var/log/upstart ]; then
    wait_for 40 10 ssh_noprompt root@$SEED_IP grep 'record\\ updated\\ for' /var/log/upstart/nova-compute.log -A 100 \| grep \'Updating host status\'
else
    wait_for 40 10 ssh_noprompt root@$SEED_IP journalctl _SYSTEMD_UNIT=nova-compute.service \| grep \'record updated for\' -A 100 \| grep \'Updating host status\'
fi


# I've tried all kinds of things to wait for before doing the nova boot and can't find a reliable combination,
# I suspect I need to watch the scheduler and compute log to follow a chain of events,
# but for now I'm tired so I'm going to
sleep 67

heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/bootstack-vm.yaml overcloud -P 'notcomputeImage=notcompute'

# Just sleeping here so that we don't fill the logs with so many loops
sleep 180

heat list

wait_for 40 10 heat list \| grep CREATE_COMPLETE

# Delete the rule that prevent the Fedora bootstrap vm from forwarding
# icmp packages. If the rule doesn't exist just do nothing...
ssh_noprompt root@$SEED_IP iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true
wait_for 20 10 ping -c 1 $(nova list | grep overcloud | sed -e "s/.*=\(.*\) .*/\1/g")

# TODO : get the compute nodes working again
