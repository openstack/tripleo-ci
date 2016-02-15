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
