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
    echo "      --bootstrap-subnodes    -- Perform bootstrap setup on subnodes. WARNING bootstrap-subnodes is deprecated and will be removed."
    echo "      --setup-nodepool-files  -- Setup nodepool files on subnodes."
    echo "      --undercloud            -- Install the undercloud."
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
    echo "      --overcloud-sanitytest    -- Run some basic crud checks for each service."
    echo "      --skip-sanitytest-create  -- Do not create resources when performing a sanitytest (assume they exist)."
    echo "      --skip-sanitytest-cleanup -- Do not delete the created resources when performing a sanitytest."
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
        -l,help,repo-setup,delorean-setup,delorean-build,multinode-setup,bootstrap-subnodes,undercloud,overcloud-images,register-nodes,introspect-nodes,overcloud-deploy,overcloud-update,overcloud-upgrade,overcloud-upgrade-converge,overcloud-delete,use-containers,undercloud-upgrade,all,enable-check,run-tempest,setup-nodepool-files,overcloud-sanitytest,skip-sanitytest-create,skip-sanitytest-cleanup \
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
TRIPLEO_HEAT_TEMPLATES_ROOT=${TRIPLEO_HEAT_TEMPLATES_ROOT:-"/usr/share/openstack-tripleo-heat-templates"}
CONTAINER_ARGS=${CONTAINER_ARGS:-"-e ${TRIPLEO_HEAT_TEMPLATES_ROOT}/environments/docker.yaml --libvirt-type=qemu"}
STABLE_RELEASE=${STABLE_RELEASE:-}
REVIEW_RELEASE=${REVIEW_RELEASE:-}
UPGRADE_RELEASE=${UPGRADE_RELEASE:-""}
DELOREAN_REPO_FILE=${DELOREAN_REPO_FILE:-"delorean.repo"}
DELOREAN_REPO_URL=${DELOREAN_REPO_URL:-"\
    https://trunk.rdoproject.org/centos7/current-tripleo/"}
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
OVERCLOUD_VALIDATE_ARGS=${OVERCLOUD_VALIDATE_ARGS-"--validation-warnings-fatal"}
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
UNDERCLOUD_UPGRADE=${UNDERCLOUD_UPGRADE:-""}
OVERCLOUD_SANITYTEST_SKIP_CREATE=${OVERCLOUD_SANITYTEST_SKIP_CREATE:-""}
OVERCLOUD_SANITYTEST_SKIP_CLEANUP=${OVERCLOUD_SANITYTEST_SKIP_CLEANUP:-""}
OVERCLOUD_SANITYTEST=${OVERCLOUD_SANITYTEST:-""}
SANITYTEST_CONTENT_NAME=${SANITYTEST_CONTENT_NAME:-"sanity_test"}
UNDERCLOUD_SANITY_CHECK=${UNDERCLOUD_SANITY_CHECK:-""}
REPO_SETUP=${REPO_SETUP:-""}
REPO_PREFIX=${REPO_PREFIX:-"/etc/yum.repos.d/"}
CACHEUPLOAD=${CACHEUPLOAD:-"0"}
OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF:-"\
    $REPO_PREFIX/delorean.repo \
    $REPO_PREFIX/delorean-current.repo \
    $REPO_PREFIX/delorean-deps.repo"}
CEPH_RELEASE=jewel
CEPH_REPO_FILE=centos-ceph-$CEPH_RELEASE.repo
if [[ -e /etc/ci/mirror_info.sh ]]; then
    source /etc/ci/mirror_info.sh
fi
NODEPOOL_CENTOS_MIRROR=${NODEPOOL_CENTOS_MIRROR:-http://mirror.centos.org/centos}
NODEPOOL_RDO_PROXY=${NODEPOOL_RDO_PROXY:-https://trunk.rdoproject.org}
NODEPOOL_BUILDLOGS_CENTOS_PROXY="${NODEPOOL_BUILDLOGS_CENTOS_PROXY:-https://buildlogs.centos.org}"
NODEPOOL_CBS_CENTOS_PROXY="${NODEPOOL_CBS_CENTOS_PROXY:-https://cbs.centos.org/repos}"
OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF}"\
    $REPO_PREFIX/$CEPH_REPO_FILE"
OPSTOOLS_REPO_ENABLED=${OPSTOOLS_REPO_ENABLED:-"0"}
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
ALT_OVERCLOUDRC=${ALT_OVERCLOUDRC:-""}
export SCRIPTS_DIR=$(dirname ${BASH_SOURCE[0]:-$0})
OVB=${OVB:-0}

# Make sure we use Puppet to deploy packages on scenario upgrades jobs after ocata release
if [[ "${STABLE_RELEASE}" != "newton" ]] ; then
    OVERCLOUD_UPGRADE_ARGS="$OVERCLOUD_UPGRADE_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/enable_package_install.yaml "
    OVERCLOUD_UPGRADE_CONVERGE_ARGS="$OVERCLOUD_UPGRADE_CONVERGE_ARGS -e $TRIPLEO_ROOT/tripleo-ci/test-environments/enable_package_install.yaml "
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
        --overcloud-sanitytest) OVERCLOUD_SANITYTEST="1"; shift 1;;
        --skip-sanitytest-create) OVERCLOUD_SANITYTEST_SKIP_CREATE="1"; shift 1;;
        --skip-sanitytest-cleanup) OVERCLOUD_SANITYTEST_SKIP_CLEANUP="1"; shift 1;;
        --run-tempest) TEMPEST_RUN="1"; shift 1;;
        --repo-setup) REPO_SETUP="1"; shift 1;;
        --delorean-setup) DELOREAN_SETUP="1"; shift 1;;
        --delorean-build) DELOREAN_BUILD="1"; shift 1;;
        --undercloud) UNDERCLOUD="1"; shift 1;;
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
    if [ $1 = "stackrc" ]; then
        cloud="Undercloud"
    else
        cloud="Overcloud"
    fi
    echo "You must source a $1 file for the $cloud."
    echo "Attempting to source $HOME/$1"
    source $HOME/$1
    echo "Done"
}

function stackrc_check {
    source_rc "stackrc"
}

function overcloudrc_check {
    if [ -z "$ALT_OVERCLOUDRC" ]; then
        source_rc "overcloudrc"
    else
        source_rc "$ALT_OVERCLOUDRC"
    fi
}

function repo_setup {

    log "Repository setup"

    sudo yum clean metadata

    # sets $TRIPLEO_OS_FAMILY and $TRIPLEO_OS_DISTRO
    source $(dirname ${BASH_SOURCE[0]:-$0})/set-os-type

    if [ "$TRIPLEO_OS_DISTRO" = "centos" ]; then
        # Enable Storage/SIG Ceph repo
        if rpm -q centos-release-ceph-jewel; then
            sudo yum -y erase centos-release-ceph-jewel
        fi
        sudo /bin/bash -c "cat <<-EOF>$REPO_PREFIX/$CEPH_REPO_FILE
[centos-ceph-$CEPH_RELEASE]
name=centos-ceph-$CEPH_RELEASE
baseurl=$NODEPOOL_CENTOS_MIRROR/7/storage/x86_64/ceph-$CEPH_RELEASE/
gpgcheck=0
enabled=1
EOF"
        if [[ "${OPSTOOLS_REPO_ENABLED}" = 1 ]]; then
            sudo /bin/bash -c "cat <<-EOF>$REPO_PREFIX/centos-opstools.repo
[centos-opstools]
name=centos-opstools
baseurl=$NODEPOOL_CENTOS_MIRROR/7/opstools/x86_64/
gpgcheck=0
enabled=1
EOF"
        fi
    fi
    # @matbu TBR debuginfo:
    log "Stable release: $STABLE_RELEASE"
    if [ -z "$STABLE_RELEASE" ]; then
        # Enable the Delorean Deps repository
        sudo curl -fLvo $REPO_PREFIX/delorean-deps.repo https://trunk.rdoproject.org/centos7/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo
        sudo sed -i -e "s~http://mirror.centos.org/centos~$NODEPOOL_CENTOS_MIRROR~" $REPO_PREFIX/delorean-deps.repo
        sudo sed -i -e "s~https://buildlogs.centos.org~$NODEPOOL_BUILDLOGS_CENTOS_PROXY~" $REPO_PREFIX/delorean-deps.repo
        sudo sed -i -e "s~https://trunk.rdoproject.org~$NODEPOOL_RDO_PROXY~" $REPO_PREFIX/delorean-deps.repo
        cat $REPO_PREFIX/delorean-deps.repo

        # Enable last known good RDO Trunk Delorean repository
        sudo curl -fLvo $REPO_PREFIX/delorean.repo $DELOREAN_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo
        sudo sed -i -e "s~https://trunk.rdoproject.org~$NODEPOOL_RDO_PROXY~" $REPO_PREFIX/delorean.repo
        cat $REPO_PREFIX/delorean.repo

        # Enable latest RDO Trunk Delorean repository if not promotion job
        if [[ $CACHEUPLOAD != 1 ]]; then
            sudo curl -fLvo $REPO_PREFIX/delorean-current.repo https://trunk.rdoproject.org/centos7/current/delorean.repo
            sudo sed -i -e 's%priority=.*%priority=10%' $REPO_PREFIX/delorean-current.repo
            sudo sed -i 's/\[delorean\]/\[delorean-current\]/' $REPO_PREFIX/delorean-current.repo
            sudo sed -i -e "s~https://trunk.rdoproject.org~$NODEPOOL_RDO_PROXY~" $REPO_PREFIX/delorean-current.repo
            sudo /bin/bash -c "cat <<-EOF>>$REPO_PREFIX/delorean-current.repo

includepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-*,openstack-puppet-modules,puppet-*
EOF"
        else
            # Create empty delorean-current for dib image building
            sudo sh -c "> $REPO_PREFIX/delorean-current.repo"
        fi
        cat $REPO_PREFIX/delorean-current.repo
    else
        # Enable the Delorean Deps repository
        sudo curl -fLvo $REPO_PREFIX/delorean-deps.repo https://trunk.rdoproject.org/centos7-$STABLE_RELEASE/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo
        sudo sed -i -e "s~http://mirror.centos.org/centos~$NODEPOOL_CENTOS_MIRROR~" $REPO_PREFIX/delorean-deps.repo
        sudo sed -i -e "s~https://buildlogs.centos.org~$NODEPOOL_BUILDLOGS_CENTOS_PROXY~" $REPO_PREFIX/delorean-deps.repo
        cat $REPO_PREFIX/delorean-deps.repo

        # Enable delorean current for the stable version
        sudo curl -fLvo $REPO_PREFIX/delorean.repo $DELOREAN_STABLE_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo
        sudo sed -i -e "s~https://trunk.rdoproject.org~$NODEPOOL_RDO_PROXY~" $REPO_PREFIX/delorean.repo
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
    sudo yum install -y createrepo git mock rpm-build yum-plugin-priorities yum-utils gcc rpmdevtools redhat-rpm-config

    # NOTE(pabelanger): Check if virtualenv is already install, if not install
    # from packages.
    if ! command -v virtualenv ; then
        sudo yum install -y python-virtualenv
    fi

    # Workaround until https://review.opendev.org/#/c/311734/ is merged and a new image is built
    sudo yum install -y libffi-devel openssl-devel

    # Add the current user to the mock group
    sudo usermod -G mock -a $(id -nu)

    mkdir -p $TRIPLEO_ROOT
    [ -d $TRIPLEO_ROOT/delorean ] || git clone https://github.com/softwarefactory-project/DLRN.git $TRIPLEO_ROOT/delorean

    pushd $TRIPLEO_ROOT/delorean

    sudo rm -rf data commits.sqlite
    mkdir -p data

    sed -i -e "s%reponame=.*%reponame=delorean-ci%" projects.ini
    sed -i -e "s%target=.*%target=centos%" projects.ini

    # Remove the rpm install test to speed up delorean (our ci test will to this)
    if [ -f scripts/build_rpm.sh ]; then
        # DLRN < 0.8.0
        sed -i -e 's%--postinstall%%' scripts/build_rpm.sh
    else
        # This is an option in DLRN since 0.8.0 for the mock build driver
        sed -i -e 's/^#install_after_build=1.*/install_after_build=0/' projects.ini
    fi

    virtualenv venv
    # NOTE(pabelanger): We need to update setuptools to the latest version for
    # CentOS 7.  Also, pytz is not declared as a dependency so we need to
    # manually add it.  Lastly, use pip install . to use wheel AFS pypi mirrors.
    ./venv/bin/pip install -U pip
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
        sed -i -e "s%baseurl=.*%baseurl=$NODEPOOL_RDO_PROXY/centos7-$REVIEW_RELEASE%" projects.ini
        # RDO changed the distgit branch for stable releases starting from newton.
        sed -i -e "s%distro=.*%distro=$REVIEW_RELEASE-rdo%" projects.ini
        sed -i -e "s%source=.*%source=stable/$REVIEW_RELEASE%" projects.ini
    elif [ -n "$FEATURE_BRANCH" ]; then
        # next, check if we are testing for a feature branch
        log "Building for feature branch $FEATURE_BRANCH"
        sed -i -e "s%baseurl=.*%baseurl=$NODEPOOL_RDO_PROXY/centos7%" projects.ini
        sed -i -e "s%distro=.*%distro=rpm-$FEATURE_BRANCH%" projects.ini
        sed -i -e "s%source=.*%source=$FEATURE_BRANCH%" projects.ini
    else
        log "Building for master"
        sed -i -e "s%baseurl=.*%baseurl=$NODEPOOL_RDO_PROXY/centos7%" projects.ini
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
            git clone https://opendev.org/openstack/$PROJ.git $TRIPLEO_ROOT/$PROJ
            if [ ! -z "$REVIEW_RELEASE" ]; then
                pushd $TRIPLEO_ROOT/$PROJ
                git checkout -b stable/$REVIEW_RELEASE origin/stable/$REVIEW_RELEASE
                popd
            fi
        fi

        # Work around inconsistency where map-project-name expects oslo-*
        MAPPED_NAME=$(echo $PROJ | sed "s/oslo./oslo-/")
        MAPPED_PROJ=$(rdopkg findpkg $MAPPED_NAME | grep ^name | awk '{print $2}' || true)
        [ -e data/$MAPPED_PROJ ] && continue
        cp -r $TRIPLEO_ROOT/$PROJ data/$MAPPED_PROJ
        pushd data/$MAPPED_PROJ
        GITHASH=$(git rev-parse HEAD)

        # Set the branches delorean reads to the same git hash as PROJ has left for us
        for BRANCH in master origin/master stable/newton origin/stable/newton stable/ocata origin/stable/ocata stable/pike origin/stable/pike stable/queens origin/stable/queens; do
            git checkout -b $BRANCH || git checkout $BRANCH
            git reset --hard $GITHASH
        done
        popd

        set +e
        while true; do
            DELOREANCMD="./venv/bin/dlrn --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --use-public --build-env http_proxy=${http_proxy:-}"
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

    sudo yum install -y python-tripleoclient ceph-ansible

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

    # Masquerade traffic to external networks from controllers on baremetal undercloud
    # In ovb deployments, baremental nodes use undercloud as default route to reach DNS etc...
    if [ $OVB -eq 1 ]; then
        sudo iptables -A BOOTSTACK_MASQ -s 10.0.0.0/24 ! -d 10.0.0.0/24 -j MASQUERADE -t nat
        sudo iptables-save | sudo tee /etc/sysconfig/iptables
    fi

    log "Undercloud install - DONE."

}

function overcloud_images {

    log "Overcloud images"

    # This hack is no longer needed in ocata.
    if [[ "${STABLE_RELEASE}" =~ ^(newton)$ ]]; then
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
    if [[ "${STABLE_RELEASE}" =~ ^(newton)$ ]] ; then
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

    if [ "$INTROSPECT_NODES" = 1 ]; then
        # Keep the nodes in manageable state so that they may be
        # introspected later.
        openstack overcloud node import $INSTACKENV_JSON_PATH
    else
        openstack overcloud node import $INSTACKENV_JSON_PATH --provide
    fi

    ironic node-list

    log "Register nodes - DONE."

}

function introspect_nodes {

    log "Introspect nodes"

    stackrc_check

    # Note: Unlike the legacy bulk command, overcloud node
    # introspect will only run on nodes in the 'manageable'
    # provisioning state.
    openstack overcloud node introspect --all-manageable
    openstack overcloud node provide --all-manageable

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
    if [ $exitval -eq 1 ]; then
        log "Overcloud create - FAILED!"
        exit 1
    fi
    log "Overcloud create - DONE."
}

function undercloud_upgrade {

    log "Undercloud upgrade"

    # Setup repositories
    repo_setup

    # In pike and above this is handled by the pre-upgrade hook
    if [[ "$STABLE_RELEASE" =~ ^(newton|ocata)$ ]]; then
        sudo systemctl stop openstack-*
        sudo systemctl stop neutron-*
        sudo systemctl stop openvswitch
        sudo systemctl stop httpd
    fi
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
        if [ $exitval -eq 1 ]; then
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
    if openstack stack show "$OVERCLOUD_NAME" 2>&1 > /dev/null ; then
        log "Create overcloud repo template file"
        /bin/bash -c "cat <<EOF>$HOME/init-repo.yaml

parameter_defaults:
  UpgradeInitCommand: |
    set -e
    # For some reason '$HOME' is not defined when the Heat agent executes this
    # script and tripleo.sh expects it. Just reuse the same value from the
    # current undercloud user.
    yum clean all
    export STABLE_RELEASE=$STABLE_RELEASE
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
EOF"
        log "Overcloud upgrade started."
        log "Upgrade command arguments: $OVERCLOUD_UPGRADE_ARGS"
        log "Execute major upgrade."
        openstack overcloud deploy $OVERCLOUD_UPGRADE_ARGS
        log "Major upgrade - DONE."

        if openstack stack show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "UPDATE_COMPLETE"; then
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
    if openstack stack show "$OVERCLOUD_NAME" 2>&1 > /dev/null; then
        log "Overcloud upgrade converge started."
        log "Upgrade command arguments: $OVERCLOUD_UPGRADE_CONVERGE_ARGS"
        log "Execute major upgrade converge."
        openstack overcloud deploy $OVERCLOUD_UPGRADE_CONVERGE_ARGS
        log "Major upgrade converge - DONE."

        if openstack stack show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "UPDATE_COMPLETE"; then
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
    if $($(dirname $0)/wait_for -w $OVERCLOUD_DELETE_TIMEOUT -d 10 -s "DELETE_COMPLETE" -- "$wait_command"); then
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

    if openstack stack show "$OVERCLOUD_NAME" | grep "stack_status " | egrep -q "(CREATE|UPDATE)_COMPLETE"; then

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
        auth.use_dynamic_credentials true \
        identity.admin_password $OS_PASSWORD \
        compute.build_timeout 500 \
        validation.image_ssh_user cirros \
        orchestration.stack_owner_role _member_ \
        network.build_timeout 500 \
        volume.build_timeout 500 \
        DEFAULT.log_file "/var/log/tempest/tempest.log" \
        $TEMPEST_ADD_CONFIG
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
        git clone https://opendev.org/$repo
        popd
    else
        echo "$repo found at $TRIPLEO_ROOT/$repo, nothing to do."
    fi

}

# This function creates an internal gre bridge to connect all external
# network bridges across the compute and network nodes.
# bridge_name: Bridge name on each host for logical l2 network
#              connectivity.
# host_ip: ip address of the bridge host which is reachable for all peer
#          the hub for all of our spokes.
# set_ips: Whether or not to set l3 addresses on our logical l2 network.
#          This can be helpful for setting up routing tables.
# offset: starting value for gre tunnel key and the ip addr suffix
# The next two parameters are only used if set_ips is "True".
# pub_addr_prefix: The IPv4 address three octet prefix used to give compute
#                  nodes non conflicting addresses on the pub_if_name'd
#                  network. Should be provided as X.Y.Z. Offset will be
#                  applied to this as well as the below mask to get the
#                  resulting address.
# pub_addr_mask: the CIDR mask less the '/' for the IPv4 addresses used
#                above.
# every additional parameter is considered as a peer host (spokes)
#
# For OVS troubleshooting needs:
#   http://www.yet.org/2014/09/openvswitch-troubleshooting/
#
function ovs_vxlan_bridge {
    if is_suse; then
        local ovs_package='openvswitch'
        local ovs_service='openvswitch'
    elif is_fedora; then
        local ovs_package='openvswitch openstack-selinux'
        local ovs_service='openvswitch'
    elif uses_debs; then
        local ovs_package='openvswitch-switch'
        local ovs_service='openvswitch-switch'
    else
        echo "Unsupported platform, can't determine openvswitch service"
        exit 1
    fi
    local install_ovs_deps="source $BASE/new/devstack/functions-common; \
                            install_package ${ovs_package}; \
                            restart_service ${ovs_service}"
    local mtu=1450
    local bridge_name=$1
    local host_ip=$2
    local set_ips=$3
    local offset=$4
    if [[ "$set_ips" == "True" ]] ; then
        local pub_addr_prefix=$5
        local pub_addr_mask=$6
        shift 6
    else
        shift 4
    fi
    local peer_ips=$@
    # neutron uses 1:1000 with default devstack configuration, avoid overlap
    local additional_vni_offset=1000000
    eval $install_ovs_deps
    # create a bridge, just like you would with 'brctl addbr'
    # if the bridge exists, --may-exist prevents ovs from returning an error
    sudo ovs-vsctl --may-exist add-br $bridge_name
    # as for the mtu, look for notes on lp#1301958 in devstack-vm-gate.sh
    sudo ip link set mtu $mtu dev $bridge_name
    if [[ "$set_ips" == "True" ]] ; then
        echo "Set bridge: ${bridge_name}"
        if ! sudo ip addr show dev ${bridge_name} | grep -q \
            ${pub_addr_prefix}.${offset}/${pub_addr_mask} ; then
                sudo ip addr add ${pub_addr_prefix}.${offset}/${pub_addr_mask} \
                    dev ${bridge_name}
        fi
    fi
    sudo ip link set dev $bridge_name up
    for node_ip in $peer_ips; do
        offset=$(( offset+1 ))
        vni=$(( offset + additional_vni_offset ))
        # For reference on how to setup a tunnel using OVS see:
        #   http://openvswitch.org/support/config-cookbooks/port-tunneling/
        # The command below is equivalent to the sequence of ip/brctl commands
        # where an interface of vxlan type is created first, and then plugged into
        # the bridge; options are command specific configuration key-value pairs.
        #
        # Create the vxlan tunnel for the Controller/Network Node:
        #  This establishes a tunnel between remote $node_ip to local $host_ip
        #  uniquely identified by a key $offset
        sudo ovs-vsctl --may-exist add-port $bridge_name \
            ${bridge_name}_${node_ip} \
            -- set interface ${bridge_name}_${node_ip} type=vxlan \
            options:remote_ip=${node_ip} \
            options:key=${vni} \
            options:local_ip=${host_ip}
        # Now complete the vxlan tunnel setup for the Compute Node:
        #  Similarly this establishes the tunnel in the reverse direction
        remote_command $node_ip "$install_ovs_deps"
        remote_command $node_ip sudo ovs-vsctl --may-exist add-br $bridge_name
        remote_command $node_ip sudo ip link set mtu $mtu dev $bridge_name
        remote_command $node_ip sudo ovs-vsctl --may-exist add-port $bridge_name \
            ${bridge_name}_${host_ip} \
            -- set interface ${bridge_name}_${host_ip} type=vxlan \
            options:remote_ip=${host_ip} \
            options:key=${vni} \
            options:local_ip=${node_ip}
        if [[ "$set_ips" == "True" ]] ; then
            if ! remote_command $node_ip sudo ip addr show dev ${bridge_name} | \
                grep -q ${pub_addr_prefix}.${offset}/${pub_addr_mask} ; then
                    remote_command $node_ip sudo ip addr add \
                        ${pub_addr_prefix}.${offset}/${pub_addr_mask} \
                        dev ${bridge_name}
            fi
        fi
        remote_command $node_ip sudo ip link set dev $bridge_name up
    done
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
    if [[ ! "${STABLE_RELEASE}" =~ ^(newton|ocata) ]]; then
      # This verifies that at least one conductor comes up, and at least one
      # IPMI-based driver was successfully enabled.
      ipmi_drivers="$(grep -c ipmi <(ironic driver-list))"
      if [[ $ipmi_drivers -eq 0 ]]; then
        log "ERROR: Check ironic driver-list"
        exit 1
      fi
    else
      ironic node-list
    fi
    openstack stack list
    ui_sanity_check
    set +x
}

function bootstrap_subnodes {
    log "WARNING: Bootstrap subnodes is deprecated and will be removed. "

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
        cat /etc/nodepool/id_rsa.pub >> ~/.ssh/authorized_keys
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
        echo $sub_node_ip >> /etc/nodepool/sub_nodes
        echo $sub_node_ip >> /etc/nodepool/sub_nodes_private
    done

    for sub_node_ip in $SUB_NODE_IPS; do
        echo $sub_node_ip > /etc/nodepool/node
        echo $sub_node_ip > /etc/nodepool/node_private
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
    undercloud
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
