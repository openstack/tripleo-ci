#!/bin/bash
# Copyright 2015 Red Hat, Inc.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

##############################################################################
# tripleo.sh is a script to automate a TripleO setup. It's goals are to be
# used in aiding:
#
# - developer setups
# - CI
# - documentation generation (hopefully)
#
# It's not a new CLI, or end user facing wrapper around existing TripleO
# CLI's.
#
# tripleo.sh should never contain any "business" logic in it that is
# necessary for a successful deployment. It should instead just mirror the
# steps that we document for TripleO end users.
#
##############################################################################


set -eu
set -o pipefail

SCRIPT_NAME=${SCRIPT_NAME:-$(basename $0)}

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Automates TripleO setup steps."
    echo
    echo "$SCRIPT_NAME is also configurable via environment variables, most of"
    echo "which are not exposed via cli args for simplicity. See the source"
    echo "for the set of environment variables that can be overridden."
    echo
    echo "Note that cli args always take precedence over environment"
    echo "variables."
    echo
    echo "Options:"
    echo "      --repo-setup            -- Perform repository setup."
    echo "      --delorean-setup        -- Install local delorean build environment."
    echo "      --delorean-build        -- Build a delorean package locally"
    echo "      --multinode-setup       -- Perform multinode setup."
    echo "      --bootstrap-subnodes    -- Perform bootstrap setup on subnodes."
    echo "      --setup-nodepool-files  -- Setup nodepool files on subnodes."
    echo "      --undercloud            -- Install the undercloud."
    echo "      --undercloud-containers -- Install the undercloud with containers."
    echo "      --overcloud-images      -- Build and load overcloud images."
    echo "      --register-nodes        -- Register and configure nodes."
    echo "      --introspect-nodes      -- Introspect nodes."
    echo "      --undercloud-upgrade    -- Upgrade a deployed undercloud."
    echo "      --overcloud-deploy      -- Deploy an overcloud."
    echo "      --overcloud-update      -- Update a deployed overcloud."
    echo "      --overcloud-upgrade     -- Upgrade a deployed overcloud."
    echo "      --overcloud-upgrade-converge -- Finish (converge) upgrade of a deployed overcloud."
    echo "      --overcloud-delete      -- Delete the overcloud."
    echo "      --use-containers        -- Use a containerized compute node."
    echo "      --enable-check          -- Enable checks on update."
    echo "      --overcloud-pingtest    -- Run a tenant vm, attach and ping floating IP."
    echo "      --overcloud-sanitytest    -- Run some basic crud checks for each service."
    echo "      --skip-sanitytest-create  -- Do not create resources when performing a sanitytest (assume they exist)."
    echo "      --skip-sanitytest-cleanup -- Do not delete the created resources when performing a sanitytest."
    echo "      --skip-pingtest-cleanup -- For debuging purposes, do not delete the created resources when performing a pingtest."
    echo "      --run-tempest           -- Run tempest tests."
    echo "      --all, -a               -- Run all of the above commands."
    echo "      -x                      -- enable tracing"
    echo "      --help, -h              -- Print this help message."
    echo
    exit 1
}

if [ ${#@} = 0 ]; then
    show_options
    exit 1
fi

TEMP=$(getopt -o ,h \
        -l,help,repo-setup,delorean-setup,delorean-build,multinode-setup,bootstrap-subnodes,undercloud,undercloud-containers,overcloud-images,register-nodes,introspect-nodes,overcloud-deploy,overcloud-update,overcloud-upgrade,overcloud-upgrade-converge,overcloud-delete,use-containers,overcloud-pingtest,undercloud-upgrade,skip-pingtest-cleanup,all,enable-check,run-tempest,setup-nodepool-files,overcloud-sanitytest,skip-sanitytest-create,skip-sanitytest-cleanup \
        -o,x,h,a \
        -n $SCRIPT_NAME -- "$@")

if [ $? != 0 ]; then
    show_options
    exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

TRIPLEO_ROOT=${TRIPLEO_ROOT:-$HOME/tripleo}

# Source deploy.env if it exists. It should exist if we are running under
# tripleo-ci
if [ -f "$TRIPLEO_ROOT/tripleo-ci/deploy.env" ]; then
    source $TRIPLEO_ROOT/tripleo-ci/deploy.env
fi

ALL=${ALL:-""}
CONTAINER_ARGS=${CONTAINER_ARGS:-"-e /usr/share/openstack-tripleo-heat-templates/environments/docker.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/docker-network.yaml --libvirt-type=qemu"}
STABLE_RELEASE=${STABLE_RELEASE:-}
REVIEW_RELEASE=${REVIEW_RELEASE:-$STABLE_RELEASE}
UPGRADE_RELEASE=${UPGRADE_RELEASE:-""}
DELOREAN_REPO_FILE=${DELOREAN_REPO_FILE:-"delorean.repo"}
DELOREAN_REPO_URL=${DELOREAN_REPO_URL:-"\
    http://trunk.rdoproject.org/centos7/current-tripleo/"}
DELOREAN_STABLE_REPO_URL=${DELOREAN_STABLE_REPO_URL:-"\
    https://trunk.rdoproject.org/centos7-$STABLE_RELEASE/current/"}
ATOMIC_URL=${ATOMIC_URL:-"https://download.fedoraproject.org/pub/alt/atomic/stable/Cloud-Images/x86_64/Images/Fedora-Cloud-Atomic-23-20160308.x86_64.qcow2"}
INSTACKENV_JSON_PATH=${INSTACKENV_JSON_PATH:-"$HOME/instackenv.json"}
INTROSPECT_NODES=${INTROSPECT_NODES:-""}
REGISTER_NODES=${REGISTER_NODES:-""}
OVERCLOUD_DEPLOY=${OVERCLOUD_DEPLOY:-""}
OVERCLOUD_DELETE=${OVERCLOUD_DELETE:-""}
OVERCLOUD_DELETE_TIMEOUT=${OVERCLOUD_DELETE_TIMEOUT:-"300"}
OVERCLOUD_DEPLOY_ARGS=${OVERCLOUD_DEPLOY_ARGS:-""}
# --validation-errors-fatal was deprecated in newton and removed in ocata
if [[ "${STABLE_RELEASE}" = "mitaka" ]]; then
    OVERCLOUD_VALIDATE_ARGS=${OVERCLOUD_VALIDATE_ARGS-"--validation-errors-fatal --validation-warnings-fatal"}
else
    OVERCLOUD_VALIDATE_ARGS=${OVERCLOUD_VALIDATE_ARGS-"--validation-warnings-fatal"}
fi
OVERCLOUD_UPDATE=${OVERCLOUD_UPDATE:-""}
OVERCLOUD_UPGRADE=${OVERCLOUD_UPGRADE:-""}
OVERCLOUD_UPGRADE_CONVERGE=${OVERCLOUD_UPGRADE_CONVERGE:-""}
OVERCLOUD_UPDATE_RM_FILES=${OVERCLOUD_UPDATE_RM_FILES:-"1"}
OVERCLOUD_UPDATE_ARGS=${OVERCLOUD_UPDATE_ARGS:-"$OVERCLOUD_DEPLOY_ARGS $OVERCLOUD_VALIDATE_ARGS"}
OVERCLOUD_UPDATE_CHECK=${OVERCLOUD_UPDATE_CHECK:-}
OVERCLOUD_IMAGES_PATH=${OVERCLOUD_IMAGES_PATH:-"$HOME"}
OVERCLOUD_IMAGES_YAML_PATH=${OVERCLOUD_IMAGES_YAML_PATH:-"/usr/share/openstack-tripleo-common/image-yaml"}
OVERCLOUD_IMAGES=${OVERCLOUD_IMAGES:-""}
OVERCLOUD_IMAGES_LEGACY_ARGS=${OVERCLOUD_IMAGES_LEGACY_ARGS:-"--all"}
OVERCLOUD_IMAGES_ARGS=${OVERCLOUD_IMAGES_ARGS:-"--output-directory $OVERCLOUD_IMAGES_PATH --config-file $OVERCLOUD_IMAGES_YAML_PATH/overcloud-images.yaml --config-file $OVERCLOUD_IMAGES_YAML_PATH/overcloud-images-centos7.yaml"}
OVERCLOUD_NAME=${OVERCLOUD_NAME:-"overcloud"}
OVERCLOUD_UPGRADE_THT_PATH=${OVERCLOUD_UPGRADE_THT_PATH:-"/usr/share/openstack-tripleo-heat-templates"}
OVERCLOUD_UPGRADE_ARGS=${OVERCLOUD_UPGRADE_ARGS:-"-e $OVERCLOUD_UPGRADE_THT_PATH/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS -e $OVERCLOUD_UPGRADE_THT_PATH/environments/major-upgrade-composable-steps.yaml -e $HOME/init-repo.yaml --templates $OVERCLOUD_UPGRADE_THT_PATH"}
OVERCLOUD_UPGRADE_CONVERGE_ARGS=${OVERCLOUD_UPGRADE_CONVERGE_ARGS:-"-e $OVERCLOUD_UPGRADE_THT_PATH/overcloud-resource-registry-puppet.yaml $OVERCLOUD_DEPLOY_ARGS -e $OVERCLOUD_UPGRADE_THT_PATH/environments/major-upgrade-converge.yaml --templates $OVERCLOUD_UPGRADE_THT_PATH"}
UPGRADE_VERSION=${UPGRADE_VERSION:-"master"}
UPGRADE_REPO_URL=${UPGRADE_REPO_URL:-"http://buildlogs.centos.org/centos/7/cloud/x86_64/rdo-trunk-$UPGRADE_VERSION-tested/delorean.repo"}
UPGRADE_OVERCLOUD_REPO_URL=${UPGRADE_OVERCLOUD_REPO_URL:-"http://buildlogs.centos.org/centos/7/cloud/x86_64/rdo-trunk-$UPGRADE_VERSION-tested/delorean.repo"}
UNDERCLOUD_UPGRADE=${UNDERCLOUD_UPGRADE:-""}
UNDERCLOUD_CONTAINERS=${UNDERCLOUD_CONTAINERS:-""}
UPGRADE_VERSION=${UPGRADE_VERSION:-"master"}
OVERCLOUD_SANITYTEST_SKIP_CREATE=${OVERCLOUD_SANITYTEST_SKIP_CREATE:-""}
OVERCLOUD_SANITYTEST_SKIP_CLEANUP=${OVERCLOUD_SANITYTEST_SKIP_CLEANUP:-""}
OVERCLOUD_SANITYTEST=${OVERCLOUD_SANITYTEST:-""}
SANITYTEST_CONTENT_NAME=${SANITYTEST_CONTENT_NAME:-"sanity_test"}
SKIP_PINGTEST_CLEANUP=${SKIP_PINGTEST_CLEANUP:-""}
OVERCLOUD_PINGTEST=${OVERCLOUD_PINGTEST:-""}
UNDERCLOUD_SANITY_CHECK=${UNDERCLOUD_SANITY_CHECK:-""}
REPO_SETUP=${REPO_SETUP:-""}
REPO_PREFIX=${REPO_PREFIX:-"/etc/yum.repos.d/"}
OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF:-"\
    $REPO_PREFIX/delorean.repo \
    $REPO_PREFIX/delorean-current.repo \
    $REPO_PREFIX/delorean-deps.repo"}
# Use Ceph/Jewel for all but mitaka
if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
  OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF}"\
    $REPO_PREFIX/CentOS-Ceph-Hammer.repo"
else
  OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF}"\
    $REPO_PREFIX/CentOS-Ceph-Jewel.repo"
fi
OPSTOOLS_REPO_ENABLED=${OPSTOOLS_REPO_ENABLED:-"0"}
OPSTOOLS_REPO_URL=${OPSTOOLS_REPO_URL:-"https://raw.githubusercontent.com/centos-opstools/opstools-repo/master/opstools.repo"}
if [[ "${OPSTOOLS_REPO_ENABLED}" = 1 ]]; then
  OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF}"\
    $REPO_PREFIX/centos-opstools.repo"
fi
FEATURE_BRANCH=${FEATURE_BRANCH:-}
DELOREAN_SETUP=${DELOREAN_SETUP:-""}
DELOREAN_BUILD=${DELOREAN_BUILD:-""}
MULTINODE_SETUP=${MULTINODE_SETUP:-""}
MULTINODE_ENV_NAME=${MULTINODE_ENV_NAME:-}
MTU=${MTU:-"1450"}
BOOTSTRAP_SUBNODES=${BOOTSTRAP_SUBNODES:-""}
SETUP_NODEPOOL_FILES=${SETUP_NODEPOOL_FILES:-""}
PRIMARY_NODE_IP=${PRIMARY_NODE_IP:-""}
SUB_NODE_IPS=${SUB_NODE_IPS:-""}
NODEPOOL_REGION=${NODEPOOL_REGION:-"nodepool_region"}
NODEPOOL_CLOUD=${NODEPOOL_CLOUD:-"nodepool_cloud"}
STDERR=/dev/null
UNDERCLOUD=${UNDERCLOUD:-""}
UNDERCLOUD_CONF=${UNDERCLOUD_CONF:-"/usr/share/instack-undercloud/undercloud.conf.sample"}
UNDERCLOUD_SSL=${UNDERCLOUD_SSL:-""}
BASE=${BASE:-$TRIPLEO_ROOT}
USE_CONTAINERS=${USE_CONTAINERS:-""}
TEMPEST_RUN=${TEMPEST_RUN:-""}
TEMPEST_ARGS=${TEMPEST_ARGS:-"--parallel --subunit"}
TEMPEST_ADD_CONFIG=${TEMPEST_ADD_CONFIG:-}
TEMPEST_REGEX=${TEMPEST_REGEX:-"^(?=(.*smoke))(?!(tempest.api.orchestration.stacks|tempest.scenario.test_volume_boot_pattern|tempest.api.telemetry))"}
TEMPEST_PINNED="72ccabcb685df7c3e28cd25639b05d8a031901c8"
SSH_OPTIONS=${SSH_OPTIONS:-'-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=Verbose -o PasswordAuthentication=no -o ConnectionAttempts=32'}
export SCRIPTS_DIR=$(dirname ${BASH_SOURCE[0]:-$0})

if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
    export OS_IMAGE_API_VERSION=1
fi
# Temporary workarounds

while true ; do
    case "$1" in
        --all|-a ) ALL="1"; shift 1;;
        --use-containers) USE_CONTAINERS="1"; shift 1;;
        --enable-check) OVERCLOUD_UPDATE_CHECK="1"; shift 1;;
        --introspect-nodes) INTROSPECT_NODES="1"; shift 1;;
        --register-nodes) REGISTER_NODES="1"; shift 1;;
        --overcloud-deploy) OVERCLOUD_DEPLOY="1"; shift 1;;
        --overcloud-update) OVERCLOUD_UPDATE="1"; shift 1;;
        --overcloud-upgrade) OVERCLOUD_UPGRADE="1"; shift 1;;
        --overcloud-upgrade-converge) OVERCLOUD_UPGRADE_CONVERGE="1"; shift 1;;
        --overcloud-delete) OVERCLOUD_DELETE="1"; shift 1;;
        --overcloud-images) OVERCLOUD_IMAGES="1"; shift 1;;
        --overcloud-pingtest) OVERCLOUD_PINGTEST="1"; shift 1;;
        --skip-pingtest-cleanup) SKIP_PINGTEST_CLEANUP="1"; shift 1;;
        --overcloud-sanitytest) OVERCLOUD_SANITYTEST="1"; shift 1;;
        --skip-sanitytest-create) OVERCLOUD_SANITYTEST_SKIP_CREATE="1"; shift 1;;
        --skip-sanitytest-cleanup) OVERCLOUD_SANITYTEST_SKIP_CLEANUP="1"; shift 1;;
        --run-tempest) TEMPEST_RUN="1"; shift 1;;
        --repo-setup) REPO_SETUP="1"; shift 1;;
        --delorean-setup) DELOREAN_SETUP="1"; shift 1;;
        --delorean-build) DELOREAN_BUILD="1"; shift 1;;
        --undercloud) UNDERCLOUD="1"; shift 1;;
        --undercloud-containers) UNDERCLOUD_CONTAINERS="1"; shift 1;;
        --undercloud-upgrade) UNDERCLOUD_UPGRADE="1"; shift 1;;
        --multinode-setup) MULTINODE_SETUP="1"; shift 1;;
        --bootstrap-subnodes) BOOTSTRAP_SUBNODES="1"; shift 1;;
        --setup-nodepool-files) SETUP_NODEPOOL_FILES="1"; shift 1;;
        -x) set -x; STDERR=/dev/stderr; shift 1;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

function log {
    echo "#################"
    echo -n "$SCRIPT_NAME -- "
    echo $@
    echo "#################"
}

function source_rc {
    if [ $1 = "stackrc" ] ; then cloud="Undercloud"; else cloud="Overcloud"; fi
    echo "You must source a $1 file for the $cloud."
    echo "Attempting to source $HOME/$1"
    source $HOME/$1
    echo "Done"
}

function stackrc_check {
    source_rc "stackrc"
}

function overcloudrc_check {
    source_rc "overcloudrc"
}

function repo_setup {

    log "Repository setup"

    sudo yum clean metadata

    # sets $TRIPLEO_OS_FAMILY and $TRIPLEO_OS_DISTRO
    source $(dirname ${BASH_SOURCE[0]:-$0})/set-os-type

    if [ "$TRIPLEO_OS_DISTRO" = "centos" ]; then
        # Enable Storage/SIG Ceph repo
        if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
            CEPH_REPO_RPM=centos-release-ceph-hammer
            CEPH_REPO_FILE=CentOS-Ceph-Hammer.repo
        else
            if rpm -q centos-release-ceph-hammer; then
                sudo yum -y erase centos-release-ceph-hammer
            fi
            CEPH_REPO_RPM=centos-release-ceph-jewel
            CEPH_REPO_FILE=CentOS-Ceph-Jewel.repo
        fi

        if [[ "${OPSTOOLS_REPO_ENABLED}" = 1 ]]; then
            sudo curl -Lvo $REPO_PREFIX/centos-opstools.repo \
                "${OPSTOOLS_REPO_URL}"
        fi

        if [ $REPO_PREFIX != "/etc/yum.repos.d/" ]; then
            # Note yum --installroot doesn't seem to work as it can't find the extras repos in the
            # system yum.repos.d, so download the package then extraact the repo file
            mkdir -p $REPO_PREFIX
            yumdownloader --destdir $REPO_PREFIX $CEPH_REPO_RPM
            pushd $REPO_PREFIX
            rpm2cpio ${CEPH_REPO_RPM}*.rpm | cpio -ivd
            mv etc/yum.repos.d/* .
            popd
        else
            sudo yum -y install --enablerepo=extras $CEPH_REPO_RPM
        fi
        sudo sed -i -e 's%gpgcheck=.*%gpgcheck=0%' ${REPO_PREFIX}/${CEPH_REPO_FILE}
    fi
    # @matbu TBR debuginfo:
    log "Stable release: $STABLE_RELEASE"
    if [ -z "$STABLE_RELEASE" ]; then
        # Enable the Delorean Deps repository
        sudo curl -Lvo $REPO_PREFIX/delorean-deps.repo http://trunk.rdoproject.org/centos7/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo
        cat $REPO_PREFIX/delorean-deps.repo

        # Enable last known good RDO Trunk Delorean repository
        sudo curl -Lvo $REPO_PREFIX/delorean.repo $DELOREAN_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo
        cat $REPO_PREFIX/delorean.repo

        # Enable latest RDO Trunk Delorean repository
        sudo curl -Lvo $REPO_PREFIX/delorean-current.repo http://trunk.rdoproject.org/centos7/current/delorean.repo
        sudo sed -i -e 's%priority=.*%priority=10%' $REPO_PREFIX/delorean-current.repo
        sudo sed -i 's/\[delorean\]/\[delorean-current\]/' $REPO_PREFIX/delorean-current.repo
        sudo /bin/bash -c "cat <<-EOF>>$REPO_PREFIX/delorean-current.repo

includepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-cloud-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-common,openstack-tripleo-heat-templates,openstack-tripleo-image-elements,openstack-tripleo,openstack-tripleo-puppet-elements,openstack-puppet-modules,openstack-tripleo-ui,puppet-*
EOF"
        cat $REPO_PREFIX/delorean-current.repo
    else
        # Enable the Delorean Deps repository
        sudo curl -Lvo $REPO_PREFIX/delorean-deps.repo http://trunk.rdoproject.org/centos7-$STABLE_RELEASE/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo
        cat $REPO_PREFIX/delorean-deps.repo

        # Enable delorean current for the stable version
        sudo curl -Lvo $REPO_PREFIX/delorean.repo $DELOREAN_STABLE_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo
        cat $REPO_PREFIX/delorean.repo

        # Create empty delorean-current for dib image building
        sudo sh -c "> $REPO_PREFIX/delorean-current.repo"
        cat $REPO_PREFIX/delorean-current.repo
    fi

    # Install the yum-plugin-priorities package so that the Delorean repository
    # takes precedence over the main RDO repositories.
    sudo yum -y install yum-plugin-priorities

    # Make sure EPEL is uninstalled.
    if rpm --quiet -q epel-release; then
        sudo rpm -e epel-release
    fi

    sudo yum clean all
    sudo yum makecache

    log "Repository setup - DONE."

}

function delorean_setup {

    log "Delorean setup"

    # Install delorean as per combination of toci-instack and delorean docs
    sudo yum install -y createrepo git mock rpm-build yum-plugin-priorities yum-utils gcc

    # NOTE(pabelanger): Check if virtualenv is already install, if not install
    # from packages.
    if ! command -v virtualenv ; then
        sudo yum install -y python-virtualenv
    fi

    # Workaround until https://review.openstack.org/#/c/311734/ is merged and a new image is built
    sudo yum install -y libffi-devel openssl-devel

    # Add the current user to the mock group
    sudo usermod -G mock -a $(id -nu)

    mkdir -p $TRIPLEO_ROOT
    [ -d $TRIPLEO_ROOT/delorean ] || git clone https://github.com/openstack-packages/delorean.git $TRIPLEO_ROOT/delorean

    pushd $TRIPLEO_ROOT/delorean

    sudo rm -rf data commits.sqlite
    mkdir -p data

    sed -i -e "s%reponame=.*%reponame=delorean-ci%" projects.ini
    sed -i -e "s%target=.*%target=centos%" projects.ini

    # Remove the rpm install test to speed up delorean (our ci test will to this)
    # TODO: add an option for this in delorean
    sed -i -e 's%--postinstall%%' scripts/build_rpm.sh

    virtualenv venv
    # NOTE(pabelanger): We need to update setuptools to the latest version for
    # CentOS 7.  Also, pytz is not declared as a dependency so we need to
    # manually add it.  Lastly, use pip install . to use wheel AFS pypi mirrors.
    ./venv/bin/pip install -U setuptools
    ./venv/bin/pip install pytz
    ./venv/bin/pip install .

    popd
    log "Delorean setup - DONE."
}

function delorean_build {

    log "Delorean build"

    export PATH=/sbin:/usr/sbin:$PATH
    source $(dirname ${BASH_SOURCE[0]:-$0})/common_functions.sh

    pushd $TRIPLEO_ROOT/delorean

    if [ -n "$REVIEW_RELEASE" ]; then
        log "Building for release $REVIEW_RELEASE"
        # first check if we have a stable release
        sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7-$REVIEW_RELEASE%" projects.ini
        if [ "$REVIEW_RELEASE" = "mitaka" ]; then
            sed -i -e "s%distro=.*%distro=rpm-$REVIEW_RELEASE%" projects.ini
        else
            # RDO changed the distgit branch for stable releases starting from newton.
            sed -i -e "s%distro=.*%distro=$REVIEW_RELEASE-rdo%" projects.ini
        fi
        sed -i -e "s%source=.*%source=stable/$REVIEW_RELEASE%" projects.ini
    elif [ -n "$FEATURE_BRANCH" ]; then
        # next, check if we are testing for a feature branch
        log "Building for feature branch $FEATURE_BRANCH"
        sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7%" projects.ini
        sed -i -e "s%distro=.*%distro=rpm-$FEATURE_BRANCH%" projects.ini
        sed -i -e "s%source=.*%source=$FEATURE_BRANCH%" projects.ini
    else
        log "Building for master"
        sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7%" projects.ini
        sed -i -e "s%distro=.*%distro=rpm-master%" projects.ini
        sed -i -e "s%source=.*%source=master%" projects.ini
    fi

    sudo rm -rf data commits.sqlite
    mkdir -p data

    # build packages
    # loop through each of the projects listed in DELOREAN_BUILD_REFS, if it is a project we
    # are capable of building an rpm for then build it.
    # e.g. DELOREAN_BUILD_REFS="openstack/cinder openstack/heat etc.."
    for PROJ in $DELOREAN_BUILD_REFS ; do
        log "Building $PROJ"

        PROJ=$(filterref $PROJ)

        # Clone the repo if it doesn't yet exist
        if [ ! -d $TRIPLEO_ROOT/$PROJ ]; then
            git clone https://git.openstack.org/openstack/$PROJ.git $TRIPLEO_ROOT/$PROJ
            if [ ! -z "$REVIEW_RELEASE" ]; then
                pushd $TRIPLEO_ROOT/$PROJ
                git checkout -b stable/$REVIEW_RELEASE origin/stable/$REVIEW_RELEASE
                popd
            fi
        fi

        # Work around inconsistency where map-project-name expects oslo-*
        MAPPED_NAME=$(echo $PROJ | sed "s/oslo./oslo-/")
        MAPPED_PROJ=$(./venv/bin/python scripts/map-project-name $MAPPED_NAME || true)
        [ -e data/$MAPPED_PROJ ] && continue
        cp -r $TRIPLEO_ROOT/$PROJ data/$MAPPED_PROJ
        pushd data/$MAPPED_PROJ
        GITHASH=$(git rev-parse HEAD)

        # Set the branches delorean reads to the same git hash as PROJ has left for us
        for BRANCH in master origin/master stable/mitaka origin/stable/mitaka stable/newton origin/stable/newton stable/ocata origin/stable/ocata; do
            git checkout -b $BRANCH || git checkout $BRANCH
            git reset --hard $GITHASH
        done
        popd

        set +e
        while true; do
            DELOREANCMD="./venv/bin/dlrn --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --use-public --build-env http_proxy=${http_proxy:-} --info-repo rdoinfo"
            # Using sudo to su a command as ourselves to run the command with a new login
            # to ensure the addition to the mock group has taken effect.
            sudo su $(id -nu) -c "$DELOREANCMD"
            EXITCODE=$?

            # delorean exits with 2 if the error is a network glitch, we can retry
            if [ "$EXITCODE" == "2" ] ; then
                continue
            elif [ "$EXITCODE" == "0" ] ; then
                break
            fi
            set -e
            exit 1
        done
        set -e
    done
    popd
    log "Delorean build - DONE."
}

function undercloud {

    log "Undercloud install"

    sudo yum install -y python-tripleoclient

    if [ ! -f ~/undercloud.conf ]; then
        cp -b -f $UNDERCLOUD_CONF ~/undercloud.conf
    else
        log "~/undercloud.conf  already exists, not overwriting"
    fi

    # Hostname check, add to /etc/hosts if needed
    if ! grep -E "^127.0.0.1\s*$(hostname -f)" /etc/hosts; then
        sudo sed -i "s/127.0.0.1\s*\(.*\)/127.0.0.1\t$(hostname -f) $(hostname -s) \1/" /etc/hosts
    fi
    if ! grep -E "^::1\s*$(hostname -f)" /etc/hosts; then
        sudo sed -i "s/::1\s*\(.*\)/::1\t$(hostname -f) $(hostname -s) \1/" /etc/hosts
    fi

    openstack undercloud install

    log "Undercloud install - DONE."

}

function undercloud_containers {

    log "Undercloud install containers"
    # FIXME: eventually we will wire this into 'openstack undercloud install'
    # but for now we manually do these things to mimic that functionality today
    sudo setenforce permissive
    sudo sed -i 's/SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    sudo yum install -y \
      openstack-heat-api \
      openstack-heat-engine \
      openstack-heat-monolith \
      python-heat-agent \
      python-heat-agent-ansible \
      python-heat-agent-apply-config \
      python-heat-agent-hiera \
      python-heat-agent-puppet \
      python-heat-agent-docker-cmd \
      python-heat-agent-json-file \
      python-ipaddr \
      python-tripleoclient \
      docker \
      openvswitch \
      openstack-puppet-modules \
      openstack-kolla
    cd

    sudo systemctl start openvswitch
    if [ -n "${LOCAL_REGISTRY:-}" ]; then
      echo "INSECURE_REGISTRY='--insecure-registry ${LOCAL_REGISTRY:-}'" | sudo tee /etc/sysconfig/docker
    fi
    sudo systemctl start docker

    sudo mkdir -p /etc/puppet/modules/
    sudo ln -f -s /usr/share/openstack-puppet/modules/* /etc/puppet/modules/

    # Hostname check, add to /etc/hosts if needed
    if ! grep -E "^::1\s*$(hostname -f)" /etc/hosts; then
        sudo sed -i "s/::1\s*\(.*\)/::1\t$(hostname -f) $(hostname -s) \1/" /etc/hosts
    fi

    # Custom settings can go here
    cat > $HOME/custom.yaml <<-EOF_CAT
resource_registry:
  OS::TripleO::Undercloud::Net::SoftwareConfig: $HOME/tripleo-heat-templates/net-config-noop.yaml

parameter_defaults:
  UndercloudNameserver: 8.8.8.8
  NeutronServicePlugins: ""
EOF_CAT

    LOCAL_IP=${LOCAL_IP:-`/usr/sbin/ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n'`}

    cp -a /usr/share/openstack-tripleo-heat-templates ~/tripleo-heat-templates

    sudo openstack undercloud deploy --templates=$HOME/tripleo-heat-templates \
        --local-ip=$LOCAL_IP \
        --heat-native \
        -e $HOME/tripleo-heat-templates/environments/services-docker/ironic.yaml \
        -e $HOME/tripleo-heat-templates/environments/services-docker/mistral.yaml \
        -e $HOME/tripleo-heat-templates/environments/services-docker/zaqar.yaml \
        -e $HOME/tripleo-heat-templates/environments/docker.yaml \
        -e $HOME/tripleo-heat-templates/environments/mongodb-nojournal.yaml \
        -e $HOME/custom.yaml

    # the new installer requires root privs to avoid sudo'ing everything,
    # so we copy out the key manually to /home/stack for backwards compat
    # if it exists
    sudo cp /root/stackrc $HOME/stackrc
    sudo chown $UID $HOME/stackrc

    log "Undercloud install containers - DONE."

}

function overcloud_images {

    log "Overcloud images"

    # This hack is no longer needed in ocata.
    if [[ "${STABLE_RELEASE}" =~ ^(mitaka|newton)$ ]]; then
        # Ensure yum-plugin-priorities is installed

        # get the right path for diskimage-builder version
        COMMON_ELEMENTS_PATH=$(python -c '
try:
    import diskimage_builder.paths
    diskimage_builder.paths.show_path("elements")
except:
    print("/usr/share/diskimage-builder/elements")
        ')
        echo -e '#!/bin/bash\nyum install -y yum-plugin-priorities' | sudo tee ${COMMON_ELEMENTS_PATH}/yum/pre-install.d/99-tmphacks
        sudo chmod +x ${COMMON_ELEMENTS_PATH}/yum/pre-install.d/99-tmphacks
    fi

    # To install the undercloud instack-undercloud is run as root,
    # as a result all of the git repositories get cached to
    # ~root/.cache/image-create/source-repositories, lets not clone them again
    if [ -d ~root/.cache/image-create/source-repositories ] && \
       [ ! -d ~/.cache/image-create/source-repositories ] ; then
        sudo cp -r ~root/.cache/image-create/source-repositories ~/.cache/image-create/source-repositories
        sudo chown -R $(id -u) ~/.cache/image-create/source-repositories
    fi

    export DIB_YUM_REPO_CONF=$OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF

    log "Overcloud images saved in $OVERCLOUD_IMAGES_PATH"
    pushd $OVERCLOUD_IMAGES_PATH
    log "OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=$OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF"
    if [[ "${STABLE_RELEASE}" =~ ^(mitaka|newton)$ ]] ; then
        OVERCLOUD_IMAGES_ARGS="$OVERCLOUD_IMAGES_LEGACY_ARGS"
    fi
    DIB_YUM_REPO_CONF=$OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF \
        openstack overcloud image build $OVERCLOUD_IMAGES_ARGS 2>&1 | \
        tee -a overcloud-image-build.log

    stackrc_check
    openstack overcloud image upload --update-existing
    popd

    log "Overcloud images - DONE."

}


function register_nodes {

    log "Register nodes"

    if [ ! -f $INSTACKENV_JSON_PATH ]; then
        echo Could not find instackenv.json at $INSTACKENV_JSON_PATH
        echo Specify the path to instackenv.json with '$INSTACKENV_JSON_PATH'
        exit 1
    fi

    stackrc_check
    if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
        openstack baremetal import --json $INSTACKENV_JSON_PATH
        # This step is a part of the import command from Newton on
        openstack baremetal configure boot
    else
        if [ "$INTROSPECT_NODES" = 1 ]; then
            # Keep the nodes in manageable state so that they may be
            # introspected later.
            openstack overcloud node import $INSTACKENV_JSON_PATH
        else
            openstack overcloud node import $INSTACKENV_JSON_PATH --provide
        fi
    fi

    ironic node-list

    log "Register nodes - DONE."

}

function introspect_nodes {

    log "Introspect nodes"

    stackrc_check

    if [[ "${STABLE_RELEASE}" = "mitaka" ]] ; then
        openstack baremetal introspection bulk start
    else
        # Note: Unlike the legacy bulk command, overcloud node
        # introspect will only run on nodes in the 'manageable'
        # provisioning state.
        openstack overcloud node introspect --all-manageable
        openstack overcloud node provide --all-manageable
    fi

    log "Introspect nodes - DONE."

}

function overcloud_deploy {

    log "Overcloud deploy"

    # Force use of --templates
    if [[ ! $OVERCLOUD_DEPLOY_ARGS =~ --templates ]]; then
        OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS --templates"
    fi
    stackrc_check

    OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS $OVERCLOUD_VALIDATE_ARGS"
    # Set dns server for the overcloud nodes
    subnet_id=$(openstack network list -f value -c Name -c Subnets | grep ctlplane | cut -d " " -f 2)
    neutron subnet-update $subnet_id --dns-nameserver $(cat /etc/resolv.conf | grep nameserver | awk '{ print $2 }' | sed ':a;N;$!ba;s/\n/ --dns-nameserver /g')

    if [[ $USE_CONTAINERS == 1 ]]; then
        if ! glance image-list | grep  -q atomic-image; then
            wget --progress=dot:mega $ATOMIC_URL
            glance image-create --name atomic-image --file `basename $ATOMIC_URL` --disk-format qcow2 --container-format bare
        fi
        #TODO: When container job is changed to network-isolation remove this
        neutron subnet-update $(neutron net-list | grep ctlplane | cut  -d ' ' -f 6) --dns-nameserver 8.8.8.8
        OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS $CONTAINER_ARGS"
    fi


    log "unsetting any http proxy"
    unset http_proxy
    log "Overcloud create started."
    exitval=0
    log "Deploy command arguments: $OVERCLOUD_DEPLOY_ARGS"
    openstack overcloud deploy $OVERCLOUD_DEPLOY_ARGS || exitval=1
    if [ $exitval -eq 1 ];
    then
        log "Overcloud create - FAILED!"
        exit 1
    fi
    log "Overcloud create - DONE."
}

function undercloud_upgrade {

    log "Undercloud upgrade"

    # Setup repositories
    repo_setup

    # NOTE(emilien):
    # If we don't stop OpenStack services before the upgrade, Puppet run will hang forever.
    # This thing might be an ugly workaround but we need to to upgrade the undercloud.
    # The question is: where to do it? in tripleoclient? or instack-undercloud?
    sudo systemctl stop openstack-*
    sudo systemctl stop neutron-*
    sudo systemctl stop openvswitch
    sudo systemctl stop httpd
    # tripleo cli needs to be updated first
    sudo yum -y update python-tripleoclient

    # Upgrade the undercloud
    openstack undercloud upgrade
    log "Undercloud upgrade - Done."
}

function overcloud_update {
    # Force use of --templates
    if [[ ! $OVERCLOUD_UPDATE_ARGS =~ --templates ]]; then
        OVERCLOUD_UPDATE_ARGS="$OVERCLOUD_UPDATE_ARGS --templates"
    fi
    stackrc_check
    if openstack stack show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "(CREATE|UPDATE)_COMPLETE"; then
        FILE_PREFIX=$(date "+overcloud-update-resources-%s")
        BEFORE_FILE="/tmp/${FILE_PREFIX}-before.txt"
        AFTER_FILE="/tmp/${FILE_PREFIX}-after.txt"
        # This is an update, so if enabled, compare the before/after resource lists
        if [ ! -z "$OVERCLOUD_UPDATE_CHECK" ]; then
            openstack stack resource list -n5 overcloud | awk '{print $2, $4, $6}' | sort > $BEFORE_FILE
        fi

        log "Overcloud update started."
        exitval=0
        openstack overcloud deploy $OVERCLOUD_UPDATE_ARGS || exitval=1
        if [ $exitval -eq 1 ];
        then
            log "Overcloud update - FAILED!"
            exit 1
        fi
        log "Overcloud update - DONE."

        if [ ! -z "$OVERCLOUD_UPDATE_CHECK" ]; then
            openstack stack resource list -n5 overcloud | awk '{print $2, $4, $6}' | sort > $AFTER_FILE
            diff_rsrc=$(diff $BEFORE_FILE $AFTER_FILE)
            if [ ! -z "$diff_rsrc" ]; then
                log "Overcloud update - Completed but unexpected resource differences: $diff_rsrc"
                exit 1
            fi
        fi
        log "Overcloud update - DONE."
        if [[ $OVERCLOUD_UPDATE_RM_FILES == 1 ]]; then
            rm -f $BEFORE_FILE $AFTER_FILE
        fi
    else
        log "Overcloud FAILED - No stack $OVERCLOUD_NAME."
        exit 1
    fi
}

function overcloud_upgrade {
    stackrc_check
    if heat stack-show "$OVERCLOUD_NAME" ; then
        log "Create overcloud repo template file"
        /bin/bash -c "cat <<EOF>$HOME/init-repo.yaml

parameter_defaults:
  UpgradeInitCommand: |
    set -e
    # For some reason '$HOME' is not defined when the Heat agent executes this
    # script and tripleo.sh expects it. Just reuse the same value from the
    # current undercloud user.
    yum clean all
    HOME=$HOME $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup
    yum clean all
    yum install -y python-heat-agent-*

    # TODO: (slagle)
    # remove the --noscripts install of openstack-tripleo-image-elements
    # once https://review.rdoproject.org/r/4225 merges
    pushd /tmp
    yumdownloader openstack-tripleo-image-elements
    rpm -Uvh --noscripts --force ./openstack-tripleo-image-elements*
    rm -f openstack-tripleo-image-elements*
    popd

    # FIXME: matbu
    # Remove those packages is temporary workaround since the fix in
    # https://bugs.launchpad.net/tripleo/+bug/1649284
    # will be release and landed in the packages
    yum remove -y python-UcsSdk openstack-neutron-bigswitch-agent python-networking-bigswitch openstack-neutron-bigswitch-lldp python-networking-odl
    # Ref https://review.openstack.org/#/c/392615 disable the old hiera hook
    # FIXME - this should probably be handled via packaging?
    rm -f /usr/libexec/os-apply-config/templates/etc/puppet/hiera.yaml
    rm -f /usr/libexec/os-refresh-config/configure.d/40-hiera-datafiles
    rm -f /etc/puppet/hieradata/*.yaml
EOF"
        log "Overcloud upgrade started."
        log "Upgrade command arguments: $OVERCLOUD_UPGRADE_ARGS"
        log "Execute major upgrade."
        openstack overcloud deploy $OVERCLOUD_UPGRADE_ARGS
        log "Major upgrade - DONE."

        if heat stack-show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "UPDATE_COMPLETE"; then
            log "Major Upgrade - DONE."
        else
            log "Major Upgrade FAILED."
            exit 1
        fi
    else
        log "Overcloud upgrade FAILED - No stack $OVERCLOUD_NAME."
        exit 1
    fi
}

function overcloud_upgrade_converge {
    stackrc_check
    if heat stack-show "$OVERCLOUD_NAME" ; then
        log "Overcloud upgrade converge started."
        log "Upgrade command arguments: $OVERCLOUD_UPGRADE_CONVERGE_ARGS"
        log "Execute major upgrade converge."
        openstack overcloud deploy $OVERCLOUD_UPGRADE_CONVERGE_ARGS
        log "Major upgrade converge - DONE."

        if heat stack-show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "UPDATE_COMPLETE"; then
            log "Major Upgrade converge - DONE."
        else
            log "Major Upgrade converge FAILED."
            exit 1
        fi
    else
        log "Overcloud upgrade converge FAILED - No stack $OVERCLOUD_NAME."
        exit 1
    fi
}

function overcloud_delete {

    log "Overcloud delete"

    stackrc_check

    OVERCLOUD_ID=$(openstack stack list | grep "$OVERCLOUD_NAME" | awk '{print $2}')
    wait_command="openstack stack show $OVERCLOUD_ID"
    openstack stack delete --yes "$OVERCLOUD_NAME"
    if $($TRIPLEO_ROOT/tripleo-ci/scripts/wait_for -w $OVERCLOUD_DELETE_TIMEOUT -d 10 -s "DELETE_COMPLETE" -- "$wait_command"); then
       log "Overcloud $OVERCLOUD_ID DELETE_COMPLETE"
    else
       log "Overcloud $OVERCLOUD_ID delete failed or timed out:"
       openstack stack show $OVERCLOUD_ID
       exit 1
    fi
    if [[ "${STABLE_RELEASE}" != "mitaka" ]] ; then
        openstack overcloud plan delete "$OVERCLOUD_NAME" && exitval=0 || exitval=1
        if [ ${exitval} -eq 0 ]; then
            log "Overcloud $OVERCLOUD_ID plan delete SUCCESS"
        else
            log "Overcloud $OVERCLOUD_ID plan delete FAILED"
            exit 1
        fi
    fi
}

function run_cmd {
  if ! $@; then
      echo "Command: $@ FAILED" >&2
      exit 1
  else
      echo "Command: $@ OK"
  fi
}

function overcloud_sanitytest_create {
    ENABLED_SERVICES=$@
    for service in $ENABLED_SERVICES; do
        case $service in
            "keystone" )
                run_cmd openstack user create ${SANITYTEST_CONTENT_NAME}
                run_cmd openstack user list
                ;;
            "glance_api" )
                run_cmd openstack image create ${SANITYTEST_CONTENT_NAME}
                run_cmd openstack image list
                ;;
            "neutron_api" )
                run_cmd openstack network create ${SANITYTEST_CONTENT_NAME}
                run_cmd openstack network list
                ;;
            "cinder_api" )
                run_cmd openstack volume create ${SANITYTEST_CONTENT_NAME} --size 1
                run_cmd openstack volume list
                ;;
            "heat_api" )
                echo "heat_template_version: newton" > /tmp/${SANITYTEST_CONTENT_NAME}.yaml
                openstack stack create ${SANITYTEST_CONTENT_NAME} --template /tmp/${SANITYTEST_CONTENT_NAME}.yaml
                openstack stack list
                ;;
            "swift_proxy" )
                openstack container create ${SANITYTEST_CONTENT_NAME}
                openstack container list
                ;;
            "sahara_api" )
                # glance_api must also be enabled
                run_cmd openstack image create sahara_${SANITYTEST_CONTENT_NAME}
                run_cmd openstack dataprocessing image register sahara_${SANITYTEST_CONTENT_NAME} --username centos
                run_cmd openstack dataprocessing image list
                ;;
        esac
    done
}

function overcloud_sanitytest_check {
    ENABLED_SERVICES=$@
    for service in $ENABLED_SERVICES; do
        case $service in
            "keystone" )
                run_cmd openstack user show ${SANITYTEST_CONTENT_NAME}
                ;;
            "glance_api" )
                run_cmd openstack image show ${SANITYTEST_CONTENT_NAME}
                ;;
            "neutron_api" )
                run_cmd openstack network show ${SANITYTEST_CONTENT_NAME}
                ;;
            "cinder_api" )
                run_cmd openstack volume show ${SANITYTEST_CONTENT_NAME}
                ;;
            "heat_api" )
                run_cmd openstack stack show ${SANITYTEST_CONTENT_NAME}
                # FIXME(shardy): It'd be good to add pre/post upgrade checks
                # on the actual version, but this is still good for debugging
                run_cmd openstack orchestration template version list
                ;;
            "swift_proxy" )
                run_cmd openstack container show ${SANITYTEST_CONTENT_NAME}
                ;;
            "sahara_api" )
                run_cmd openstack dataprocessing image show sahara_${SANITYTEST_CONTENT_NAME}
                ;;
        esac
    done
}

function overcloud_sanitytest_cleanup {
    ENABLED_SERVICES=$@
    for service in $ENABLED_SERVICES; do
        case $service in
            "keystone" )
                echo "Sanity test keystone"
                run_cmd openstack user delete ${SANITYTEST_CONTENT_NAME}
                ;;
            "glance_api" )
                run_cmd openstack image delete ${SANITYTEST_CONTENT_NAME}
                ;;
            "neutron_api" )
                run_cmd openstack network delete ${SANITYTEST_CONTENT_NAME}
                ;;
            "cinder_api" )
                run_cmd openstack volume delete ${SANITYTEST_CONTENT_NAME}
                ;;
            "heat_api" )
                run_cmd openstack stack delete --yes ${SANITYTEST_CONTENT_NAME}
                ;;
            "swift_proxy" )
                run_cmd openstack container delete ${SANITYTEST_CONTENT_NAME}
                ;;
            "sahara_api" )
                run_cmd openstack dataprocessing image unregister sahara_${SANITYTEST_CONTENT_NAME}
                run_cmd openstack image delete sahara_${SANITYTEST_CONTENT_NAME}
                ;;
        esac
    done
}

function overcloud_sanitytest {

    log "Overcloud sanitytest"
    exitval=0
    stackrc_check

    if heat stack-show "$OVERCLOUD_NAME" | grep "stack_status " | egrep -q "(CREATE|UPDATE)_COMPLETE"; then

        ENABLED_SERVICES=$(openstack stack output show overcloud EnabledServices -f json | \
                           jq -r ".output_value" | jq '.Controller | .[]' | tr "\n" " " | sed "s/\"//g")
        echo "Sanity Test, ENABLED_SERVICES=$ENABLED_SERVICES"

        overcloudrc_check

        if [ "$OVERCLOUD_SANITYTEST_SKIP_CREATE" != 1 ]; then
            overcloud_sanitytest_create $ENABLED_SERVICES
        fi

        overcloud_sanitytest_check $ENABLED_SERVICES

        if [ "$OVERCLOUD_SANITYTEST_SKIP_CLEANUP" != 1 ]; then
            overcloud_sanitytest_cleanup $ENABLED_SERVICES
        fi

        if [ $exitval -eq 0 ]; then
            log "Overcloud sanitytest SUCCEEDED"
        else
            log "Overcloud sanitytest FAILED"
        fi
        exit $exitval
    else
        log "Overcloud sanitytest FAILED - No stack $OVERCLOUD_NAME."
        exit 1
    fi
}

function cleanup_pingtest {

    log "Overcloud pingtest; cleaning environment"
    overcloudrc_check
    wait_command="openstack stack show tenant-stack"
    openstack stack delete --yes tenant-stack || true
    if $TRIPLEO_ROOT/tripleo-ci/scripts/wait_for -w 300 -d 10 -s "Stack not found" -- "$wait_command"; then
        log "Overcloud pingtest - deleted the tenant-stack heat stack"
    else
        log "Overcloud pingtest - time out waiting to delete tenant heat stack, please check manually"
    fi
    log "Overcloud pingtest - cleaning all 'pingtest_*' images"
    openstack image list | grep pingtest | awk '{print $2}' | xargs -r -n1 openstack image delete || true
    log "Overcloud pingtest - cleaning demo network 'nova'"
    neutron net-delete nova || true
}

function overcloud_pingtest {

    log "Overcloud pingtest"
    exitval=0

    stackrc_check
    SUBNET_ID=$(openstack network list -c Subnets -c Name -f value | grep ctlplane | awk {'print $2'})
    CTLPLANE_CIDR=$(neutron subnet-show $SUBNET_ID -F cidr -f value)
    CTLPLANE_NET=$(echo $CTLPLANE_CIDR | awk -F "." {'print $1"."$2"."$3'})

    overcloudrc_check

    cleanup_pingtest

    # NOTE(bnemec): We have to use the split cirros image here to avoid
    # https://bugs.launchpad.net/cirros/+bug/1312199  With the separate
    # kernel and ramdisk Nova will add the necessary kernel param for us.
    IMAGE_PATH=$OVERCLOUD_IMAGES_PATH/cirros.img
    INITRAMFS_PATH=$OVERCLOUD_IMAGES_PATH/cirros.initramfs
    KERNEL_PATH=$OVERCLOUD_IMAGES_PATH/cirros.kernel
    if [ ! -e $IMAGE_PATH -o ! -e $INITRAMFS_PATH -o ! -e $KERNEL_PATH ]; then
        log "Overcloud pingtest, trying to download Cirros image"
        curl -L -o $IMAGE_PATH http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
        curl -L -o $INITRAMFS_PATH http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-initramfs
        curl -L -o $KERNEL_PATH http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-kernel
    fi
    log "Overcloud pingtest, uploading demo tenant image to glance"
    ramdisk_id=$(openstack image create pingtest_initramfs --public --container-format ari --disk-format ari --file $INITRAMFS_PATH | grep ' id ' | awk '{print $4}')
    kernel_id=$(openstack image create pingtest_kernel --public --container-format aki --disk-format aki --file $KERNEL_PATH | grep ' id ' | awk '{print $4}')
    openstack image create pingtest_image --public --container-format ami --disk-format ami --property kernel_id=$kernel_id --property ramdisk_id=$ramdisk_id --file $IMAGE_PATH

    log "Overcloud pingtest, creating external network"
    neutron net-create nova --shared --router:external=True --provider:network_type flat \
  --provider:physical_network datacentre

    FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-$CTLPLANE_CIDR}
    FLOATING_IP_START=${FLOATING_IP_START:-"${CTLPLANE_NET}.50"}
    FLOATING_IP_END=${FLOATING_IP_END:-"${CTLPLANE_NET}.64"}
    EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"${CTLPLANE_NET}.1"}
    TENANT_STACK_DEPLOY_ARGS=${TENANT_STACK_DEPLOY_ARGS:-""}
    neutron subnet-create --name ext-subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY nova $FLOATING_IP_CIDR
    # pingtest environment for scenarios jobs is in TripleO Heat Templates.
    if [ -e /usr/share/openstack-tripleo-heat-templates/ci/pingtests/$MULTINODE_ENV_NAME.yaml ]; then
        TENANT_PINGTEST_TEMPLATE=/usr/share/openstack-tripleo-heat-templates/ci/pingtests/$MULTINODE_ENV_NAME.yaml
    else
        if [ -e /usr/share/openstack-tripleo-heat-templates/ci/pingtests/tenantvm_floatingip.yaml ]; then
            TENANT_PINGTEST_TEMPLATE=/usr/share/openstack-tripleo-heat-templates/ci/pingtests/tenantvm_floatingip.yaml
        else
            # If the template is not found, we will get the template from the tripleo-ci location for backwards compatibility.
            TENANT_PINGTEST_TEMPLATE=$TRIPLEO_ROOT/tripleo-ci/templates/tenantvm_floatingip.yaml
        fi
    fi
    log "Overcloud pingtest, creating tenant-stack heat stack:"
    openstack stack create -f yaml -t $TENANT_PINGTEST_TEMPLATE $TENANT_STACK_DEPLOY_ARGS tenant-stack || exitval=1

    WAIT_FOR_COMMAND="openstack stack list | grep tenant-stack"

    # No point in waiting if the previous command failed.
    if [ ${exitval} -eq 0 ]; then
        # TODO(beagles): While the '-f' flag will short-circuit fail us, we'll
        # likely have to wait for service operations to timeout before the
        # stack gets marked as failed anyways. A CI oriented configuration for
        # some key services *might* work for 'fail faster', but where things
        # can be so slow already it might just cause more pain.
        #
        if $TRIPLEO_ROOT/tripleo-ci/scripts/wait_for -w 300 -d 10 -s "CREATE_COMPLETE" -f "CREATE_FAILED" -- $WAIT_FOR_COMMAND; then
            log "Overcloud pingtest, heat stack CREATE_COMPLETE";

            vm1_ip=`openstack stack output show tenant-stack server1_public_ip | grep value | awk '{print $4}'`

            log "Overcloud pingtest, trying to ping the floating IPs $vm1_ip"

            if $TRIPLEO_ROOT/tripleo-ci/scripts/wait_for -w 360 -d 10 -s "bytes from $vm1_ip" -- "ping -c 1 $vm1_ip" ; then
                ping -c 1 $vm1_ip
                log "Overcloud pingtest, SUCCESS"
            else
                ping -c 1 $vm1_ip || :
                nova show Server1 || :
                nova service-list || :
                neutron agent-list || :
                nova console-log Server1 || :
                log "Overcloud pingtest, FAIL"
                exitval=1
            fi
        else
            nova service-list || :
            neutron agent-list || :
            openstack stack show tenant-stack || :
            openstack stack event list -f table tenant-stack || :
            openstack stack resource list -n5 tenant-stack || :
            openstack stack failures list tenant-stack || :
            log "Overcloud pingtest, failed to create heat stack, trying cleanup"
            exitval=1
        fi
    else
        log "Overcloud pingtest, stack create command failed immediately"
    fi
    if [ "$SKIP_PINGTEST_CLEANUP" != 1 ]; then
        cleanup_pingtest
    else
        log "Overcloud pingtest, the resources created by the pingtest will remain until a new pingtest is executed."
    fi
    if [ $exitval -eq 0 ]; then
        log "Overcloud pingtest SUCCEEDED"
    else
        log "Overcloud pingtest FAILED"
    fi
    exit $exitval
}

function clean_tempest {
    neutron net-delete nova || echo "Cleaning tempest: no networks were created"
}

function tempest_run {

    log "Running tempest"

    stackrc_check
    CTLPLANE_CIDR=$(neutron net-list -c subnets -c name -f value | grep ctlplane | awk {'print $2'})
    CTLPLANE_NET=$(echo $CTLPLANE_CIDR | awk -F "." {'print $1"."$2"."$3'})

    overcloudrc_check
    clean_tempest
    root_dir=$(realpath $(dirname ${BASH_SOURCE[0]:-$0}))
    [[ ! -e $HOME/tempest ]] && git clone https://github.com/openstack/tempest $HOME/tempest
    pushd $HOME/tempest
    git checkout $TEMPEST_PINNED
    FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-$CTLPLANE_CIDR}
    FLOATING_IP_START=${FLOATING_IP_START:-"${CTLPLANE_NET}.50"}
    FLOATING_IP_END=${FLOATING_IP_END:-"${CTLPLANE_NET}.64"}
    export EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"${CTLPLANE_NET}.1"}
    neutron net-create nova --shared --router:external=True --provider:network_type flat --provider:physical_network datacentre;
    neutron subnet-create --name ext-subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY nova $FLOATING_IP_CIDR;
    sudo yum install -y libffi-devel openssl-devel python-virtualenv
    virtualenv --no-site-packages .venv
    $HOME/tempest/tools/with_venv.sh pip install -U pip setuptools
    $HOME/tempest/tools/with_venv.sh pip install junitxml httplib2 -r test-requirements.txt -r requirements.txt
    cp $root_dir/config_tempest.py $HOME/tempest/tools/
    cp $root_dir/api_discovery.py $HOME/tempest/tempest/common/
    cp $root_dir/default-overrides.conf $HOME/tempest/etc/
    sudo mkdir -p /var/log/tempest/ ||:
    sudo mkdir -p /etc/tempest/ ||:
    sudo chown $USER:$USER -R /var/log/tempest/
    $HOME/tempest/tools/with_venv.sh python $HOME/tempest/tools/config_tempest.py \
        --out etc/tempest.conf \
        --debug \
        --create \
        --deployer-input ~/tempest-deployer-input.conf \
        identity.uri $OS_AUTH_URL \
        compute.allow_tenant_isolation true \
        identity.admin_password $OS_PASSWORD \
        compute.build_timeout 500 \
        compute.image_ssh_user cirros \
        orchestration.stack_owner_role _member_ \
        compute.ssh_user cirros \
        network.build_timeout 500 \
        volume.build_timeout 500 \
        DEFAULT.log_file "/var/log/tempest/tempest.log" \
        scenario.ssh_user cirros $TEMPEST_ADD_CONFIG
    sudo cp $HOME/tempest/etc/tempest.conf /etc/tempest/tempest.conf
    [[ ! -e $HOME/tempest/.testrepository ]] && $HOME/tempest/tools/with_venv.sh testr init
    $HOME/tempest/tools/with_venv.sh testr run \
        $TEMPEST_ARGS \
        $TEMPEST_REGEX | \
        tee >( $HOME/tempest/tools/with_venv.sh subunit2junitxml --output-to=/var/log/tempest/tempest.xml ) | \
        $HOME/tempest/tools/with_venv.sh subunit-trace --no-failure-debug -f 2>&1 | \
        tee /var/log/tempest/tempest_console.log && exitval=0 || exitval=$?
    $HOME/tempest/tools/with_venv.sh subunit2html $HOME/tempest/.testrepository/$(ls -t $HOME/tempest/.testrepository/ | grep -e "[0-9]" | head -1) /var/log/tempest/tempest.html
    exit ${exitval}
}

function clone {

    local repo=$1

    log "$0 requires $repo to be cloned at \$TRIPLEO_ROOT ($TRIPLEO_ROOT)"

    mkdir -p $TRIPLEO_ROOT
    if [ ! -d $TRIPLEO_ROOT/$(basename $repo) ]; then
        echo "$repo not found at $TRIPLEO_ROOT/$repo, git cloning."
        pushd $TRIPLEO_ROOT
        git clone https://git.openstack.org/$repo
        popd
    else
        echo "$repo found at $TRIPLEO_ROOT/$repo, nothing to do."
    fi

}

function multinode_setup {

    log "Multinode Setup"

    clone openstack-dev/devstack
    clone openstack-infra/devstack-gate

    # $BASE is expected by devstack/functions-common
    # which is sourced by devstack-gate/functions.sh
    # It should be the parent directory of the "new" directory where
    # zuul-cloner has checked out the repositories
    export BASE
    export TRIPLEO_ROOT

    log "Sourcing devstack-gate/functions.sh"
    set +u
    source $TRIPLEO_ROOT/devstack-gate/functions.sh
    set -u

    PUB_BRIDGE_NAME=${PUB_BRIDGE_NAME:-"br-ex"}

    local primary_node
    primary_node=$(cat /etc/nodepool/primary_node_private)
    local sub_nodes
    sub_nodes=$(cat /etc/nodepool/sub_nodes_private)

    for ip in $sub_nodes; do
        # Do repo setup so openvswitch package is available on subnodes. Will
        # be installed by ovs_vxlan_bridge function below.
        log "Running --repo-setup on $ip"
        ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
            TRIPLEO_ROOT=$TRIPLEO_ROOT \
            $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup
    done

    # Create OVS vxlan bridges
    # If br-ctlplane already exists on this node, we need to bring it down
    # first, then bring it back up after calling ovs_vxlan_bridge. This ensures
    # that the route added to br-ex by ovs_vxlan_bridge will be preferred over
    # the br-ctlplane route. If it's not preferred, multinode connectivity
    # across the vxlan bridge will not work.
    if [ -f /etc/sysconfig/network-scripts/ifcfg-br-ctlplane ]; then
        sudo ifdown br-ctlplane
    fi
    set +u
    log "Running ovs_vxlan_bridge"
    ovs_vxlan_bridge $PUB_BRIDGE_NAME $primary_node "True" 2 192.168.24 24 $sub_nodes
    set -u

    log "Setting $PUB_BRIDGE_NAME up on $primary_node"
    sudo ip link set dev $PUB_BRIDGE_NAME up
    sudo ip link set dev $PUB_BRIDGE_NAME mtu $MTU

    if [ -f /etc/sysconfig/network-scripts/ifcfg-br-ctlplane ]; then
        sudo ifup br-ctlplane
    fi
    # Restart neutron-openvswitch-agent if it's enabled, since it may have
    # terminated when br-ctlplane was down
    if [ "$(sudo systemctl is-enabled neutron-openvswitch-agent)" = 'enabled' ]; then
        sudo systemctl reset-failed neutron-openvswitch-agent
        sudo systemctl restart neutron-openvswitch-agent
    fi

    local ping_command="ping -c 6 -W 3 192.168.24.2"

    for ip in $sub_nodes; do
        log "Setting $PUB_BRIDGE_NAME up on $ip"
        ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
            sudo ip link set dev $PUB_BRIDGE_NAME up
        ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
            sudo ip link set dev $PUB_BRIDGE_NAME mtu $MTU
        log "Pinging from $ip"
        if ! remote_command $ip $ping_command; then
            log "Pinging from $ip failed, restarting openvswitch"
            remote_command $ip sudo systemctl restart openvswitch
            if ! remote_command $ip $ping_command; then
                log "Pinging from $ip still failed after restarting openvswitch"
                exit 1
            fi
        fi
    done

    log "Multinode Setup - DONE".
}

function ui_sanity_check {
    if [ -f "/etc/httpd/conf.d/25-tripleo-ui.conf" ]; then
        if [ "$UNDERCLOUD_SSL" = 1 ]; then
            UI_URL=https://192.168.24.2
        else
            UI_URL=http://192.168.24.1:3000
        fi
        if ! curl $UI_URL 2>/dev/null | grep -q 'TripleO'; then
            log "ERROR: TripleO UI front page is not loading."
            exit 1
        fi
    fi
}

function undercloud_sanity_check {
    set -x
    stackrc_check
    openstack user list
    openstack catalog list
    nova service-list
    glance image-list
    neutron subnet-list
    neutron net-list
    neutron agent-list
    ironic node-list
    openstack stack list
    # FIXME undercloud with containers does not yet have the UI
    if [ "$UNDERCLOUD_CONTAINERS" != 1 ]; then
      ui_sanity_check
    fi
    set +x
}

function bootstrap_subnodes {
    log "Bootstrap subnodes"

    local sub_nodes
    sub_nodes=$(cat /etc/nodepool/sub_nodes_private)

    bootstrap_subnodes_repos

    local bootstrap_script
    if [ "$BOOTSTRAP_SUBNODES_MINIMAL" = "1" ]; then
        bootstrap_script=bootstrap-overcloud-full-minimal.sh
    else
        bootstrap_script=bootstrap-overcloud-full.sh
    fi

    for ip in $sub_nodes; do
        log "Bootstrapping $ip"
        # Run overcloud full bootstrap script
        log "Running bootstrap-overcloud-full.sh on $ip"
        ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
            TRIPLEO_ROOT=$TRIPLEO_ROOT \
            $TRIPLEO_ROOT/tripleo-ci/scripts/$bootstrap_script
    done

    log "Bootstrap subnodes - DONE".
}


function setup_nodepool_files {
    log "Setup nodepool files"

    clone openstack-dev/devstack
    clone openstack-infra/devstack-gate
    clone openstack-infra/tripleo-ci

    if [ ! -d $BASE/new ]; then
        ln -s $TRIPLEO_ROOT $BASE/new
    fi

    sudo mkdir -p /etc/nodepool
    sudo chown -R $(whoami): /etc/nodepool

    if [ ! -f /etc/nodepool/id_rsa ]; then
        ssh-keygen -N "" -t rsa -f /etc/nodepool/id_rsa
    fi

    if [ -z $PRIMARY_NODE_IP ]; then
        echo '$PRIMARY_NODE_IP must be defined. Exiting.'
        exit 1
    fi

    echo $PRIMARY_NODE_IP > /etc/nodepool/primary_node
    echo $PRIMARY_NODE_IP > /etc/nodepool/primary_node_private

    echo -n > /etc/nodepool/sub_nodes
    echo -n > /etc/nodepool/sub_nodes_private
    for sub_node_ip in $SUB_NODE_IPS; do
        echo $sub_node_ip >> /etc/nodepool/node
        echo $sub_node_ip >> /etc/nodepool/node_private
        echo $sub_node_ip >> /etc/nodepool/sub_nodes
        echo $sub_node_ip >> /etc/nodepool/sub_nodes_private

        ssh $SSH_OPTIONS -tt $sub_node_ip sudo mkdir -p $TRIPLEO_ROOT
        ssh $SSH_OPTIONS -tt $sub_node_ip sudo chown -R $(whoami): $TRIPLEO_ROOT
        rsync -e "ssh $SSH_OPTIONS" -avhP $TRIPLEO_ROOT $sub_node_ip:$TRIPLEO_ROOT/..
        rsync -e "ssh $SSH_OPTIONS" -avhP /etc/nodepool $sub_node_ip:
        ssh $SSH_OPTIONS -tt $sub_node_ip sudo cp -r nodepool /etc
        ssh $SSH_OPTIONS $sub_node_ip \
            "/bin/bash -c 'cat /etc/nodepool/id_rsa.pub >> ~/.ssh/authorized_keys'"
    done

    echo $PRIMARY_NODE_IP > /etc/nodepool/node
    echo $PRIMARY_NODE_IP > /etc/nodepool/node_private

    echo "NODEPOOL_REGION=$NODEPOOL_REGION" > /etc/nodepool/provider
    echo "NODEPOOL_CLOUD=$NODEPOOL_CLOUD" >> /etc/nodepool/provider

    log "Setup nodepool files - DONE"
}


function bootstrap_subnodes_repos {
    log "Bootstrap subnodes repos"

    local sub_nodes
    sub_nodes=$(cat /etc/nodepool/sub_nodes_private)

    for ip in $sub_nodes; do
        log "Bootstrapping $ip"
        log "Running --repo-setup on $ip"
        # Do repo setup
        # if UPGRADE_RELEASE is set, then we are making an upgrade, so
        # we need to set the stable_release.
        if [ ! -z $UPGRADE_RELEASE ]; then
            log "Stable release $UPGRADE_RELEASE"
            ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
                "TRIPLEO_ROOT=$TRIPLEO_ROOT; \
                unset STABLE_RELEASE; \
                export STABLE_RELEASE=$UPGRADE_RELEASE; \
                $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup"
        else
            ssh $SSH_OPTIONS -t -i /etc/nodepool/id_rsa $ip \
                TRIPLEO_ROOT=$TRIPLEO_ROOT \
                $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --repo-setup
        fi
    done

    log "Bootstrap subnodes repos - DONE".
}


if [ "$REPO_SETUP" = 1 ]; then
    repo_setup
fi

if [ "$DELOREAN_SETUP" = 1 ]; then
    delorean_setup
fi

if [ "$DELOREAN_BUILD" = 1 ]; then
    export DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-$@}"
    if [ -z "$DELOREAN_BUILD_REFS" ]; then
        echo "Usage: $0 --delorean-build openstack/heat openstack/nova"
        exit 1
    fi
    delorean_build
fi

if [ "$UNDERCLOUD" = 1 ]; then
    if [ "$UNDERCLOUD_CONTAINERS" = 1 ]; then
        undercloud_containers
    else
        undercloud
    fi
    if [ "$UNDERCLOUD_SANITY_CHECK" = 1 ]; then
        undercloud_sanity_check
    fi
fi

if [ "$OVERCLOUD_IMAGES" = 1 ]; then
    overcloud_images
fi

if [ "$REGISTER_NODES" = 1 ]; then
    register_nodes
fi

if [ "$INTROSPECT_NODES" = 1 ]; then
    introspect_nodes
fi

if [ "$OVERCLOUD_DEPLOY" = 1 ]; then
    overcloud_deploy
fi

if [ "$OVERCLOUD_UPDATE" = 1 ]; then
    overcloud_update
fi

if [ "$OVERCLOUD_UPGRADE" = 1 ]; then
    overcloud_upgrade
fi

if [ "$OVERCLOUD_UPGRADE_CONVERGE" = 1 ]; then
    overcloud_upgrade_converge
fi

if [ "$OVERCLOUD_DELETE" = 1 ]; then
    overcloud_delete
fi

if [[ "$USE_CONTAINERS" == 1 && "$OVERCLOUD_DEPLOY" != 1 ]]; then
    echo "Error: --overcloud-deploy flag is required with the flag --use-containers"
    exit 1
fi

if [ "$OVERCLOUD_PINGTEST" = 1 ]; then
    overcloud_pingtest
fi

if [ "$OVERCLOUD_SANITYTEST" = 1 ]; then
    overcloud_sanitytest
fi

if [ "$TEMPEST_RUN" = 1 ]; then
    tempest_run
fi

if [ "$UNDERCLOUD_UPGRADE" = 1 ]; then
    undercloud_upgrade
    if [ "$UNDERCLOUD_SANITY_CHECK" = 1 ]; then
        undercloud_sanity_check
    fi
fi

if [ "$MULTINODE_SETUP" = 1 ]; then
    multinode_setup
fi

if [ "$BOOTSTRAP_SUBNODES" = 1 ]; then
    bootstrap_subnodes
fi

if [ "$SETUP_NODEPOOL_FILES" = 1 ]; then
    setup_nodepool_files
fi

if [ "$ALL" = 1 ]; then
    repo_setup
    undercloud
    overcloud_images
    register_nodes
    introspect_nodes
    overcloud_deploy
fi
