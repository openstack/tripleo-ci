#!/usr/bin/env bash
set -eux

## Signal to toci_gate_test.sh we've started
touch /tmp/toci.started

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

export IP_DEVICE=${IP_DEVICE:-"eth0"}
export ZUUL_PROJECT=${ZUUL_PROJECT:-""}
export CA_SERVER=${CA_SERVER:-""}

source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash
stop_metric "tripleo.testenv.${TOCI_JOBTYPE}.wait.seconds" # start_metric in toci_gate_test.sh
start_metric "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.ci.total.seconds"

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
# Note for tripleo-quickstart: this task is already managed in tripleo-ci-setup-playbook.yml
sudo yum remove -y facter puppet hiera puppetlabs-release rdo-release
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

# We can't use squid to cache https urls, so don't use them
for i in /etc/yum.repos.d/delorean*
do
    # NOTE(bnemec): It seems that using http urls for CBS repos causes a lot
    # of spurious failures due to the forced redirect to https.  Limit this
    # to only the delorean repos that actually allow http access.
    sudo sed -i 's|https://trunk.rdoproject.org|http://trunk.rdoproject.org|g' $i
done

# Install some useful/necessary packages
sudo yum -y install wget python-simplejson yum-plugin-priorities qemu-img

trap "exit_val=\$?; [ \$exit_val != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci \$exit_val 2>&1 | awk '{ print strftime(\"%Y-%m-%d %H:%M:%S.000\"), \"|\", \$0; fflush(); }' > $WORKSPACE/logs/postci.log 2>&1" EXIT

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
    wget --progress=dot:mega http://$MIRRORSERVER/builds-${STABLE_RELEASE:-master}/current-tripleo${STABLE_RELEASE:+-$STABLE_RELEASE}/ipa_images.tar || true
    if [ -f ipa_images.tar ] ; then
        tar -xf ipa_images.tar
        update_image $PWD/ironic-python-agent.initramfs
        mv ironic-python-agent.* ~
        rm ipa_images.tar
    fi
fi

# Same thing for the overcloud image
if canusecache overcloud-full.tar ; then
    wget --progress=dot:mega http://$MIRRORSERVER/builds-${STABLE_RELEASE:-master}/current-tripleo${STABLE_RELEASE:+-$STABLE_RELEASE}/overcloud-full.tar || true
    if [ -f overcloud-full.tar ] ; then
        tar -xf overcloud-full.tar
        update_image $PWD/overcloud-full.qcow2
        mv overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz ~
        rm overcloud-full.tar
    fi
fi

cp -f $TE_DATAFILE ~/instackenv.json

# Use $REMAINING_TIME of infra to calculate maximum time for remaning part of job
# Leave 10 minutes for postci function
REMAINING_TIME=${REMAINING_TIME:-180}
TIME_FOR_DEPLOY=$(( REMAINING_TIME - ($(date +%s) - START_JOB_TIME)/60 - 10 ))
/usr/bin/timeout --preserve-status ${TIME_FOR_DEPLOY}m $TRIPLEO_ROOT/tripleo-ci/scripts/deploy.sh

if [[ $CACHEUPLOAD == 1 && can_promote ]] ; then
    # Get the IPA and overcloud images for caching
    tar -C ~ -cf - ironic-python-agent.initramfs ironic-python-agent.vmlinuz ironic-python-agent.kernel > ipa_images.tar
    tar -C ~ -cf - overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz > overcloud-full.tar

    md5sum overcloud-full.tar > overcloud-full.tar.md5
    md5sum ipa_images.tar > ipa_images.tar.md5

    UPLOAD_FOLDER=builds${STABLE_RELEASE:+-$STABLE_RELEASE}
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "folder=$UPLOAD_FOLDER" -F "upload=@ipa_images.tar;filename=ipa_images.tar"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "folder=$UPLOAD_FOLDER" -F "upload=@overcloud-full.tar;filename=overcloud-full.tar"
    # TODO(pabelanger): Remove qcow2 format, since centos-7 cannot mount nbd with the default kernel.
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "folder=$UPLOAD_FOLDER" -F "upload=@ipa_images.tar.md5;filename=ipa_images.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "folder=$UPLOAD_FOLDER" -F "upload=@overcloud-full.tar.md5;filename=overcloud-full.tar.md5"
    curl http://$MIRRORSERVER/cgi-bin/upload.cgi  -F "repohash=$TRUNKREPOUSED" -F "folder=$UPLOAD_FOLDER" -F "$JOB_NAME=SUCCESS"
fi

echo 'Run completed.'
