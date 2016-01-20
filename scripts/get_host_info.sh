#!/bin/bash

sudo bash <<-EOF &> /var/log/host_info.txt
set -x
export PATH=\$PATH:/sbin
ps -efZ
ls -Z /var/run/
df -h
uptime
sudo netstat -lpn
sudo iptables-save
sudo ovs-vsctl show
ip addr
free -h
top -n 1 -o RES
rpm -qa
sudo os-collect-config --print
which pcs &> /dev/null && sudo pcs status --full
which pcs &> /dev/null && sudo pcs constraint show --full
which pcs &> /dev/null && sudo pcs stonith show --full
which crm_verify &> /dev/null && sudo crm_verify -L -VVVVVV

EOF

if [ -e ~/stackrc ] ; then
    source ~/stackrc

    nova list | tee /tmp/nova-list.txt
    heat stack-show overcloud
    heat resource-list overcloud
    heat event-list overcloud
    # useful to see what failed when puppet fails
    for failed_deployment in $(heat resource-list --nested-depth 5 overcloud | grep FAILED | grep 'StructuredDeployment ' | cut -d '|' -f3); do heat deployment-show $failed_deployment; done;
fi
