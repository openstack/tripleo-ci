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
    echo "      --undercloud            -- Install the undercloud."
    echo "      --overcloud-images      -- Build and load overcloud images."
    echo "      --register-nodes        -- Register and configure nodes."
    echo "      --introspect-nodes      -- Introspect nodes."
    echo "      --overcloud-deploy      -- Deploy an overcloud."
    echo "      --overcloud-update      -- Update a deployed overcloud."
    echo "      --overcloud-delete      -- Delete the overcloud."
    echo "      --use-containers        -- Use a containerized compute node."
    echo "      --enable-check          -- Enable checks on update."
    echo "      --overcloud-pingtest    -- Run a tenant vm, attach and ping floating IP."
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
        -l,help,repo-setup,delorean-setup,delorean-build,undercloud,overcloud-images,register-nodes,introspect-nodes,overcloud-deploy,overcloud-update,overcloud-delete,use-containers,overcloud-pingtest,skip-pingtest-cleanup,all,enable-check,run-tempest \
        -o,x,h,a \
        -n $SCRIPT_NAME -- "$@")

if [ $? != 0 ]; then
    show_options
    exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

ALL=${ALL:-""}
CONTAINER_ARGS=${CONTAINER_ARGS:-"-e /usr/share/openstack-tripleo-heat-templates/environments/docker.yaml -e /usr/share/openstack-tripleo-heat-templates/environments/docker-network.yaml --libvirt-type=qemu"}
STABLE_RELEASE=${STABLE_RELEASE:-}
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
OVERCLOUD_VALIDATE_ARGS=${OVERCLOUD_VALIDATE_ARGS:-"--validation-errors-fatal --validation-warnings-fatal"}
OVERCLOUD_UPDATE=${OVERCLOUD_UPDATE:-""}
OVERCLOUD_UPDATE_RM_FILES=${OVERCLOUD_UPDATE_RM_FILES:-"1"}
OVERCLOUD_UPDATE_ARGS=${OVERCLOUD_UPDATE_ARGS:-"$OVERCLOUD_DEPLOY_ARGS $OVERCLOUD_VALIDATE_ARGS"}
OVERCLOUD_UPDATE_CHECK=${OVERCLOUD_UPDATE_CHECK:-}
OVERCLOUD_IMAGES_PATH=${OVERCLOUD_IMAGES_PATH:-"$HOME"}
OVERCLOUD_IMAGES=${OVERCLOUD_IMAGES:-""}
OVERCLOUD_IMAGES_ARGS=${OVERCLOUD_IMAGES_ARGS='--all'}
OVERCLOUD_NAME=${OVERCLOUD_NAME:-"overcloud"}
SKIP_PINGTEST_CLEANUP=${SKIP_PINGTEST_CLEANUP:-""}
OVERCLOUD_PINGTEST=${OVERCLOUD_PINGTEST:-""}
REPO_SETUP=${REPO_SETUP:-""}
REPO_PREFIX=${REPO_PREFIX:-"/etc/yum.repos.d/"}
OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF=${OVERCLOUD_IMAGES_DIB_YUM_REPO_CONF:-"\
    $REPO_PREFIX/delorean.repo \
    $REPO_PREFIX/delorean-current.repo \
    $REPO_PREFIX/delorean-deps.repo"}
DELOREAN_SETUP=${DELOREAN_SETUP:-""}
DELOREAN_BUILD=${DELOREAN_BUILD:-""}
STDERR=/dev/null
UNDERCLOUD=${UNDERCLOUD:-""}
UNDERCLOUD_CONF=${UNDERCLOUD_CONF:-"/usr/share/instack-undercloud/undercloud.conf.sample"}
TRIPLEO_ROOT=${TRIPLEO_ROOT:-$HOME/tripleo}
USE_CONTAINERS=${USE_CONTAINERS:-""}
TEMPEST_RUN=${TEMPEST_RUN:-""}
TEMPEST_ARGS=${TEMPEST_ARGS:-"--parallel --subunit"}
TEMPEST_ADD_CONFIG=${TEMPEST_ADD_CONFIG:-}
TEMPEST_REGEX=${TEMPEST_REGEX:-"^(?=(.*smoke))(?!(tempest.api.orchestration.stacks|tempest.scenario.test_volume_boot_pattern|tempest.api.telemetry))"}
TEMPEST_PINNED="fb77374ddeeb1642bffa086311d5f281e15142b2"

# TODO: remove this when Image create in openstackclient supports the v2 API
export OS_IMAGE_API_VERSION=1

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
        --overcloud-delete) OVERCLOUD_DELETE="1"; shift 1;;
        --overcloud-images) OVERCLOUD_IMAGES="1"; shift 1;;
        --overcloud-pingtest) OVERCLOUD_PINGTEST="1"; shift 1;;
        --skip-pingtest-cleanup) SKIP_PINGTEST_CLEANUP="1"; shift 1;;
        --run-tempest) TEMPEST_RUN="1"; shift 1;;
        --repo-setup) REPO_SETUP="1"; shift 1;;
        --delorean-setup) DELOREAN_SETUP="1"; shift 1;;
        --delorean-build) DELOREAN_BUILD="1"; shift 1;;
        --undercloud) UNDERCLOUD="1"; shift 1;;
        -x) set -x; STDERR=/dev/stderr; shift 1;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done


##Begin TODO ccamacho: Remove when Liberty EOL: 2016-11-17
function openstack {
    if [ "$1" == "stack" ] ; then
        if [ -z "$STABLE_RELEASE" ]; then
            /usr/bin/openstack $@
         else
            heat stack-${@:2:$#}
        fi
    else
       /usr/bin/openstack $@
    fi
}
##End TODO


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

    # sets $TRIPLEO_OS_FAMILY and $TRIPLEO_OS_DISTRO
    source $(dirname ${BASH_SOURCE[0]:-$0})/set-os-type

    if [ "$TRIPLEO_OS_DISTRO" = "centos" ]; then
        # Enable epel
        rpm -q epel-release || sudo yum -y install epel-release
    fi

    if [ -z "$STABLE_RELEASE" ]; then
        # Enable the Delorean Deps repository
        sudo curl -Lo $REPO_PREFIX/delorean-deps.repo http://trunk.rdoproject.org/centos7/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo

        # Enable last known good RDO Trunk Delorean repository
        sudo curl -Lo $REPO_PREFIX/delorean.repo $DELOREAN_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo

        # Enable latest RDO Trunk Delorean repository
        sudo curl -Lo $REPO_PREFIX/delorean-current.repo http://trunk.rdoproject.org/centos7/current/delorean.repo
        sudo sed -i -e 's%priority=.*%priority=10%' $REPO_PREFIX/delorean-current.repo
        sudo sed -i 's/\[delorean\]/\[delorean-current\]/' $REPO_PREFIX/delorean-current.repo
        sudo /bin/bash -c "cat <<-EOF>>$REPO_PREFIX/delorean-current.repo

includepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-cloud-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-common,openstack-tripleo-heat-templates,openstack-tripleo-image-elements,openstack-tripleo,openstack-tripleo-puppet-elements
EOF"
    else
        # Enable the Delorean Deps repository
        sudo curl -Lo $REPO_PREFIX/delorean-deps.repo http://trunk.rdoproject.org/centos7-$STABLE_RELEASE/delorean-deps.repo
        sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo

        # Enable delorean current for the stable version
        sudo curl -Lo $REPO_PREFIX/delorean.repo $DELOREAN_STABLE_REPO_URL/$DELOREAN_REPO_FILE
        sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo

        # Create empty delorean-current for dib image building
        sudo sh -c "> $REPO_PREFIX/delorean-current.repo"
    fi

    # Install the yum-plugin-priorities package so that the Delorean repository
    # takes precedence over the main RDO repositories.
    sudo yum -y install yum-plugin-priorities

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

    if [ -z "$STABLE_RELEASE" ]; then
        sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7%" projects.ini
        sed -i -e "s%distro=.*%distro=rpm-master%" projects.ini
        sed -i -e "s%source=.*%source=master%" projects.ini
    else
        sed -i -e "s%baseurl=.*%baseurl=https://trunk.rdoproject.org/centos7-$STABLE_RELEASE%" projects.ini
        sed -i -e "s%distro=.*%distro=rpm-$STABLE_RELEASE%" projects.ini
        sed -i -e "s%source=.*%source=stable/$STABLE_RELEASE%" projects.ini
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
            if [ ! -z "$STABLE_RELEASE" ]; then
                pushd $TRIPLEO_ROOT/$PROJ
                git checkout -b stable/$STABLE_RELEASE origin/stable/$STABLE_RELEASE
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
        for BRANCH in master origin/master stable/liberty origin/stable/liberty stable/mitaka origin/stable/mitaka; do
            git checkout -b $BRANCH || git checkout $BRANCH
            git reset --hard $GITHASH
        done
        popd

        while true; do
            DELOREANCMD="./venv/bin/dlrn --config-file projects.ini --head-only --package-name $MAPPED_PROJ --local --build-env DELOREAN_DEV=1 --build-env http_proxy=${http_proxy:-} --info-repo rdoinfo"
            # Using sudo to su a command as ourselves to run the command with a new login
            # to ensure the addition to the mock group has taken effect.
            sudo su $(id -nu) -c "$DELOREANCMD" || true

            # If delorean fails due to a network error it will mark it to be retried up to 3 times
            # Test the status and run delorean again if it is not SUCCESS or FAILED
            STATUS=$(echo "select status from commits where project_name == \"$MAPPED_PROJ\" order by id desc limit 1;" | sqlite3 commits.sqlite)
            if [ "$STATUS" == "FAILED" ] ; then
                exit 1
            elif [ "$STATUS" == "SUCCESS" ] ; then
                break
            elif [ "$STATUS" == "RETRY" ] ; then
                continue
            fi
            exit 1
        done
    done
    popd
    log "Delorean build - DONE."
}

function undercloud {

    log "Undercloud install"
    # We use puppet modules from source by default for master, for stable we
    # currently use a stable package (we may eventually want to use a
    # stable-puppet-modules element instead so we can set DIB_REPOREF.., etc)
    if [ -z "$STABLE_RELEASE" ]; then
        export DIB_INSTALLTYPE_puppet_modules=${DIB_INSTALLTYPE_puppet_modules:-source}
    else
        export DIB_INSTALLTYPE_puppet_modules=${DIB_INSTALLTYPE_puppet_modules:-}
    fi

    sudo yum install -y python-tripleoclient

    if [ ! -f ~/undercloud.conf ]; then
        cp -b -f $UNDERCLOUD_CONF ~/undercloud.conf
    else
        log "~/undercloud.conf  already exists, not overwriting"
    fi

    # Hostname check, add to /etc/hosts if needed
    if ! grep -E "^127.0.0.1\s*$HOSTNAME" /etc/hosts; then
        sudo /bin/bash -c "echo \"127.0.0.1 $HOSTNAME\" >> /etc/hosts"
    fi

    openstack undercloud install

    log "Undercloud install - DONE."

}

function overcloud_images {

    log "Overcloud images"
    log "Overcloud images saved in $OVERCLOUD_IMAGES_PATH"

    # We use puppet modules from source by default for master, for stable we
    # currently use a stable package (we may eventually want to use a
    # stable-puppet-modules element instead so we can set DIB_REPOREF.., etc)
    if [ -z "$STABLE_RELEASE" ]; then
        export DIB_INSTALLTYPE_puppet_modules=${DIB_INSTALLTYPE_puppet_modules:-source}
    else
        export DIB_INSTALLTYPE_puppet_modules=${DIB_INSTALLTYPE_puppet_modules:-}
    fi

    if [[ "${STABLE_RELEASE}" =~ ^(liberty)$ ]] ; then
        export FS_TYPE=ext4
    fi

    # (slagle) TODO: This needs to be fixed in python-tripleoclient or
    # diskimage-builder!
    # Ensure yum-plugin-priorities is installed
    echo -e '#!/bin/bash\nyum install -y yum-plugin-priorities' | sudo tee /usr/share/diskimage-builder/elements/yum/pre-install.d/99-tmphacks
    sudo chmod +x /usr/share/diskimage-builder/elements/yum/pre-install.d/99-tmphacks

    # To install the undercloud instack-undercloud is run as root,
    # as a result all of the git repositories get cached to
    # ~root/.cache/image-create/source-repositories, lets not clone them again
    if [ -d ~root/.cache/image-create/source-repositories ] && \
       [ ! -d ~/.cache/image-create/source-repositories ] ; then
        sudo cp -r ~root/.cache/image-create/source-repositories ~/.cache/image-create/source-repositories
        sudo chown -R $(id -u) ~/.cache/image-create/source-repositories
    fi

    log "Overcloud images saved in $OVERCLOUD_IMAGES_PATH"
    pushd $OVERCLOUD_IMAGES_PATH
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
    openstack baremetal import --json $INSTACKENV_JSON_PATH
    ironic node-list
    if [[ "${STABLE_RELEASE}" =~ ^(liberty|mitaka)$ ]] ; then
        # This step is a part of the import command from Newton on
        openstack baremetal configure boot
    fi

    log "Register nodes - DONE."

}

function introspect_nodes {

    log "Introspect nodes"

    stackrc_check
    openstack baremetal introspection bulk start

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

    if [[ $USE_CONTAINERS == 1 ]]; then
        if ! glance image-list | grep  -q atomic-image; then
            wget --progress=dot:mega $ATOMIC_URL
            glance image-create --name atomic-image --file `basename $ATOMIC_URL` --disk-format qcow2 --container-format bare
        fi
        #TODO: When container job is changed to network-isolation remove this
        neutron subnet-update $(neutron net-list | grep ctlplane | cut  -d ' ' -f 6) --dns-nameserver 8.8.8.8
        OVERCLOUD_DEPLOY_ARGS="$OVERCLOUD_DEPLOY_ARGS $CONTAINER_ARGS"
    fi

    log "Overcloud create started."
    openstack overcloud deploy $OVERCLOUD_DEPLOY_ARGS
    log "Overcloud create - DONE."
}

function overcloud_update {
    # Force use of --templates
    if [[ ! $OVERCLOUD_UPDATE_ARGS =~ --templates ]]; then
        OVERCLOUD_UPDATE_ARGS="$OVERCLOUD_UPDATE_ARGS --templates"
    fi
    stackrc_check
    if heat stack-show "$OVERCLOUD_NAME" | grep "stack_status " | egrep "(CREATE|UPDATE)_COMPLETE"; then
        FILE_PREFIX=$(date "+overcloud-update-resources-%s")
        BEFORE_FILE="/tmp/${FILE_PREFIX}-before.txt"
        AFTER_FILE="/tmp/${FILE_PREFIX}-after.txt"
        # This is an update, so if enabled, compare the before/after resource lists
        if [ ! -z "$OVERCLOUD_UPDATE_CHECK" ]; then
            heat resource-list -n5 overcloud | awk '{print $2, $4, $6}' | sort > $BEFORE_FILE
        fi

        log "Overcloud update started."
        openstack overcloud deploy $OVERCLOUD_UPDATE_ARGS
        log "Overcloud update - DONE."

        if [ ! -z "$OVERCLOUD_UPDATE_CHECK" ]; then
            heat resource-list -n5 overcloud | awk '{print $2, $4, $6}' | sort > $AFTER_FILE
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

function overcloud_delete {

    log "Overcloud delete"

    stackrc_check

    # We delete the stack via heat, then wait for it to be deleted
    # This should be fairly quick, but we poll for OVERCLOUD_DELETE_TIMEOUT
    yes | openstack stack delete "$OVERCLOUD_NAME"
    # Note, we need the ID, not the name, as stack-show will only return
    # soft-deleted stacks by ID (not name, as it may be reused)
    OVERCLOUD_ID=$(openstack stack list | grep "$OVERCLOUD_NAME" | awk '{print $2}')
    if $(tripleo wait_for -w $OVERCLOUD_DELETE_TIMEOUT -d 10 -s "DELETE_COMPLETE" -- "openstack stack show $OVERCLOUD_ID"); then
       log "Overcloud $OVERCLOUD_ID DELETE_COMPLETE"
    else
       log "Overcloud $OVERCLOUD_ID delete failed or timed out:"
       openstack stack show $OVERCLOUD_ID
       exit 1
    fi
}

function cleanup_pingtest {

    log "Overcloud pingtest; cleaning environment"
    overcloudrc_check
    yes | openstack stack delete tenant-stack || true
    if tripleo wait_for -w 300 -d 10 -s "Stack not found" -- "openstack stack show tenant-stack"; then
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
    FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-"192.0.2.0/24"}
    FLOATING_IP_START=${FLOATING_IP_START:-"192.0.2.50"}
    FLOATING_IP_END=${FLOATING_IP_END:-"192.0.2.64"}
    EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"192.0.2.1"}
    TENANT_STACK_DEPLOY_ARGS=${TENANT_STACK_DEPLOY_ARGS:-""}
    neutron subnet-create --name ext-subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY nova $FLOATING_IP_CIDR
    TENANT_PINGTEST_TEMPLATE=/usr/share/tripleo-ci/tenantvm_floatingip.yaml
    if [ ! -e $TENANT_PINGTEST_TEMPLATE ]; then
        TENANT_PINGTEST_TEMPLATE=$(dirname `readlink -f -- $0`)/../templates/tenantvm_floatingip.yaml
    fi
    log "Overcloud pingtest, creating tenant-stack heat stack:"
    heat stack-create -f $TENANT_PINGTEST_TEMPLATE $TENANT_STACK_DEPLOY_ARGS tenant-stack || exitval=1

    # No point in waiting if the previous command failed.
    if [ ${exitval} -eq 0 ]; then
        # TODO(beagles): While the '-f' flag will short-circuit fail us, we'll
        # likely have to wait for service operations to timeout before the
        # stack gets marked as failed anyways. A CI oriented configuration for
        # some key services *might* work for 'fail faster', but where things
        # can be so slow already it might just cause more pain.
        #
        if tripleo wait_for -w 1200 -d 10 -s "CREATE_COMPLETE" -f "CREATE_FAILED" -- "heat stack-list | grep tenant-stack"; then
            log "Overcloud pingtest, heat stack CREATE_COMPLETE";

            vm1_ip=`heat output-show tenant-stack server1_public_ip -F raw`
            # On new Heat clients the above command returns a big long string.
            # If the resulting value is longer than an IP address we need the alternate command.
            if [ ${#vm1_ip} -gt 15 ]; then
                vm1_ip=`heat output-show tenant-stack server1_public_ip -F raw -v`
            fi

            log "Overcloud pingtest, trying to ping the floating IPs $vm1_ip"

            if tripleo wait_for -w 360 -d 10 -s "bytes from $vm1_ip" -- "ping -c 1 $vm1_ip" ; then
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
            heat stack-show tenant-stack || :
            heat event-list tenant-stack || :
            heat resource-list -n 5 tenant-stack || :
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

    overcloudrc_check
    clean_tempest
    root_dir=$(realpath $(dirname ${BASH_SOURCE[0]:-$0}))
    [[ ! -e $HOME/tempest ]] && git clone https://github.com/openstack/tempest $HOME/tempest
    pushd $HOME/tempest
    git checkout $TEMPEST_PINNED
    FLOATING_IP_CIDR=${FLOATING_IP_CIDR:-"192.0.2.0/24"};
    FLOATING_IP_START=${FLOATING_IP_START:-"192.0.2.50"};
    FLOATING_IP_END=${FLOATING_IP_END:-"192.0.2.64"};
    export EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY:-"192.0.2.1"};
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

if [ "$TEMPEST_RUN" = 1 ]; then
    tempest_run
fi

if [ "$ALL" = 1 ]; then
    repo_setup
    undercloud
    overcloud_images
    register_nodes
    introspect_nodes
    overcloud_deploy
fi
