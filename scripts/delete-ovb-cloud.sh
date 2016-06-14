#!/bin/bash
set -x


nova delete $(nova list --all-tenants | grep -e te-broker -e mirror-server -e proxy-server| awk '{print $2}')

sleep 5
keystone user-delete openstack-nodepool
keystone tenant-delete openstack-nodepool

neutron router-interface-delete private_router private_subnet
neutron router-delete private_router
neutron subnet-delete private_subnet
neutron net-delete private
neutron subnet-delete public_subnet
neutron net-delete public

