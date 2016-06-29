set -eux
set -o pipefail

cd

# This sets all the environment variables for undercloud and overcloud installation
source /opt/stack/new/tripleo-ci/deploy.env
source /opt/stack/new/tripleo-ci/scripts/metrics.bash

# Prevent python from buffering stdout, so timestamps are set at appropriate times
export PYTHONUNBUFFERED=true

export DIB_DISTRIBUTION_MIRROR=$CENTOS_MIRROR
export DIB_EPEL_MIRROR=$EPEL_MIRROR
export STABLE_RELEASE=${STABLE_RELEASE:-""}

echo '[DEFAULT]' > ~/undercloud.conf

if [ $UNDERCLOUD_SSL == 1 ] ; then
    echo 'generate_service_certificate = True' >> ~/undercloud.conf
fi

sudo yum install -y moreutils
echo "INFO: Check /var/log/undercloud_install.txt for undercloud install output"
echo "INFO: This file can be found in logs/undercloud.tar.xz in the directory containing console.log"
start_metric "tripleo.undercloud.install.seconds"
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --undercloud 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' | sudo dd of=/var/log/undercloud_install.txt || (tail -n 50 /var/log/undercloud_install.txt && false)
stop_metric "tripleo.undercloud.install.seconds"

if [ "$OVB" = 1 ]; then

    # eth1 is on the provisioning netwrok and doesn't have dhcp, so we need to set its MTU manually.
    sudo ip link set dev eth1 up
    sudo ip link set dev eth1 mtu 1400

    echo -e "\ndhcp-option-force=26,1400" | sudo tee -a /etc/dnsmasq-ironic.conf
    sudo systemctl restart 'neutron-*'

    # The undercloud install is creating file in ~/.cache as root
    # change them back so we can build overcloud images
    sudo chown -R $USER ~/.cache || true

    # check the power status of the last IPMI device we have details for
    # this ensures the BMC is ready and sanity tests that its working
    PMADDR=$(jq '.nodes[length-1].pm_addr' < ~/instackenv.json | tr '"' ' ')
    tripleo wait_for -d 10 -l 40 -- ipmitool -I lanplus -H $PMADDR -U admin -P password power status
fi

if [ $INTROSPECT == 1 ] ; then
    # I'm removing most of the nodes in the env to speed up discovery
    # This could be in jq but I don't know how
    # Only do this for jobs that use introspection, as it makes the likelihood
    # of hitting https://bugs.launchpad.net/tripleo/+bug/1341420 much higher
    python -c "import simplejson ; d = simplejson.loads(open(\"instackenv.json\").read()) ; del d[\"nodes\"][$NODECOUNT:] ; print simplejson.dumps(d)" > instackenv_reduced.json
    mv instackenv_reduced.json instackenv.json

    # Lower the timeout for introspection to decrease failure time
    # It should not take more than 10 minutes with IPA ramdisk and no extra collectors
    sudo sed -i '2itimeout = 600' /etc/ironic-inspector/inspector.conf
    sudo systemctl restart openstack-ironic-inspector
fi

if [ $NETISO_V4 -eq 1 ] || [ $NETISO_V6 -eq 1 ]; then

    # Update our floating range to use a 10. /24
    export FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-"10.0.0.0/24"}
    export FLOATING_IP_START=${FLOATING_IP_START:-"10.0.0.100"}
    export FLOATING_IP_END=${FLOATING_IP_END:-"10.0.0.200"}
    export EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"10.0.0.1"}

# Make our undercloud act as the external gateway
# eth6 should line up with the "external" network port per the
# tripleo-heat-template/network/config/multiple-nics templates.
# NOTE: seed uses eth0 for the local network.
    cat >> /tmp/eth6.cfg <<EOF_CAT
network_config:
    - type: interface
      name: eth6
      use_dhcp: false
      addresses:
        - ip_netmask: 10.0.0.1/24
EOF_CAT
    if [ $NETISO_V6 -eq 1 ]; then
        cat >> /tmp/eth6.cfg <<EOF_CAT
        - ip_netmask: 2001:db8:fd00:1000::1/64
EOF_CAT
    fi
    sudo os-net-config -c /tmp/eth6.cfg -v
fi

# Our ci underclouds don't have enough RAM to allow us to use a tmpfs
export DIB_NO_TMPFS=1
# Override the default repositories set by tripleo.sh, to add the delorean-ci repository
export OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=$(ls /etc/yum.repos.d/delorean*)
# Directing the output of this command to a file as its extreemly verbose
echo "INFO: Check /var/log/image_build.txt for image build output"
echo "INFO: This file can be found in logs/undercloud.tar.xz in the directory containing console.log"
start_metric "tripleo.overcloud.${TOCI_JOBTYPE}.images.seconds"
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --overcloud-images | ts '%Y-%m-%d %H:%M:%S.000 |' | sudo dd of=/var/log/image_build.txt || (tail -n 50 /var/log/image_build.txt && false)
stop_metric "tripleo.overcloud.${TOCI_JOBTYPE}.images.seconds"

OVERCLOUD_IMAGE_MB=$(du -ms overcloud-full.qcow2 | cut -f 1 | sed 's|.$||')
record_metric "tripleo.overcloud.${TOCI_JOBTYPE}.image.size_mb" "$OVERCLOUD_IMAGE_MB"

start_metric "tripleo.register.nodes.seconds"
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --register-nodes
stop_metric "tripleo.register.nodes.seconds"

if [ $INTROSPECT == 1 ] ; then
   start_metric "tripleo.introspect.seconds"
   $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --introspect-nodes
   stop_metric "tripleo.introspect.seconds"
fi

sleep 60

if [ -n "${OVERCLOUD_UPDATE_ARGS:-}" ] ; then
    # Reinstall openstack-tripleo-heat-templates from delorean-current.
    # Since we're testing updates, we want to remove any version we may have
    # installed from the delorean-ci repo and install from delorean-current,
    # or just delorean in the case of stable branches.
    sudo rpm -ev --nodeps openstack-tripleo-heat-templates
    sudo yum -y --disablerepo=* --enablerepo=delorean,delorean-current install openstack-tripleo-heat-templates
fi

export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config.yaml"
if [[ "${STABLE_RELEASE}" =~ ^(liberty|mitaka)$ ]] ; then
    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config-mitaka-and-below.yaml"
fi
start_metric "tripleo.overcloud.${TOCI_JOBTYPE}.deploy.seconds"
http_proxy= $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --overcloud-deploy ${TRIPLEO_SH_ARGS:-}
stop_metric "tripleo.overcloud.${TOCI_JOBTYPE}.deploy.seconds"

if [ -n "${OVERCLOUD_UPDATE_ARGS:-}" ] ; then
    # Reinstall openstack-tripleo-heat-templates, this will pick up the version
    # from the delorean-ci repo if the patch being tested is from
    # tripleo-heat-templates, otherwise it will just reinstall from
    # delorean-current.
    sudo rpm -ev --nodeps openstack-tripleo-heat-templates
    sudo yum -y install openstack-tripleo-heat-templates

    export OVERCLOUD_UPDATE_ARGS="$OVERCLOUD_UPDATE_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config.yaml"
    if [[ "${STABLE_RELEASE}" =~ ^(liberty|mitaka)$ ]] ; then
        OVERCLOUD_UPDATE_ARGS="$OVERCLOUD_UPDATE_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/worker-config-mitaka-and-below.yaml"
    fi
    http_proxy= $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --overcloud-update ${TRIPLEO_SH_ARGS:-}
fi

# Sanity test we deployed what we said we would
source ~/stackrc
[ "$NODECOUNT" != $(nova list | grep ACTIVE | wc -l | cut -f1 -d " ") ] && echo "Wrong number of nodes deployed" && exit 1

if [ $PACEMAKER == 1 ] ; then
    # Wait for the pacemaker cluster to settle and all resources to be
    # available. heat-{api,engine} are the best candidates since due to the
    # constraint ordering they are typically started last. We'll wait up to
    # 180s.
    start_metric "tripleo.overcloud.${TOCI_JOBTYPE}.settle.seconds"
    timeout -k 10 240 ssh $SSH_OPTIONS heat-admin@$(nova list | grep controller-0 | awk '{print $12}' | cut -d'=' -f2) sudo crm_resource -r openstack-heat-api --wait || {
        exitcode=$?
        echo "crm_resource for openstack-heat-api has failed!"
        exit $exitcode
        }
    timeout -k 10 240 ssh $SSH_OPTIONS heat-admin@$(nova list | grep controller-0 | awk '{print $12}' | cut -d'=' -f2) sudo crm_resource -r openstack-heat-engine --wait|| {
        exitcode=$?
        echo "crm_resource for openstack-heat-engine has failed!"
        exit $exitcode
        }
     stop_metric "tripleo.overcloud.${TOCI_JOBTYPE}.settle.seconds"
fi

source ~/overcloudrc
if [ $RUN_PING_TEST == 1 ] ; then
    start_metric "tripleo.overcloud.${TOCI_JOBTYPE}.ping_test.seconds"
    OVERCLOUD_PINGTEST_OLD_HEATCLIENT=0 $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --overcloud-pingtest
    stop_metric "tripleo.overcloud.${TOCI_JOBTYPE}.ping_test.seconds"
fi
if [ $RUN_TEMPEST_TESTS == 1 ] ; then
    start_metric "tripleo.overcloud.${TOCI_JOBTYPE}.tempest.seconds"
    export TEMPEST_REGEX='^(?=(.*smoke))(?!('
    export TEMPEST_REGEX="${TEMPEST_REGEX}tempest.api.orchestration.stacks"
    export TEMPEST_REGEX="${TEMPEST_REGEX}|tempest.scenario.test_volume_boot_pattern" # http://bugzilla.redhat.com/1272289
    export TEMPEST_REGEX="${TEMPEST_REGEX}|tempest.api.telemetry"
    export TEMPEST_REGEX="${TEMPEST_REGEX}|tempest.api.identity.*v3" # https://bugzilla.redhat.com/1266947
    export TEMPEST_REGEX="${TEMPEST_REGEX}|.*test_external_network_visibility" # https://bugs.launchpad.net/tripleo/+bug/1577769
    export TEMPEST_REGEX="${TEMPEST_REGEX}))"
    bash $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --run-tempest
    stop_metric "tripleo.overcloud.${TOCI_JOBTYPE}.tempest.seconds"
fi
