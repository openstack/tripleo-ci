#!/usr/bin/env bash
set -eux

## Signal to toci_gate_test.sh we've started
touch /tmp/toci.started

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

export PATH=/sbin:/usr/sbin:$PATH

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash

stop_metric "tripleo.testenv.wait.seconds" # start_metric in toci_gate_test.sh
start_metric "tripleo.ci.total.seconds"

mkdir -p $WORKSPACE/logs

MY_IP=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}')

export no_proxy=192.0.2.1,$MY_IP,$MIRRORSERVER

# Setup delorean
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-setup

dummy_ci_repo

trap "[ \$? != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' > $WORKSPACE/logs/postci.log 2>&1" EXIT

delorean_build_and_serve

# Install all of the repositories we need
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup

layer_ci_repo

# Remove everything installed from a delorean repository (only requred if ci nodes are being reused)
TOBEREMOVED=$(yumdb search from_repo delorean delorean-current delorean-ci | grep -v -e from_repo -e "Loaded plugins" || true)
[ "$TOBEREMOVED" != "" ] &&  sudo yum remove -y $TOBEREMOVED
sudo yum clean all

# ===== End : Yum repository setup ====

cd $TRIPLEO_ROOT
sudo yum install -y diskimage-builder instack-undercloud os-apply-config qemu-kvm

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)
SSH_USER=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-user --type username)
HOST_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key host-ip --type netaddress)
ENV_NUM=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key env-num --type int)

mkdir -p ~/.ssh
echo "$PRIV_SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
# Generate the public key from the private one
ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
# Ensure there is a newline after the last key
echo >> ~/.ssh/authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# Kill any VM's in the test env that we may have started, freeing up RAM
# for other tests running on the TE host.
function destroy_vms(){
    ssh $SSH_OPTIONS $SSH_USER@$HOST_IP virsh destroy seed_${ENV_NUM} || true
    for i in $(seq 0 14) ; do
        ssh $SSH_OPTIONS $SSH_USER@$HOST_IP virsh destroy baremetal${ENV_NUM}brbm_one${ENV_NUM}_${i} || true
    done
    ssh $SSH_OPTIONS $SSH_USER@$HOST_IP purge_env ${ENV_NUM} || true
}

# TODO : Remove the need for this from instack-undercloud
ls /home/jenkins/.ssh/id_rsa_virt_power || ssh-keygen -f /home/jenkins/.ssh/id_rsa_virt_power -P ""

export ANSWERSFILE=/usr/share/instack-undercloud/undercloud.conf.sample
export ELEMENTS_PATH=/usr/share/instack-undercloud
export DIB_DISTRIBUTION_MIRROR=$CENTOS_MIRROR
export DIB_EPEL_MIRROR=$EPEL_MIRROR
export DIB_CLOUD_IMAGES=http://$MIRRORSERVER/cloud.centos.org/centos/7/images

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

# Build and deploy our undercloud instance
destroy_vms

# If this 404's it wont error just continue without a file created
if canusecache $UNDERCLOUD_VM_NAME.qcow2 ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/$UNDERCLOUD_VM_NAME.qcow2 || true
    [ -f $PWD/$UNDERCLOUD_VM_NAME.qcow2 ] && update_image $PWD/$UNDERCLOUD_VM_NAME.qcow2
fi

# We're adding some packages to the image build here so when using a cached image
# less has to be installed during the undercloud install
if [ ! -e $UNDERCLOUD_VM_NAME.qcow2 ] ; then
    echo "INFO: Check logs/instack-build.txt for instack image build output"
    DIB_YUM_REPO_CONF=$(ls /etc/yum.repos.d/delorean*) \
    # Pre install packages on the instack image for the master jobs, We don't currently
    # cache images for the stabole jobs so this isn't need and causes complications bug #1585937
    PREINSTALLPACKAGES=
    if [ -z "$STABLE_RELEASE" ] ; then
        PREINSTALLPACKAGES="-p automake,docker-registry,dstat,gcc-c++,ipxe-bootimgs,libxslt-devel,mariadb-devel,mariadb-server,memcached,mod_wsgi,openstack-aodh-api,openstack-aodh-evaluator,openstack-aodh-listener,openstack-aodh-notifier,openstack-ceilometer-api,openstack-ceilometer-central,openstack-ceilometer-collector,openstack-glance,openstack-heat-api,openstack-heat-api-cfn,openstack-heat-engine,openstack-ironic-api,openstack-ironic-conductor,openstack-ironic-inspector,openstack-keystone,openstack-neutron,openstack-neutron-ml2,openstack-neutron-openvswitch,openstack-nova-api,openstack-nova-cert,openstack-nova-compute,openstack-nova-conductor,openstack-nova-scheduler,openstack-selinux,openstack-swift-account,openstack-swift-object,openstack-swift-proxy,openstack-tempest,openwsman-python,os-apply-config,os-cloud-config,os-collect-config,os-net-config,os-refresh-config,puppet,python-pip,python-virtualenv,rabbitmq-server,tftp-server,xinetd,yum-plugin-priorities"
    fi
    # NOTE(pabelanger): Create both qcow2 and raw formats, but once we removed
    # Fedora 22 support, we can stop building qcow2 images.
    disk-image-create --image-size 30 -t qcow2,raw -a amd64 centos7 instack-vm -o $UNDERCLOUD_VM_NAME $PREINSTALLPACKAGES 2>&1 | sudo dd of=$WORKSPACE/logs/instack-build.txt || (tail -n 50 $WORKSPACE/logs/instack-build.txt && false)
fi
dd if=$UNDERCLOUD_VM_NAME.qcow2 | ssh $SSH_OPTIONS root@${HOST_IP} copyseed $ENV_NUM
ssh $SSH_OPTIONS root@${HOST_IP} virsh start seed_$ENV_NUM

# Set SEED_IP here to prevent postci ssh'ing to the undercloud before its up and running
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress --key-default '')
SANITIZED_SEED_ADDRESS=$(sanitize_ip_address ${SEED_IP})

# The very first thing we should do is put a valid dns server in /etc/resolv.conf, without it
# all ssh connections hit a 20 second delay until a reverse dns lookup hits a timeout
echo -e "nameserver 10.1.8.10\nnameserver 8.8.8.8" > /tmp/resolv.conf
tripleo wait_for -d 5 -l 20 -- scp $SSH_OPTIONS /tmp/resolv.conf root@${SANITIZED_SEED_ADDRESS}:/etc/resolv.conf

echo_vars_to_deploy_env
cp $TRIPLEO_ROOT/tripleo-ci/deploy.env $WORKSPACE/logs/deploy.env.log

# Copy the required CI resources to the undercloud were we use them
tar -czf - $TRIPLEO_ROOT/tripleo-ci /etc/yum.repos.d/delorean* | ssh $SSH_OPTIONS root@$SEED_IP tar -C / -xzf -

# Don't get a file from cache if CACHEUPLOAD=1 (periodic job)
# If this 404's it wont error just continue without a file created
if canusecache ipa_images.tar ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/ipa_images.tar || true
    if [ -f ipa_images.tar ] ; then
        tar -xf ipa_images.tar
        update_image $PWD/ironic-python-agent.initramfs
        scp $SSH_OPTIONS ironic-python-agent.* root@${SANITIZED_SEED_ADDRESS}:/home/stack
        rm ipa_images.tar ironic-python-agent.*
    fi
fi

# Same thing for the overcloud image
if canusecache overcloud-full.tar ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/overcloud-full.tar || true
    if [ -f overcloud-full.tar ] ; then
        tar -xf overcloud-full.tar
        update_image $PWD/overcloud-full.qcow2
        scp $SSH_OPTIONS overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz root@${SANITIZED_SEED_ADDRESS}:/home/stack
        rm overcloud-full.*
    fi
fi

ssh $SSH_OPTIONS root@${SEED_IP} <<-EOF

set -eux

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

ip route add 0.0.0.0/0 dev eth0 via $MY_IP

# installing basic utils
yum install -y python-simplejson dstat yum-plugin-priorities

# Add a simple system utilisation logger process
dstat -tcmndrylpg --output /var/log/dstat-csv.log >/dev/null &
disown

# https://bugs.launchpad.net/tripleo/+bug/1536136
# Add some swap to the undercloud, this is only a temp solution
# to see if it improves CI fail rates, we need to come to a concensus
# on how much RAM is acceptable as a minimum and stick to it
dd if=/dev/zero of=/swapfile count=2k bs=1M
mkswap /swapfile
swapon /swapfile

# Install our test cert so SSL tests work
cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

# Run the deployment as the stack user
su -l -c "bash $TRIPLEO_ROOT/tripleo-ci/scripts/deploy.sh" stack
EOF

# If we got this far and its a periodic job, declare success and upload build artifacts
if [ $CACHEUPLOAD == 1 ] ; then
    # Get the IPA and overcloud images for caching
    ssh root@$SEED_IP tar -C /home/stack -cf - ironic-python-agent.initramfs ironic-python-agent.vmlinuz ironic-python-agent.kernel > ipa_images.tar
    ssh root@$SEED_IP tar -C /home/stack -cf - overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz > overcloud-full.tar

    md5sum overcloud-full.tar > overcloud-full.tar.md5
    md5sum ipa_images.tar > ipa_images.tar.md5
    md5sum $TRIPLEO_ROOT/$UNDERCLOUD_VM_NAME.qcow2 > $UNDERCLOUD_VM_NAME.qcow2.md5

    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@ipa_images.tar;filename=ipa_images.tar"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@overcloud-full.tar;filename=overcloud-full.tar"
    # TODO(pabelanger): Remove qcow2 format, since centos-7 cannot mount nbd with the default kernel.
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@$TRIPLEO_ROOT/$UNDERCLOUD_VM_NAME.qcow2;filename=$UNDERCLOUD_VM_NAME.qcow2"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@$TRIPLEO_ROOT/$UNDERCLOUD_VM_NAME.raw;filename=$UNDERCLOUD_VM_NAME.raw"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@ipa_images.tar.md5;filename=ipa_images.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@overcloud-full.tar.md5;filename=overcloud-full.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@$UNDERCLOUD_VM_NAME.qcow2.md5;filename=$UNDERCLOUD_VM_NAME.qcow2.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "$JOB_NAME=SUCCESS"
fi

exit 0
echo 'Run completed.'
