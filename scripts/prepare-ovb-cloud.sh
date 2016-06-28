#!/bin/bash
set -ex

export PATH=$PATH:scripts
source $1

# Script to deploy the base infrastructure required to create the ovb-common and ovb-testenv stacks
# Parts of this script could have been a heat stack but not all

# We can't use heat to create the flavors as they can't be given a name with the heat resource
nova flavor-show bmc || nova flavor-create bmc auto 512 20 1
nova flavor-show baremetal || nova flavor-create baremetal auto 5120 41 1
nova flavor-show undercloud || nova flavor-create undercloud auto 6144 40 2

# Remove the flavors that provide most disk space, the disks on rh2 are small we've over commited
# disk space, so this will help protect against an single instance filling the disk on a compute node
nova flavor-delete m1.large || true
nova flavor-delete m1.xlarge || true

glance image-show 'CentOS-7-x86_64-GenericCloud' || \
glance image-create --progress --name 'CentOS-7-x86_64-GenericCloud' --is-public true --disk-format qcow2 --container-format bare \
    --copy-from http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2

glance image-show 'ipxe-boot' || \
glance image-create --name ipxe-boot --is-public true --disk-format qcow2 --property os_shutdown_timeout=5 --container-format bare \
    --copy-from https://raw.githubusercontent.com/cybertron/openstack-virtual-baremetal/master/ipxe/ipxe-boot.qcow2

# Create a pool of floating IP's
neutron net-show public || neutron net-create public --router:external=True
neutron subnet-show public_subnet || neutron subnet-create --name public_subnet --enable_dhcp=False --allocation_pool start=$PUBLIC_IP_FLOATING_START,end=$PUBLIC_IP_FLOATING_END --gateway $PUBLIC_IP_GATWAY public $PUBLIC_IP_NET

# Create a shared private network
neutron net-show private || neutron net-create --shared private
neutron subnet-show private_subnet || neutron subnet-create --name private_subnet --gateway 192.168.100.1 --allocation-pool start=192.168.100.2,end=192.168.103.254 --dns-nameserver 8.8.8.8 private 192.168.100.0/22


# Give outside access to the private network
if ! neutron router-show private_router ; then
    neutron router-create private_router
    neutron router-gateway-set private_router public
    neutron router-interface-add private_router private_subnet
fi

# Keys to used in infrastructure
nova keypair-show tripleo-cd-admins || nova keypair-add --pub-key scripts/tripleo-cd-admins tripleo-cd-admins

# Create a new project/user whose creds will be injected into the te-broker for creating heat stacks
./scripts/assert-user -n openstack-nodepool -t openstack-nodepool -u openstack-nodepool -e openstack-nodepool@noreply.org || true
NODEPOOLUSERID=$(openstack user show openstack-nodepool | awk '$2=="id" {print $4}')
NODEPOOLPROJECTID=$(openstack project show openstack-nodepool | awk '$2=="id" {print $4}')
nova quota-update --instances 9999 --cores 9999 --ram $QUOTA_RAM --floating-ips $QUOTA_FIPS $NODEPOOLPROJECTID
nova quota-update --instances 9999 --cores 9999 --ram $QUOTA_RAM --floating-ips $QUOTA_FIPS --user $NODEPOOLUSERID $NODEPOOLPROJECTID
neutron quota-update --network $QUOTA_NETS --subnet $QUOTA_NETS --port $QUOTA_PORTS --floatingip $QUOTA_FIPS --tenant-id $NODEPOOLPROJECTID


touch ~/nodepoolrc
chmod 600 ~/nodepoolrc
echo -e "export OS_USERNAME=openstack-nodepool\nexport OS_TENANT_NAME=openstack-nodepool" > ~/nodepoolrc
echo "export OS_AUTH_URL=$OS_AUTH_URL" >> ~/nodepoolrc

set +x
PASSWORD=$(grep openstack-nodepool os-asserted-users | awk '{print $2}')
echo "export OS_PASSWORD=$PASSWORD" >> ~/nodepoolrc
set -x

source ~/nodepoolrc

nova keypair-show tripleo-cd-admins || nova keypair-add --pub-key scripts/tripleo-cd-admins tripleo-cd-admins
# And finally some servers we need
nova show te-broker || nova boot --flavor m1.medium --image "CentOS-7-x86_64-GenericCloud" --key-name tripleo-cd-admins --nic net-name=private,v4-fixed-ip=$TEBROKERIP --user-data scripts/deploy-server.sh --file "/etc/nodepoolrc=$HOME/nodepoolrc" te-broker
nova show mirror-server || nova boot --flavor m1.medium --image "CentOS-7-x86_64-GenericCloud" --key-name tripleo-cd-admins --nic net-name=private,v4-fixed-ip=$MIRRORIP --user-data scripts/deploy-server.sh mirror-server
nova show proxy-server || nova boot --flavor m1.medium --image "CentOS-7-x86_64-GenericCloud" --key-name tripleo-cd-admins --nic net-name=private,v4-fixed-ip=$PROXYIP --user-data scripts/deploy-server.sh proxy-server
if ! nova image-show bmc-template ; then
    nova keypair-add --pub-key ~/.ssh/id_rsa.pub undercloud
    nova boot --flavor bmc --image "CentOS-7-x86_64-GenericCloud" --key-name undercloud --user-data scripts/deploy-server.sh bmc-template 
    FLOATINGIP=$(nova floating-ip-create $EXTNET | grep public | awk '{print $4}')
    nova floating-ip-associate bmc-template $FLOATINGIP
    while ! ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o ConnectTimeout=2 centos@$FLOATINGIP ls /var/tmp/ready ; do
        sleep 10
    done
    nova image-create --poll bmc-template bmc-template
    nova delete bmc-template
    nova keypair-delete undercloud
fi
