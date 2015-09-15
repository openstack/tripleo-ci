#!/usr/bin/env bash

set -eux

if [ ! -e "$TE_DATAFILE" ] ; then
    echo "Couldn't find data file"
    exit 1
fi

export PATH=/sbin:/usr/sbin:$PATH
source toci_functions.sh

export TRIPLEO_ROOT=/opt/stack/new
mkdir -p $WORKSPACE/logs

# Add temporary reverts and cherrypick's here e.g.
# temprevert <projectname> <commit-hash-to-revert> <bugnumber>
# pin <projectname> <commit-hash-to-pin-to> <bugnumber>
# cherrypick <projectname> <gerrit-refspec>

# https://review.openstack.org/#/c/221411/ Bug #1493442
# Make puppet-glance work again on RedHat distros
cherrypick puppet-glance refs/changes/11/221411/1

# Disable horizon on the overcloud. Bug: #1492416
cherrypick tripleo-heat-templates refs/changes/97/219697/2

# Revert https://review.openstack.org/#/c/217753/ bug 1494747
temprevert heat f180cf9e1c106b58c52139a7c999794a7b2e7465 1494747


# ===== Start : Yum repository setup ====
# Some repositories used here are not yet pulled into the openstack infrastructure
# Until this happens we have to grab them separately
[ -d $TRIPLEO_ROOT/delorean ] || git clone https://github.com/openstack-packages/delorean.git $TRIPLEO_ROOT/delorean
[ -d $TRIPLEO_ROOT/instack-undercloud ] || git clone https://git.openstack.org/openstack/instack-undercloud $TRIPLEO_ROOT/instack-undercloud
[ -d $TRIPLEO_ROOT/instack ] || git clone https://git.openstack.org/openstack/instack $TRIPLEO_ROOT/instack
[ -d $TRIPLEO_ROOT/python-tripleoclient ] || git clone https://git.openstack.org/openstack/python-tripleoclient $TRIPLEO_ROOT/python-tripleoclient
[ -d $TRIPLEO_ROOT/tripleo-common ] || git clone https://git.openstack.org/openstack/tripleo-common $TRIPLEO_ROOT/tripleo-common
[ -d $TRIPLEO_ROOT/tuskar ] || git clone https://git.openstack.org/openstack/tuskar $TRIPLEO_ROOT/tuskar
[ -d $TRIPLEO_ROOT/python-tuskarclient ] || git clone https://git.openstack.org/openstack/python-tuskarclient $TRIPLEO_ROOT/python-tuskarclient
[ -d $TRIPLEO_ROOT/ironic-discoverd ] || git clone https://github.com/rdo-management/ironic-discoverd $TRIPLEO_ROOT/ironic-discoverd
[ -d $TRIPLEO_ROOT/tuskar-ui-extras ] || git clone https://github.com/rdo-management/tuskar-ui-extras $TRIPLEO_ROOT/tuskar-ui-extras
[ -d $TRIPLEO_ROOT/python-ironic-inspector-client ] || git clone https://github.com/openstack/python-ironic-inspector-client $TRIPLEO_ROOT/python-ironic-inspector-client

# Now that we have setup all of our git repositories we need to build packages from them
# If this is a job to test master of everything we get a list of all git repo's
if [ -z "${ZUUL_CHANGES:-}" ] ; then
    echo "No change ids specified, building all projects in $TRIPLEO_ROOT"
    ZUUL_CHANGES=$(find $TRIPLEO_ROOT -maxdepth 2 -type d -name .git -printf "%h ")
fi
ZUUL_CHANGES=${ZUUL_CHANGES//^/ }

# We build a rpm for each of the projects in this list on every test, for
# everything else we are using whatever delorean repository we're using
# Note: see BUILDPACKAGES in toci_functions it holds a list of projects
# we are capable of building
for PROJECT in diskimage-builder heat instack instack-undercloud ironic ironic-discoverd os-cloud-config python-ironic-inspector-client python-tripleoclient tripleo-common tripleo-heat-templates tripleo-image-elements tuskar-ui-extras ; do
    if ! echo " $ZUUL_CHANGES " | grep " $PROJECT " ; then
        ZUUL_CHANGES="$ZUUL_CHANGES $PROJECT "
    fi
done

# prep delorean
# "docker build" with 1.7.1-3 appears to be broken on F21
sudo yum install -y https://kojipkgs.fedoraproject.org//packages/docker-io/1.6.2/3.el6/x86_64/docker-io-1.6.2-3.el6.x86_64.rpm \
                    createrepo yum-plugin-priorities yum-utils
sudo systemctl start docker

cd $TRIPLEO_ROOT/delorean
sudo rm -rf data *.sqlite
mkdir -p data

# Delorean has changed the way it references its dependencies, until we figure
# out how best to deal with the new delorean pin it.
git reset --hard 1916092770b35c0b0b6e81b85dd4b41cdf0a293f

sudo semanage fcontext -a -t svirt_sandbox_file_t "$TRIPLEO_ROOT/delorean/data(/.)?"
sudo semanage fcontext -a -t svirt_sandbox_file_t "$TRIPLEO_ROOT/delorean/scripts(/.)?"
sudo restorecon -R "$TRIPLEO_ROOT/delorean"

MY_IP=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}')

sudo chown :$(id -g) /var/run/docker.sock
./scripts/create_build_image.sh centos

sed -i -e "s%target=.*%target=centos%" projects.ini
sed -i -e "s%baseurl=.*%baseurl=http://$MY_IP:8766/%" projects.ini
sed -i -e "s%reponame=.*%reponame=delorean-ci%" projects.ini
# Remove the rpm install test to speed up delorean (our ci test will to this)
# TODO: and an option for this in delorean
sed -i -e 's%.*installed.*%touch $OUTPUT_DIRECTORY/installed%' scripts/build_rpm.sh

virtualenv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python setup.py install

# post ci chores to run at the end of ci
SSH_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=Verbose -o PasswordAuthentication=no'
TARCMD="sudo XZ_OPT=-3 tar -cJf - --exclude=udev/hwdb.bin --exclude=etc/services --exclude=selinux/targeted --exclude=etc/services --exclude=etc/pki /var/log /etc"
function postci(){
    set +e
    if [ -e $TRIPLEO_ROOT/delorean/data/repos/ ] ; then
        # I'd like to tar up repos/current but tar'ed its about 8M it may be a
        # bit much for the log server, maybe when we are building less
        find $TRIPLEO_ROOT/delorean/data/repos -name rpmbuild.log | XZ_OPT=-3 xargs tar -cJf $WORKSPACE/logs/delorean_repos.tar.xz
    fi
    if [ "${HOST_IP}" != "" ] ; then
        # Generate extra state information from the running undercloud
        ssh root@${SEED_IP} /tmp/get_host_info.sh

        # Get logs from the undercloud
        ssh root@${SEED_IP} $TARCMD > $WORKSPACE/logs/undercloud.tar.xz

        # when we ran get_host_info.sh on the undercloud it left the output of nova list in /tmp for us
        for INSTANCE in $(ssh root@${SEED_IP} cat /tmp/nova-list.txt | grep ACTIVE | awk '{printf"%s=%s\n", $4, $12}') ; do
            IP=${INSTANCE//*=}
            NAME=${INSTANCE//=*}
            ssh root@${SEED_IP} su stack -c \"scp $SSH_OPTIONS /tmp/get_host_info.sh heat-admin@$IP:/tmp\"
            ssh root@${SEED_IP} su stack -c \"ssh $SSH_OPTIONS heat-admin@$IP sudo /tmp/get_host_info.sh\"
            ssh root@${SEED_IP} su stack -c \"ssh $SSH_OPTIONS heat-admin@$IP $TARCMD\" > $WORKSPACE/logs/${NAME}.tar.xz
        done
        destroy_vms &> $WORKSPACE/logs/destroy_vms.log
    fi
    return 0
}
trap "postci" EXIT

# build packages
# loop through each of the projects listed in ZUUL_CHANGES if it is a project we
# are capable of building an rpm for then build it.
# e.g. ZUUL_CHANGES=openstack/cinder:master:refs/changes/61/71461/4^opensta...
for PROJ in $ZUUL_CHANGES ; do

    PROJ=$(filterref $PROJ)
    buildpackage $PROJ || continue

    PROJDIR=$TRIPLEO_ROOT/$PROJ

    MAPPED_PROJ=$(./venv/bin/python scripts/map-project-name $PROJ || true)
    [ -e data/$MAPPED_PROJ ] && continue
    cp -r $TRIPLEO_ROOT/$PROJ data/$MAPPED_PROJ
    pushd data/$MAPPED_PROJ
    GITHASH=$(git rev-parse HEAD)
    # TODO: Remove the mtg branches once we stop using rdoinfo from rdo-management
    for BRANCH in master origin/master origin/mgt-master mgt-master ; do
        git checkout -b $BRANCH || git checkout $BRANCH
        git reset --hard $GITHASH
    done
    popd

    # Try the delorean build twice, it too much fails on network blips
    # TODO: make use of better mirrirs (or our own)
    ./venv/bin/delorean --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --build-env DELOREAN_DEV=1 --build-env http_proxy=$http_proxy --info-repo rdoinfo || \
    ./venv/bin/delorean --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --build-env DELOREAN_DEV=1 --build-env http_proxy=$http_proxy --info-repo rdoinfo

done

# kill the http server if its already running
ps -ef | grep -i python | grep SimpleHTTPServer | awk '{print $2}' | xargs kill -9 || true
cd data/repos
sudo iptables -I INPUT -p tcp --dport 8766 -i eth1 -j ACCEPT
python -m SimpleHTTPServer 8766 1>$WORKSPACE/logs/yum_mirror.log 2>$WORKSPACE/logs/yum_mirror_error.log &

# On top of the distro repositories we layer two othere
# 1. A recent version of rdo trunk, we should eventually switch to /current
# 2. Trunk packages we built above, this repo has highest priority
sudo wget http://trunk.rdoproject.org/centos7/df/03/df0377d64e1ef0b53c4e78a8ff6a50159de5131a_733f1417/delorean.repo -O /etc/yum.repos.d/delorean.repo
sudo wget http://$MY_IP:8766/current/delorean-ci.repo -O /etc/yum.repos.d/delorean-ci.repo

# The repository we have just generated should get priority
sudo sed -i -e 's%priority=.*%priority=20%' /etc/yum.repos.d/delorean.repo
sudo sed -i -e 's%priority=.*%priority=1%' /etc/yum.repos.d/delorean-ci.repo

# Remove everything installed from a delorean repository (only requred if ci nodes are being reused)
TOBEREMOVED=$(yumdb search from_repo "*delorean*" | grep -v -e from_repo -e "Loaded plugins" || true)
[ "$TOBEREMOVED" != "" ] &&  sudo yum remove -y $TOBEREMOVED
sudo yum clean all

# ===== End : Yum repository setup ====

cd $TRIPLEO_ROOT
sudo yum install -y diskimage-builder instack-undercloud os-apply-config

PRIV_SSH_KEY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-key --type raw)
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress --key-default '')
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
    ssh $SSH_USER@$HOST_IP virsh destroy seed_${ENV_NUM} || true
    for i in $(seq 0 14) ; do
        ssh $SSH_USER@$HOST_IP virsh destroy baremetalbrbm${ENV_NUM}_${i} || true
    done
}

# TODO : Remove the need for this from instack-undercloud
ls /home/jenkins/.ssh/id_rsa_virt_power || ssh-keygen -f /home/jenkins/.ssh/id_rsa_virt_power -P ""

# TODO : Fix instack-undercloud so TE_DATAFILE can be absolute
cp $TE_DATAFILE instackenv.json
export TE_DATAFILE=instackenv.json

export ANSWERSFILE=/usr/share/instack-undercloud/undercloud.conf.sample
export UNDERCLOUD_VM_NAME=instack
export ELEMENTS_PATH=/usr/share/instack-undercloud

# create DIB environment for puppet variables
echo "export DIB_INSTALLTYPE_puppet_modules=source" > $TRIPLEO_ROOT/puppet.env
for X in $(env | grep DIB.*puppet); do
    echo "export $X" >> $TRIPLEO_ROOT/puppet.env
done

# Build and deploy our undercloud instance
SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
disk-image-create --image-size 30 -a amd64 centos7 instack-vm -o $UNDERCLOUD_VM_NAME
destroy_vms
dd if=$UNDERCLOUD_VM_NAME.qcow2 | ssh $SSHOPTS root@${HOST_IP} copyseed $ENV_NUM
ssh $SSHOPTS root@${HOST_IP} virsh start seed_$ENV_NUM

tripleo wait_for -d 5 -l 20 scp /etc/yum.repos.d/delorean* root@${SEED_IP}:/etc/yum.repos.d

# copy in required ci files
cd $TRIPLEO_ROOT
scp puppet.env tripleo-ci/scripts/get_host_info.sh root@$SEED_IP:/tmp/

ssh $SSHOPTS root@${SEED_IP} <<-EOF

set -eux

ip route add 0.0.0.0/0 dev eth0 via $MY_IP
echo "nameserver 8.8.8.8" > /etc/resolv.conf
export http_proxy=$http_proxy
export no_proxy=192.0.2.1,$MY_IP

# Setting up nosync first to abolish time taken during disk io sync's
yum install -y nosync
echo /usr/lib64/nosync/nosync.so > /etc/ld.so.preload

yum install -y --nogpg https://rdo.fedorapeople.org/openstack-kilo/rdo-release-kilo.rpm
yum install -y yum-plugin-priorities

yum install -y python-tripleoclient

# We need python-ironic-inspector-client but the package conflicts with discovery client so install form pip until we have moved over to inspector completly
yum install -y --nogpg python-pip
pip install python-ironic-inspector-client

# From here down everything runs as the stack user
dd of=/tmp/runasstack <<-EOS

set -eux

export http_proxy=$http_proxy
export no_proxy=192.0.2.1,$MY_IP

# This sets all the DIB_.*puppet variables for undercloud and overcloud installation
source /tmp/puppet.env

# Disable installation of tuskar on the undercloud
cp /usr/share/instack-undercloud/undercloud.conf.sample ~/undercloud.conf
sudo sed -i -e 's/.*enable_tuskar.*/enable_tuskar = false/' ~/undercloud.conf

openstack undercloud install

source stackrc

# I'm removing most of the nodes in the env to speed up discovery
# This could be in jq but I don't know how
python -c 'import simplejson ; d = simplejson.loads(open("instackenv.json").read()) ; del d["nodes"][$NODECOUNT:] ; print simplejson.dumps(d)' > instackenv_reduced.json

export DIB_YUM_REPO_CONF="/etc/yum.repos.d/delorean.repo /etc/yum.repos.d/delorean-ci.repo"

# Ensure our ci repository is given priority over the others when building the image
echo -e '#!/bin/bash\nyum install -y yum-plugin-priorities' | sudo tee /usr/share/diskimage-builder/elements/yum/pre-install.d/99-tmphacks
sudo chmod +x /usr/share/diskimage-builder/elements/yum/pre-install.d/99-tmphacks

# Directing the output of this command to a file as its extreemly verbose
echo "INFO: Check /var/log/image_build.txt for image build output"
openstack overcloud image build --all 2>&1 | sudo dd of=/var/log/image_build.txt
openstack overcloud image upload
openstack baremetal import --json instackenv_reduced.json
openstack baremetal configure boot
openstack baremetal introspection bulk start
openstack flavor create --id auto --ram 4096 --disk 40 --vcpus 1 baremetal
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" baremetal
openstack overcloud deploy --templates $DEPLOYFLAGS
source ~/overcloudrc
nova list

EOS
su -l -c "bash /tmp/runasstack" stack
EOF

exit 0
echo 'Run completed.'
