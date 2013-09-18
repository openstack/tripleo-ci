#!/usr/bin/env bash

set -xe
. toci_functions.sh

cd $TOCI_WORKING_DIR
SEED_IP=`$TOCI_WORKING_DIR/tripleo-incubator/scripts/get-vm-ip seed`

# Get logs from the node on exit
trap "get_state_from_host root $SEED_IP" EXIT

# Add a route to the baremetal bridge via the seed node
sudo ip route del 192.0.2.0/24 dev virbr0 || true
sudo ip route add 192.0.2.0/24 dev virbr0 via $SEED_IP

scp_noprompt root@$SEED_IP:stackrc $TOCI_WORKING_DIR/seedrc
sed -i "s/localhost/$SEED_IP/" $TOCI_WORKING_DIR/seedrc
source $TOCI_WORKING_DIR/seedrc

export no_proxy=$no_proxy,$SEED_IP

# wait for a successful os-refresh-config
wait_for 60 10 ssh_noprompt root@$SEED_IP journalctl -u os-collect-config \| grep \'Completed phase post-configure\'

# init keystone / setup endpoints
init-keystone -p unset unset 192.0.2.1 admin@example.com root@192.0.2.1
setup-endpoints 192.0.2.1 --glance-password unset --heat-password unset --neutron-password unset --nova-password unset

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list
user-config #Adds nova keypair

if [ -n "$TOCI_MACS" ]; then
  # call setup-baremetal with no macs so baremetal flavor is created
  MACS= setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH seed
  MACS=( $TOCI_MACS )
  IPS=( $TOCI_PM_IPS )
  USERS=( $TOCI_PM_USERS )
  PASSWORDS=( $TOCI_PM_PASSWORDS )
  COUNT=0
  for MAC in "${MACS[@]}"; do
    nova baremetal-node-create --pm_address=${IPS[$COUNT]} --pm_user=${USERS[$COUNT]} --pm_password=${PASSWORDS[$COUNT]} ubuntu $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $MAC
    COUNT=$(( $COUNT + 1 ))
  done
else
  create-nodes $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH 5
  export MACS=$($TOCI_WORKING_DIR/bm_poseur/bm_poseur get-macs)
  setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH seed
fi

setup-neutron 192.0.2.2 192.0.2.3 192.0.2.0/24 192.0.2.1 ctlplane

# Load images into glance
export DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder
$TOCI_WORKING_DIR/tripleo-incubator/scripts/load-image undercloud.qcow2

keystone role-create --name heat_stack_user

# place the bootstrap public key on host so that it can admin virt
ssh_noprompt root@$SEED_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

# Now we have to wait for the bm poseur to appear on the compute node and for the compute node to then
# update the scheduler
if [ -d /var/log/upstart ]; then
    wait_for 40 10 ssh_noprompt root@$SEED_IP grep 'Free VCPUS: [^0]' /var/log/upstart/nova-compute.log
else
    wait_for 40 10 ssh_noprompt root@$SEED_IP journalctl -u nova-compute -u openstack-nova-compute \| grep \'Free VCPUS: [^0]\'
fi

if [ "$TOCI_ARCH" != "i386" ]; then
  sed -i "s/arch: i386/arch: $TOCI_DIB_ARCH/" $TOCI_WORKING_DIR/tripleo-heat-templates/undercloud-vm.yaml
fi
heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/undercloud.yaml -P "PowerUserName=$(whoami);AdminToken=${TOCI_ADMIN_TOKEN};AdminPassword=${TOCI_UNDERCLOUD_PASSWORD};CinderPassword=${TOCI_UNDERCLOUD_PASSWORD};GlancePassword=${TOCI_UNDERCLOUD_PASSWORD};HeatPassword=${TOCI_UNDERCLOUD_PASSWORD};NeutronPassword=${TOCI_UNDERCLOUD_PASSWORD};NovaPassword=${TOCI_UNDERCLOUD_PASSWORD}" undercloud


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

# Make the tripleo image elements accessible to diskimage-builder
export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements

if [ "$TOCI_DO_OVERCLOUD" = "1" ] ; then
    $TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -a $TOCI_DIB_ARCH -o overcloud-control boot-stack os-collect-config neutron-network-node stackuser local-config
fi

# Also get undercloud logs
trap "get_state_from_host root $SEED_IP ; get_state_from_host heat-admin $UNDERCLOUD_IP" EXIT

# wait for a successful os-refresh-config
wait_for 60 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo journalctl -u os-collect-config \| grep \'Completed phase post-configure\'

# setup keystone endpoints
init-keystone -p unset unset $UNDERCLOUD_IP admin@example.com root@$UNDERCLOUD_IP
setup-endpoints $UNDERCLOUD_IP --glance-password unset --heat-password unset --neutron-password unset --nova-password unset

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

if [ "$TOCI_DO_OVERCLOUD" != "1" ] ; then
    exit 0
fi

user-config
setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH undercloud
setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 $UNDERCLOUD_IP ctlplane
ssh_noprompt heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

$TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -a $TOCI_DIB_ARCH -o overcloud-compute nova-compute nova-kvm neutron-openvswitch-agent os-collect-config stackuser local-config

if [ -d /var/log/upstart ]; then
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP grep 'Free VCPUS: [^0]' /var/log/upstart/nova-compute.log
else
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo journalctl -u nova-compute -u openstack-nova-compute \| grep \'Free VCPUS: [^0]\'
fi

load-image overcloud-control.qcow2
load-image overcloud-compute.qcow2

make -C $TOCI_WORKING_DIR/tripleo-heat-templates overcloud.yaml
heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml -P "AdminToken=${TOCI_ADMIN_TOKEN};AdminPassword=${TOCI_OVERCLOUD_PASSWORD};CinderPassword=${TOCI_OVERCLOUD_PASSWORD};GlancePassword=${TOCI_OVERCLOUD_PASSWORD};HeatPassword=${TOCI_OVERCLOUD_PASSWORD};NeutronPassword=${TOCI_OVERCLOUD_PASSWORD};NovaPassword=${TOCI_OVERCLOUD_PASSWORD};notcomputeImage=overcloud-control" overcloud

sleep 161

wait_for 50 20 heat list \| grep CREATE_COMPLETE

export OVERCLOUD_IP=$(nova list | grep ctlplane | grep notcompute | sed -e "s/.*=\([0-9.]*\).*/\1/")
sed -e "s/$UNDERCLOUD_IP/$OVERCLOUD_IP/g" undercloudrc > overcloudrc
source $TOCI_WORKING_DIR/overcloudrc
export no_proxy=$no_proxy,$OVERCLOUD_IP

# Also get overcloud logs
trap "get_state_from_host root $SEED_IP ; get_state_from_host heat-admin $UNDERCLOUD_IP ; get_state_from_host heat-admin $OVERCLOUD_IP" EXIT

# wait for a successful os-refresh-config
ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true
wait_for 60 10 ssh_noprompt heat-admin@$OVERCLOUD_IP sudo journalctl -u os-collect-config \| grep \'Completed phase post-configure\'

# setup keystone endpoints
init-keystone -p unset unset $OVERCLOUD_IP admin@example.com root@$OVERCLOUD_IP
setup-endpoints $OVERCLOUD_IP --glance-password unset --heat-password unset --neutron-password unset --nova-password unset

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

# Lets add a cirros image to the overcloud
curl -L https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-i386-disk.img | glance image-create --name cirros --disk-format qcow2 --container-format bare --is-public 1
