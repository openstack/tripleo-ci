#!/bin/bash

sudo bash <<-EOF &> /var/log/host_info.txt
set -x
export PATH=\$PATH:/sbin
ps -eaufxZ
ls -Z /var/run/
df -h
uptime
sudo netstat -lpn
sudo iptables-save
sudo ovs-vsctl show
ip addr
ip route
ip -6 route
free -h
top -n 1 -b -o RES
rpm -qa
sudo os-collect-config --print
which pcs &> /dev/null && sudo pcs status --full
which pcs &> /dev/null && sudo pcs constraint show --full
which pcs &> /dev/null && sudo pcs stonith show --full
which crm_verify &> /dev/null && sudo crm_verify -L -VVVVVV
which ceph &> /dev/null && sudo ceph status
sudo facter
find ~jenkins -iname tripleo-overcloud-passwords -execdir cat '{}' ';'

EOF

if [ -e ~/stackrc ] ; then
    source ~/stackrc

    nova list | tee /tmp/nova-list.txt
    heat stack-show overcloud
    heat resource-list -n5 overcloud
    heat event-list overcloud
    # --nested-depth 2 seems to get us a reasonable list of resources without
    # taking an excessive amount of time
    openstack stack event list --nested-depth 2 -f json overcloud | $TRIPLEO_ROOT/tripleo-ci/scripts/heat-deploy-times.py | tee /var/log/heat-deploy-times.log || echo 'Failed to process resource deployment times. This is expected for stable/liberty.'
    # useful to see what failed when puppet fails
    for failed_deployment in $(heat resource-list --nested-depth 5 overcloud | grep FAILED | grep 'StructuredDeployment ' | cut -d '|' -f3); do heat deployment-show $failed_deployment; done;
fi
