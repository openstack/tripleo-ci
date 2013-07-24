#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR
SEED_IP=`$TOCI_WORKING_DIR/tripleo-incubator/scripts/get-vm-ip seed`

# Get logs from the node on exit
trap get_state_from_host EXIT

scp_noprompt root@$SEED_IP:stackrc $TOCI_WORKING_DIR/seedrc
sed -i "s/localhost/$SEED_IP/" $TOCI_WORKING_DIR/seedrc
source $TOCI_WORKING_DIR/seedrc

export no_proxy=$no_proxy,$SEED_IP

# wait for a successful os-refresh-config
wait_for 60 10 ssh_noprompt root@$SEED_IP ls /opt/stack/boot-stack/init-neutron.ok

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list
user-config #Adds nova keypair

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
  create-nodes 1 1024 30 5
  export MACS=$($TOCI_WORKING_DIR/bm_poseur/bm_poseur get-macs)
  setup-baremetal 1 1024 30 seed
fi

# Load images into glance
export DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder
$TOCI_WORKING_DIR/tripleo-incubator/scripts/load-image undercloud.qcow2

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

# TODO : find a better solution then guessing what the controller-address will be
sed -i $TOCI_WORKING_DIR/tripleo-heat-templates/undercloud-vm.yaml -e 's/\(.*controller-address:\).*/\1 192.0.2.2/'
heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/undercloud-vm.yaml -P "PowerUserName=$(whoami)" undercloud

# Just sleeping here so that we don't fill the logs with so many loops
sleep 180

heat list

wait_for 40 20 heat list \| grep CREATE_COMPLETE

# Delete the rule that prevent the Fedora bootstrap vm from forwarding
# packets. If the rule doesn't exist just do nothing...
ssh_noprompt root@$SEED_IP iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true
wait_for 20 15 ping -c 1 $(nova list | grep undercloud | sed -e "s/.*=\(.*\) .*/\1/g")

export UNDERCLOUD_IP=$(nova list | grep ctlplane | sed -e "s/.*=\([0-9.]*\).*/\1/")
cp $TOCI_WORKING_DIR/tripleo-incubator/undercloudrc $TOCI_WORKING_DIR/undercloudrc
source $TOCI_WORKING_DIR/undercloudrc
sed -i -e "s/\$UNDERCLOUD_IP/$UNDERCLOUD_IP/g" $TOCI_WORKING_DIR/undercloudrc
export no_proxy=$no_proxy,$UNDERCLOUD_IP

# If using Fedora keep using F18 for now
if [[ "$TOCI_DISTROELEMENT" =~ fedora ]] ; then
    export DIB_CLOUD_IMAGES=http://mattdm.fedorapeople.org/cloud-images
    export DIB_RELEASE=Fedora18
    export BASE_IMAGE_FILE=Fedora18-Cloud-$TOCI_ARCH-latest.qcow2
fi

# Make the tripleo image elements accessible to diskimage-builder
export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements

if [ "$TOCI_DO_OVERCLOUD" = "1" ] ; then
    $TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -a $TOCI_DIB_ARCH -o overcloud-control $TOCI_DISTROELEMENT boot-stack heat-localip heat-cfntools neutron-network-node stackuser
fi

# wait for a successful os-refresh-config
wait_for 60 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP ls /opt/stack/boot-stack/init-neutron.ok

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

if [ "$TOCI_DO_OVERCLOUD" != "1" ] ; then
    exit 0
fi

user-config
setup-baremetal 1 1024 30 undercloud
ssh_noprompt heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

$TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -a $TOCI_DIB_ARCH -o overcloud-compute $TOCI_DISTROELEMENT nova-compute nova-kvm neutron-openvswitch-agent heat-localip heat-cfntools stackuser

if [ -d /var/log/upstart ]; then
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP grep 'record\\ updated\\ for' /var/log/upstart/nova-compute.log -A 100 \| grep \'Updating host status\'
else
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo journalctl _SYSTEMD_UNIT=nova-compute.service \| grep \'record updated for\' -A 100 \| grep \'Updating host status\'
fi

sleep 67

load-image overcloud-control.qcow2
load-image overcloud-compute.qcow2

make -C $TOCI_WORKING_DIR/tripleo-heat-templates overcloud.yaml
heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/overcloud.yaml -P 'notcomputeImage=overcloud-control' overcloud

sleep 161

wait_for 40 20 heat list \| grep CREATE_COMPLETE

export OVERCLOUD_IP=$(nova list | grep ctlplane | grep notcompute | sed -e "s/.*=\([0-9.]*\).*/\1/")
sed -e "s/$UNDERCLOUD_IP/$OVERCLOUD_IP/g" undercloudrc > overcloudrc
source $TOCI_WORKING_DIR/overcloudrc
export no_proxy=$no_proxy,$OVERCLOUD_IP

# wait for a successful os-refresh-config
ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true
wait_for 60 10 ssh_noprompt heat-admin@$OVERCLOUD_IP ls /opt/stack/boot-stack/init-neutron.ok

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

# Lets add a cirros image to the overcloud
curl -L https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-i386-disk.img | glance image-create --name cirros --disk-format qcow2 --container-format bare --is-public 1
