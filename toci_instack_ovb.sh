#!/usr/bin/env bash
set -eux

## Signal to toci_gate_test.sh we've started
touch /tmp/toci.started

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

export IP_DEVICE=${IP_DEVICE:-"eth0"}
export ZUUL_PROJECT=${ZUUL_PROJECT:-""}

source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash
stop_metric "tripleo.testenv.wait.seconds" # start_metric in toci_gate_test.sh
start_metric "tripleo.ci.total.seconds"

mkdir -p $WORKSPACE/logs

MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')

# TODO: Set undercloud_hostname in undercloud.conf
hostname | sudo dd of=/etc/hostname
echo "127.0.0.1 $(hostname) $(hostname).openstacklocal" | sudo tee -a /etc/hosts

# TODO: xfsprogs should be a dep of DIB?
sudo yum install -y xfsprogs

# Will be used by the undercloud and needed for the TLS everywhere job
sudo yum install -yq jq

# Remove the anything on the infra image template that might interfere with CI
sudo yum remove -y puppet hiera puppetlabs-release rdo-release
sudo rm -rf /etc/puppet /etc/hiera.yaml

undercloud_net_range="192.168.24."
undercloud_services_ip=$undercloud_net_range"1"
undercloud_haproxy_public_ip=$undercloud_net_range"2"
undercloud_haproxy_admin_ip=$undercloud_net_range"3"
export no_proxy=$undercloud_services_ip,$undercloud_haproxy_public_ip,$undercloud_haproxy_admin_ip,$MY_IP,$MIRRORSERVER

# Setup delorean
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-setup

dummy_ci_repo

# Install all of the repositories we need
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup

# Install some useful/necessary packages
sudo yum -y install wget python-simplejson yum-plugin-priorities qemu-img

trap "exit_val=\$?; [ \$exit_val != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci \$exit_val 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' > $WORKSPACE/logs/postci.log 2>&1" EXIT

# Tempreverts/cherry-picks/pins go here.  For example:
# temprevert tripleo-common af27127508eabf2b6873713e5e1507fa92b5f5b3 1623606

delorean_build_and_serve

# Since we've moved a few commands from this spot before the wget, we need to
# sleep a few seconds in order for the SimpleHTTPServer to get setup.
sleep 3

layer_ci_repo

echo_vars_to_deploy_env

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

# Install our test cert so SSL tests work
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert-ipv6.pem /etc/pki/ca-trust/source/anchors/

sudo update-ca-trust extract

# Don't get a file from cache if CACHEUPLOAD=1 (periodic job)
# If this 404's it wont error just continue without a file created
if canusecache ipa_images.tar ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/ipa_images.tar || true
    if [ -f ipa_images.tar ] ; then
        tar -xf ipa_images.tar
        update_image $PWD/ironic-python-agent.initramfs
        mv ironic-python-agent.* ~
        rm ipa_images.tar
    fi
fi

# Same thing for the overcloud image
if canusecache overcloud-full.tar ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/overcloud-full.tar || true
    if [ -f overcloud-full.tar ] ; then
        tar -xf overcloud-full.tar
        update_image $PWD/overcloud-full.qcow2
        mv overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz ~
        rm overcloud-full.tar
    fi
fi

cp -f $TE_DATAFILE ~/instackenv.json

$TRIPLEO_ROOT/tripleo-ci/scripts/deploy.sh
# If we got this far and its a periodic job, declare success and upload build artifacts
if [ $CACHEUPLOAD == 1 ] ; then
    # Get the IPA and overcloud images for caching
    tar -C ~ -cf - ironic-python-agent.initramfs ironic-python-agent.vmlinuz ironic-python-agent.kernel > ipa_images.tar
    tar -C ~ -cf - overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz > overcloud-full.tar

    md5sum overcloud-full.tar > overcloud-full.tar.md5
    md5sum ipa_images.tar > ipa_images.tar.md5

    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@ipa_images.tar;filename=ipa_images.tar"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@overcloud-full.tar;filename=overcloud-full.tar"
    # TODO(pabelanger): Remove qcow2 format, since centos-7 cannot mount nbd with the default kernel.
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@ipa_images.tar.md5;filename=ipa_images.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "upload=@overcloud-full.tar.md5;filename=overcloud-full.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "$JOB_NAME=SUCCESS"
fi

echo 'Run completed.'
