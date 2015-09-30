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

# ===== Start : Yum repository setup ====
[ -d $TRIPLEO_ROOT/delorean ] || git clone https://github.com/openstack-packages/delorean.git $TRIPLEO_ROOT/delorean

# Now that we have setup all of our git repositories we need to build packages from them
# If this is a job to test master of everything we get a list of all git repo's
if [ -z "${ZUUL_CHANGES:-}" ] ; then
    echo "No change ids specified, building all projects in $TRIPLEO_ROOT"
    ZUUL_CHANGES=$(find $TRIPLEO_ROOT -maxdepth 2 -type d -name .git -printf "%h ")
fi
ZUUL_CHANGES=${ZUUL_CHANGES//^/ }

# prep delorean
sudo yum install -y docker-io createrepo yum-plugin-priorities yum-utils
sudo systemctl start docker

cd $TRIPLEO_ROOT/delorean
sudo rm -rf data *.sqlite
mkdir -p data

sudo semanage fcontext -a -t svirt_sandbox_file_t "$TRIPLEO_ROOT/delorean/data(/.)?"
sudo semanage fcontext -a -t svirt_sandbox_file_t "$TRIPLEO_ROOT/delorean/scripts(/.)?"
sudo restorecon -R "$TRIPLEO_ROOT/delorean"

MY_IP=$(ip addr show dev eth1 | awk '/inet / {gsub("/.*", "") ; print $2}')

sudo chown :$(id -g) /var/run/docker.sock
# Download a prebuilt build image instead of building one.
# Image built as usual then exported using "docker save delorean/centos > centos-$date-$x.tar"
curl http://${PYPIMIRROR}/buildimages/centos-20150921-1.tar | docker load

docker rm -f builder-centos || true

sed -i -e "s%reponame=.*%reponame=delorean-ci%" projects.ini
sed -i -e "s%target=.*%target=centos%" projects.ini
sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7%" projects.ini
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
for PROJFULLREF in $ZUUL_CHANGES ; do

    PROJ=$(filterref $PROJFULLREF)

    # If ci is being run for a change to ci its ok not to have a ci repository
    # We also don't build packages for puppet repositories, we use them from source
    if [ "$PROJ" == "tripleo-ci" ] || [[ "$PROJ" =~ puppet-* ]] ; then
        NO_CI_REPO_OK=1
        if [[ "$PROJ" =~ puppet-* ]] ; then
            # openstack/puppet-nova:master:refs/changes/02/213102/5 -> refs/changes/02/213102/5
            export DIB_REPOREF_${PROJ//-/_}=${PROJFULLREF##*:}
        fi
    fi

    # There is no tripleo-incubator package, so we need to translate the project name to tripleo
    if [ "$PROJ" == "tripleo-incubator" ] ; then
        PROJ="tripleo"
    fi

    MAPPED_PROJ=$(./venv/bin/python scripts/map-project-name $PROJ || true)
    [ -e data/$MAPPED_PROJ ] && continue
    cp -r $TRIPLEO_ROOT/$PROJ data/$MAPPED_PROJ
    pushd data/$MAPPED_PROJ
    GITHASH=$(git rev-parse HEAD)

    # Set the branches delorean reads to the same git hash as ZUUL has left for us
    for BRANCH in master origin/master ; do
        git checkout -b $BRANCH || git checkout $BRANCH
        git reset --hard $GITHASH
    done
    popd

    ./venv/bin/delorean --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --build-env DELOREAN_DEV=1 --build-env http_proxy=$http_proxy --info-repo rdoinfo
done

# If this was a ci job for a change to ci then we do not have a ci repository (no packages to build)
# Create a dummy repository file so ci can proceed as normal
if [ "${NO_CI_REPO_OK:-}" == 1 ] ; then
    mkdir -p data/repos/current
    touch data/repos/current/delorean-ci.repo
fi

# kill the http server if its already running
ps -ef | grep -i python | grep SimpleHTTPServer | awk '{print $2}' | xargs kill -9 || true
cd data/repos
sudo iptables -I INPUT -p tcp --dport 8766 -i eth1 -j ACCEPT
python -m SimpleHTTPServer 8766 1>$WORKSPACE/logs/yum_mirror.log 2>$WORKSPACE/logs/yum_mirror_error.log &

# Install all of the repositories we need
sudo $TRIPLEO_ROOT/tripleo-common/scripts/tripleo.sh --repo-setup

# Layer the ci repository on top of it
sudo wget http://$MY_IP:8766/current/delorean-ci.repo -O /etc/yum.repos.d/delorean-ci.repo
# rewrite the baseurl in delorean-ci.repo as its currently pointing a http://trunk.rdoproject.org/..
sudo sed -i -e "s%baseurl=.*%baseurl=http://$MY_IP:8766/current/%" /etc/yum.repos.d/delorean-ci.repo
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

export ANSWERSFILE=/usr/share/instack-undercloud/undercloud.conf.sample
export UNDERCLOUD_VM_NAME=instack
export ELEMENTS_PATH=/usr/share/instack-undercloud
export DIB_DISTRIBUTION_MIRROR=$CENTOS_MIRROR
export DIB_EPEL_MIRROR=$EPEL_MIRROR

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
scp puppet.env tripleo-ci/scripts/get_host_info.sh $TRIPLEO_ROOT/tripleo-common/scripts/tripleo.sh root@$SEED_IP:/tmp/

ssh $SSHOPTS root@${SEED_IP} <<-EOF

set -eux

ip route add 0.0.0.0/0 dev eth0 via $MY_IP
echo "nameserver 8.8.8.8" > /etc/resolv.conf
export http_proxy=$http_proxy
export no_proxy=192.0.2.1,$MY_IP

# Setting up nosync first to abolish time taken during disk io sync's
yum install -y nosync
echo /usr/lib64/nosync/nosync.so > /etc/ld.so.preload

yum install -y yum-plugin-priorities

# From here down everything runs as the stack user
dd of=/tmp/runasstack <<-EOS

set -eux

# I'm removing most of the nodes in the env to speed up discovery
# This could be in jq but I don't know how
sudo yum -y install python-simplejson
python -c 'import simplejson ; d = simplejson.loads(open("instackenv.json").read()) ; del d["nodes"][$NODECOUNT:] ; print simplejson.dumps(d)' > instackenv_reduced.json
mv instackenv_reduced.json instackenv.json

export DIB_DISTRIBUTION_MIRROR=$CENTOS_MIRROR
export DIB_EPEL_MIRROR=$EPEL_MIRROR

# This sets all the DIB_.*puppet variables for undercloud and overcloud installation
source /tmp/puppet.env

export http_proxy=$http_proxy
export no_proxy=192.0.2.1,$MY_IP,$SEED_IP
export OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS"

/tmp/tripleo.sh --undercloud
# Directing the output of this command to a file as its extreemly verbose
echo "INFO: Check /var/log/image_build.txt for image build output"
/tmp/tripleo.sh --overcloud-images | sudo dd of=/var/log/image_build.txt
/tmp/tripleo.sh --register-nodes

# Introspection currently disabled should be re-enabled by:
# https://review.openstack.org/#/c/225934/
# /tmp/tripleo.sh --introspect-nodes

sleep 60
/tmp/tripleo.sh --flavors
/tmp/tripleo.sh --overcloud-deploy

# Sanity test we deployed what we said we would
source ~/stackrc
[ "$NODECOUNT" != \\\$(nova list | grep ACTIVE | wc -l | cut -f1 -d " ") ] && echo "Wrong number of nodes deployed" && exit 1

source ~/overcloudrc
nova list

EOS
su -l -c "bash /tmp/runasstack" stack
EOF

exit 0
echo 'Run completed.'
