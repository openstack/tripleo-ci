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

cp $TOCI_WORKING_DIR/tripleo-incubator/seedrc $TOCI_WORKING_DIR/seedrc
sed -i "s/\$SEED_IP/$SEED_IP/" $TOCI_WORKING_DIR/seedrc
source $TOCI_WORKING_DIR/seedrc

export no_proxy=$no_proxy,$SEED_IP

# wait for a successful os-refresh-config
if [[ "$NODE_DIST" =~ (.*)ubuntu(.*) ]]; then
    wait_for 60 10 ssh_noprompt root@$SEED_IP grep 'Completed phase post-configure' /var/log/upstart/os-collect-config.log
else
    wait_for 60 10 ssh_noprompt root@$SEED_IP journalctl -u os-collect-config \| grep \'Completed phase post-configure\'
fi

# init keystone / setup endpoints
init-keystone -p unset unset 192.0.2.1 admin@example.com root@192.0.2.1
setup-endpoints 192.0.2.1 --glance-password unset --heat-password unset --neutron-password unset --nova-password unset

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list
user-config #Adds nova keypair

if [ -n "$TOCI_MACS" ]; then

  # For the seed VM we use only the first MAC and power management setting
  setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH "${TOCI_MACS%% *}" seed "${TOCI_PM_IPS%% *}" "${TOCI_PM_USERS%% *}" "${TOCI_PM_PASSWORDS%% *}"

else

  export SEED_MACS=$(create-nodes $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH 1)
  setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH "$SEED_MACS" seed

  # If MAC's weren't provided then we're using virtual nodes
  OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-";NovaComputeLibvirtType=qemu"}

fi

setup-neutron 192.0.2.2 192.0.2.3 192.0.2.0/24 192.0.2.1 192.0.2.1 ctlplane

# Load images into glance
export DIB_PATH=$TOCI_WORKING_DIR/diskimage-builder
$TOCI_WORKING_DIR/tripleo-incubator/scripts/load-image undercloud.qcow2

keystone role-create --name heat_stack_user

# place the bootstrap public key on host so that it can admin virt
ssh_noprompt root@$SEED_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

# Now we have to wait for the bm poseur to appear on the compute node and for the compute node to then
# update the scheduler
if [[ "$NODE_DIST" =~ (.*)ubuntu(.*) ]]; then
    wait_for 40 10 ssh_noprompt root@$SEED_IP grep 'Free VCPUS: [^0]' /var/log/upstart/nova-compute.log
else
    wait_for 40 10 ssh_noprompt root@$SEED_IP journalctl -u nova-compute -u openstack-nova-compute \| grep \'Free VCPUS: [^0]\'
fi

if [ -n "$TOCI_PM_DRIVER" ]; then
  UNDERCLOUD_POWER_MANAGER=${UNDERCLOUD_POWER_MANAGER:-";PowerManager=${TOCI_PM_DRIVER}"}
fi

heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/undercloud-vm.yaml -P "PowerUserName=$(whoami);AdminToken=${TOCI_ADMIN_TOKEN};AdminPassword=${UNDERCLOUD_ADMIN_PASSWORD};GlancePassword=${UNDERCLOUD_ADMIN_PASSWORD};HeatPassword=${UNDERCLOUD_ADMIN_PASSWORD};NeutronPassword=${UNDERCLOUD_ADMIN_PASSWORD};NovaPassword=${UNDERCLOUD_ADMIN_PASSWORD};BaremetalArch=${TOCI_DIB_ARCH}${UNDERCLOUD_POWER_MANAGER}" undercloud

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
sed -i -e "s/\$UNDERCLOUD_IP/$UNDERCLOUD_IP/g" $TOCI_WORKING_DIR/undercloudrc
source $TOCI_WORKING_DIR/undercloudrc
export no_proxy=$no_proxy,$UNDERCLOUD_IP

# Make the tripleo image elements accessible to diskimage-builder
export ELEMENTS_PATH=$TOCI_WORKING_DIR/diskimage-builder/elements:$TOCI_WORKING_DIR/tripleo-image-elements/elements

if [ "$TOCI_DO_OVERCLOUD" = "1" ] ; then
    if [ "$TOCI_OVERCLOUD_ALL_IN_ONE" = "1" ] ; then
        $TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create $NODE_DIST $TOCI_OVERCLOUD_EXTRA_ELEMENTS -a $TOCI_DIB_ARCH -o overcloud-all-in-one boot-stack nova-compute nova-kvm neutron-openvswitch-agent os-collect-config stackuser local-config neutron-network-node notcompute
    else
        $TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create $NODE_DIST $TOCI_OVERCLOUD_EXTRA_ELEMENTS -a $TOCI_DIB_ARCH -o overcloud-control boot-stack os-collect-config neutron-network-node stackuser local-config notcompute
    fi
fi

# Also get undercloud logs
trap "get_state_from_host root $SEED_IP ; get_state_from_host heat-admin $UNDERCLOUD_IP" EXIT

# wait for a successful os-refresh-config
if [[ "$NODE_DIST" =~ (.*)ubuntu(.*) ]]; then
    wait_for 60 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP grep 'Completed phase post-configure' /var/log/upstart/os-collect-config.log
else
    wait_for 60 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo journalctl -u os-collect-config \| grep \'Completed phase post-configure\'
fi

# setup keystone endpoints
init-keystone -p $UNDERCLOUD_ADMIN_PASSWORD $TOCI_ADMIN_TOKEN $UNDERCLOUD_IP admin@example.com heat-admin@$UNDERCLOUD_IP
setup-endpoints $UNDERCLOUD_IP --glance-password $UNDERCLOUD_ADMIN_PASSWORD --heat-password $UNDERCLOUD_ADMIN_PASSWORD --neutron-password $UNDERCLOUD_ADMIN_PASSWORD --nova-password $UNDERCLOUD_ADMIN_PASSWORD

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

if [ "$TOCI_DO_OVERCLOUD" != "1" ] ; then
    exit 0
fi

user-config

if [ -n "$TOCI_MACS" ]; then

  # For the undercloud we pop off the first MAC and power management settings
  # since they have already been used by the seed VM
  setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH "${TOCI_MACS#[^ ]* }" undercloud "${TOCI_PM_IPS#[^ ]* }" "${TOCI_PM_USERS#[^ ]* }" "${TOCI_PM_PASSWORDS#[^ ]* }"

else

  export UNDERCLOUD_MACS=$(create-nodes $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH 2)
  setup-baremetal $TOCI_NODE_CPU $TOCI_NODE_MEM $TOCI_NODE_DISK $TOCI_DIB_ARCH "$UNDERCLOUD_MACS" undercloud

fi

setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 192.0.2.1 $UNDERCLOUD_IP ctlplane
ssh_noprompt heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

if [ "$TOCI_OVERCLOUD_ALL_IN_ONE" = "0" ] ; then
    $TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create $NODE_DIST $TOCI_OVERCLOUD_EXTRA_ELEMENTS -a $TOCI_DIB_ARCH -o overcloud-compute nova-compute nova-kvm neutron-openvswitch-agent os-collect-config stackuser local-config
fi

if [ -d /var/log/upstart ]; then
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP grep 'Free VCPUS: [^0]' /var/log/upstart/nova-compute.log
else
    wait_for 40 10 ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo journalctl -u nova-compute -u openstack-nova-compute \| grep \'Free VCPUS: [^0]\'
fi

if [ "$TOCI_OVERCLOUD_ALL_IN_ONE" = "1" ] ; then
    load-image overcloud-all-in-one.qcow2
else
    load-image overcloud-control.qcow2
    load-image overcloud-compute.qcow2
fi


if [ "$TOCI_OVERCLOUD_ALL_IN_ONE" = "1" ] ; then
    heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/overcloud-all-in-one.yaml -P "AdminToken=${TOCI_ADMIN_TOKEN};AdminPassword=${OVERCLOUD_ADMIN_PASSWORD};CinderPassword=${OVERCLOUD_ADMIN_PASSWORD};GlancePassword=${OVERCLOUD_ADMIN_PASSWORD};HeatPassword=${OVERCLOUD_ADMIN_PASSWORD};NeutronPassword=${OVERCLOUD_ADMIN_PASSWORD};NovaPassword=${OVERCLOUD_ADMIN_PASSWORD};Image=overcloud-all-in-one${OVERCLOUD_LIBVIRT_TYPE}" overcloud
else
    make -C $TOCI_WORKING_DIR/tripleo-heat-templates overcloud.yaml
    heat stack-create -f $TOCI_WORKING_DIR/tripleo-heat-templates/overcloud.yaml -P "AdminToken=${TOCI_ADMIN_TOKEN};AdminPassword=${OVERCLOUD_ADMIN_PASSWORD};CinderPassword=${OVERCLOUD_ADMIN_PASSWORD};GlancePassword=${OVERCLOUD_ADMIN_PASSWORD};HeatPassword=${OVERCLOUD_ADMIN_PASSWORD};NeutronPassword=${OVERCLOUD_ADMIN_PASSWORD};NovaPassword=${OVERCLOUD_ADMIN_PASSWORD};notcomputeImage=overcloud-control${OVERCLOUD_LIBVIRT_TYPE}" overcloud
fi

sleep 161

wait_for 50 20 heat list \| grep CREATE_COMPLETE

export OVERCLOUD_IP=$(nova list | grep ctlplane | grep notcompute | sed -e "s/.*=\([0-9.]*\).*/\1/")
cp $TOCI_WORKING_DIR/tripleo-incubator/overcloudrc $TOCI_WORKING_DIR/overcloudrc
sed -i -e "s/\$OVERCLOUD_IP/$OVERCLOUD_IP/g" $TOCI_WORKING_DIR/overcloudrc
source $TOCI_WORKING_DIR/overcloudrc
export no_proxy=$no_proxy,$OVERCLOUD_IP

# Also get overcloud logs
trap "get_state_from_host root $SEED_IP ; get_state_from_host heat-admin $UNDERCLOUD_IP ; get_state_from_host heat-admin $OVERCLOUD_IP" EXIT

# wait for a successful os-refresh-config
ssh_noprompt heat-admin@$UNDERCLOUD_IP sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true

if [[ "$NODE_DIST" =~ (.*)ubuntu(.*) ]]; then
    wait_for 60 10 ssh_noprompt heat-admin@$OVERCLOUD_IP grep 'Completed phase post-configure' /var/log/upstart/os-collect-config.log
else
    wait_for 60 10 ssh_noprompt heat-admin@$OVERCLOUD_IP sudo journalctl -u os-collect-config \| grep \'Completed phase post-configure\'
fi


# setup keystone endpoints
init-keystone -p $OVERCLOUD_ADMIN_PASSWORD $TOCI_ADMIN_TOKEN $OVERCLOUD_IP admin@example.com heat-admin@$OVERCLOUD_IP
setup-endpoints $OVERCLOUD_IP --glance-password $OVERCLOUD_ADMIN_PASSWORD --heat-password $OVERCLOUD_ADMIN_PASSWORD --neutron-password $OVERCLOUD_ADMIN_PASSWORD --nova-password $OVERCLOUD_ADMIN_PASSWORD
keystone role-create --name heat_stack_user
user-config
setup-neutron "" "" 10.0.0.0/8 "" "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24

# Make sure nova has had a chance to start responding to requests
wait_for 10 5 nova list

# Lets add a cirros image to the overcloud
curl -L https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-i386-disk.img | glance image-create --name cirros --disk-format qcow2 --container-format bare --is-public 1

# create demo user
os-adduser -p $OVERCLOUD_DEMO_PASSWORD demo demo@example.com
source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc-user
user-config

# Start and test a image on the overcloud
nova boot --key-name default --flavor m1.tiny --image cirros --key_name default demo
sleep 20 # give the port a chance to appear
PORT=$(neutron port-list -f csv -c id --quote none | tail -n1)
neutron security-group-rule-create default --protocol tcp --direction ingress --port-range-min 22 --port-range-max 22
neutron security-group-rule-create default --protocol icmp --direction ingress
IP=$(neutron floatingip-create ext-net --port-id "${PORT//[[:space:]]/}" | grep -o -P "192[0-9.]*")

wait_for 10 5 ping -c 1 $IP
