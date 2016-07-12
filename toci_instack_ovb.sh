#!/usr/bin/env bash
set -eux

## Signal to toci_gate_test.sh we've started
touch /tmp/toci.started

export CURRENT_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
export TRIPLEO_CI_DIR=$CURRENT_DIR/../

export IP_DEVICE=${IP_DEVICE:-"eth0"}

source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_vars.bash
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/common_functions.sh
source $TRIPLEO_CI_DIR/tripleo-ci/scripts/metrics.bash
start_metric "tripleo.ci.total.seconds"

mkdir -p $WORKSPACE/logs

MY_IP=$(ip addr show dev $IP_DEVICE | awk '/inet / {gsub("/.*", "") ; print $2}')

# TODO: Set undercloud_hostname in undercloud.conf
hostname | sudo dd of=/etc/hostname
echo "127.0.0.1 $(hostname) $(hostname).openstacklocal" | sudo tee -a /etc/hosts

# Kill the zuul console stream, its tcp port clashes with the port we're using to serve out /httpboot
sudo netstat -lpn | grep tcp | grep :8088 | awk '{print $7}' | cut -d / -f 1 | head -n 1 | sudo xargs -t kill -9 || true

# TODO: xfsprogs should be a dep of DIB?
sudo yum install -y xfsprogs qemu-img


# Setting up localhost so that postci will ssh to it to retrieve logs
# once the legacy TE support is removed from tripleo-ci we won't need to do
# this any longer
export SEED_IP=127.0.0.1
echo | sudo tee -a ~root/.ssh/authorized_keys | sudo tee -a ~/.ssh/authorized_keys
if [ ! -e /home/jenkins/.ssh/id_rsa.pub ] ; then
    ssh-keygen -N "" -f /home/jenkins/.ssh/id_rsa
fi
cat ~/.ssh/id_rsa.pub | sudo tee -a ~root/.ssh/authorized_keys | sudo tee -a ~/.ssh/authorized_keys

# Remove the anything on the infra image template that might interfere with CI
sudo yum remove -y puppet hiera puppetlabs-release rdo-release
sudo rm -rf /etc/puppet /etc/hiera.yaml

export no_proxy=192.0.2.1,$MY_IP,$MIRRORSERVER

# Setup delorean
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-setup

dummy_ci_repo

# Install all of the repositories we need
$TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup

# Install wget and moreutils for timestamping postci.log with ts
sudo yum -y install wget moreutils python-simplejson dstat yum-plugin-priorities

trap "[ \$? != 0 ] && echo ERROR DURING PREVIOUS COMMAND ^^^ && echo 'See postci.txt in the logs directory for debugging details'; postci 2>&1 | ts '%Y-%m-%d %H:%M:%S.000 |' > $WORKSPACE/logs/postci.log 2>&1" EXIT

delorean_build_and_serve

# Since we've moved a few commands from this spot before the wget, we need to
# sleep a few seconds in order for the SimpleHTTPServer to get setup.
sleep 3

layer_ci_repo

create_dib_vars_for_puppet

export http_proxy=""

echo_vars_to_deploy_env

source $TRIPLEO_ROOT/tripleo-ci/deploy.env

# Add a simple system utilisation logger process
sudo dstat -tcmndrylpg --output /var/log/dstat-csv.log >/dev/null &
# Install our test cert so SSL tests work
sudo cp $TRIPLEO_ROOT/tripleo-ci/test-environments/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
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
