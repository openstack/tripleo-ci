set -eux

# This sets all the environment variables for undercloud and overcloud installation
source /tmp/deploy.env

# I'm removing most of the nodes in the env to speed up discovery
# This could be in jq but I don't know how
python -c "import simplejson ; d = simplejson.loads(open(\"instackenv.json\").read()) ; del d[\"nodes\"][$NODECOUNT:] ; print simplejson.dumps(d)" > instackenv_reduced.json
mv instackenv_reduced.json instackenv.json

export DIB_DISTRIBUTION_MIRROR=$CENTOS_MIRROR
export DIB_EPEL_MIRROR=$EPEL_MIRROR

echo "INFO: Check /var/log/undercloud_install.txt for undercloud install output"
/tmp/tripleo-common/scripts/tripleo.sh --undercloud 2>&1 | sudo dd of=/var/log/undercloud_install.txt
if [ $INTROSPECT == 1 ] ; then
    # Lower the timeout for introspection to decrease failure time
    # It should not take more than 10 minutes with IPA ramdisk and no extra collectors
    sudo sed -i '2itimeout = 600' /etc/ironic-inspector/inspector.conf
    sudo systemctl restart openstack-ironic-inspector
fi

if [ $NETISO_V4 -eq 1 ]; then

    # Update our floating range to use a 10. /24
    export FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-"10.0.0.0/24"}
    export FLOATING_IP_START=${FLOATING_IP_START:-"10.0.0.100"}
    export FLOATING_IP_END=${FLOATING_IP_END:-"10.0.0.200"}
    export EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"10.0.0.1"}

    # Update our private tenant network to use a 10.0.1 /24 private range
    export TENANT_STACK_DEPLOY_ARGS=${TENANT_STACK_DEPLOY_ARGS:-"-P private_net_cidr=10.0.1.0/24 -P private_net_gateway=10.0.1.1 -P private_net_pool_start=10.0.1.10 -P private_net_pool_end=10.0.1.20"}

# Make our undercloud act as the external gateway
# eth6 should line up with the "external" network port per the
# tripleo-heat-template/network/config/multiple-nics templates.
# NOTE: seed uses eth0 for the local network.
cat >> /tmp/eth6.cfg <<EOF_CAT
network_config:
  -
    type: interface
    name: eth6
    use_dhcp: false
    addresses:
    -
      ip_netmask: 10.0.0.1/24
EOF_CAT
sudo os-net-config -c /tmp/eth6.cfg -v
fi

# Our ci underclouds don't have enough RAM to allow us to use a tmpfs
export DIB_NO_TMPFS=1
# Directing the output of this command to a file as its extreemly verbose
echo "INFO: Check /var/log/image_build.txt for image build output"
/tmp/tripleo-common/scripts/tripleo.sh --overcloud-images | sudo dd of=/var/log/image_build.txt

/tmp/tripleo-common/scripts/tripleo.sh --register-nodes

if [ $INTROSPECT == 1 ] ; then
   /tmp/tripleo-common/scripts/tripleo.sh --introspect-nodes
fi

sleep 60

unset http_proxy

# Recreate the baremetal flavor to add a swap partition
source stackrc
nova flavor-delete baremetal
nova flavor-create --swap 1024 baremetal auto 4096 39 1
nova flavor-key baremetal set capabilities:boot_option=local

export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e /tmp/worker-config.yaml"
/tmp/tripleo-common/scripts/tripleo.sh --overcloud-deploy ${TRIPLEO_SH_ARGS:-}

# Sanity test we deployed what we said we would
source ~/stackrc
[ "$NODECOUNT" != $(nova list | grep ACTIVE | wc -l | cut -f1 -d " ") ] && echo "Wrong number of nodes deployed" && exit 1

if [ $PACEMAKER == 1 ] ; then
    # Wait for the pacemaker cluster to settle and all resources to be
    # available. heat-{api,engine} are the best candidates since due to the
    # constraint ordering they are typically started last. We'll wait up to
    # 180s.
    tripleo wait_for -w 180 --delay 1 -- ssh $SSH_OPTIONS heat-admin@$(nova list | grep controller-0 | awk '{print $12}' | cut -d'=' -f2) sudo crm_resource -r openstack-heat-api --wait
    tripleo wait_for -w 180 --delay 1 -- ssh $SSH_OPTIONS heat-admin@$(nova list | grep controller-0 | awk '{print $12}' | cut -d'=' -f2) sudo crm_resource -r openstack-heat-engine --wait
fi

source ~/overcloudrc
OVERCLOUD_PINGTEST_OLD_HEATCLIENT=0 /tmp/tripleo-common/scripts/tripleo.sh --overcloud-pingtest
