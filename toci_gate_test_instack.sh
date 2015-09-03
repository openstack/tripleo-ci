#!/usr/bin/env bash
set -eux

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

export http_proxy=http://192.168.1.100:3128/
export GEARDSERVER=192.168.1.1
export PYPIMIRROR=192.168.1.101

export NODECOUNT=2
export DEPLOYFLAGS=
# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        overcloud)
            ;;
        ceph)
            NODECOUNT=4
            DEPLOYFLAGS="--ceph-storage-scale 2 -e /usr/share/openstack-tripleo-heat-templates/environments/puppet-ceph-devel.yaml"
            ;;
    esac
done

# print the final values of control variables to console
env | grep -E "(TOCI_JOBTYPE)="

# Allow the instack node to have traffic forwards through here
sudo iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
# ./testenv-client kill everything in its own process group it it hits a timeout
# run it in a separate group to avoid getting killed along with it
set -m
./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_instack.sh
