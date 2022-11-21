#!/bin/bash
# Tripleo CI functions

# Revert a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to revert
# $3 : bug id of reason for revert (used to skip revert if found in commit
#      that triggers ci).
function temprevert {
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping temprevert because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$1
    # Abort on fail so  we're not left in a conflict state
    git revert --no-edit $2 || git revert --abort || true
    popd
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"
}

# Pin to a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to pin too
# $3 : bug id of reason for the pin (used to skip revert if found in commit
#      that triggers ci).
function pin {
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping pin because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$1
    git reset --hard $2
    popd
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"
}

# Cherry-pick a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : Gerrit refspec to cherry pick
# $3 : bug id of reason for the cherry pick (used to skip cherry pick if found
#      in commit that triggers ci).
function cherrypick {
    local PROJ_NAME=$1
    local REFSPEC=$2

    # Before cherrypicking check to ensure this isn't the related fix
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping cherrypick because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$PROJ_NAME
    git fetch https://review.opendev.org/openstack/$PROJ_NAME "$REFSPEC"
    # Abort on fail so  we're not left in a conflict state
    git cherry-pick FETCH_HEAD || git cherry-pick --abort
    popd
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"

    # Export a DIB_REPOREF variable as well
    export DIB_REPOREF_${PROJ_NAME//-/_}=$REFSPEC

}

# echo's out a project name from a ref
# $1 : e.g. openstack/nova:master:refs/changes/87/64787/3 returns nova
function filterref {
    PROJ=${1%%:*}
    PROJ=${PROJ##*/}
    echo $PROJ
}

function layer_ci_repo {
    # Find the path to the trunk repository used
    TRUNKREPOUSED=$(grep -Eo "[0-9a-z]{2}/[0-9a-z]{2}/[0-9a-z]{40}_[0-9a-z]+" /etc/yum.repos.d/delorean.repo)

    # Layer the ci repository on top of it
    sudo wget http://$MY_IP:8766/current/delorean-ci.repo -O /etc/yum.repos.d/delorean-ci.repo
    # rewrite the baseurl in delorean-ci.repo as its currently pointing a https://trunk.rdoproject.org/..
    sudo sed -i -e "s%baseurl=.*%baseurl=http://$MY_IP:8766/current/%" /etc/yum.repos.d/delorean-ci.repo
    sudo sed -i -e 's%priority=.*%priority=1%' /etc/yum.repos.d/delorean-ci.repo
}


function echo_vars_to_deploy_env {
    CALLER=$(caller)
    echo "# Written via echo_vars_to_deploy_env from $CALLER" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    for VAR in NODEPOOL_CBS_CENTOS_PROXY NODEPOOL_CENTOS_MIRROR http_proxy INTROSPECT MY_IP no_proxy NODECOUNT OVERCLOUD_DEPLOY_ARGS OVERCLOUD_UPDATE_ARGS PACEMAKER SSH_OPTIONS STABLE_RELEASE TRIPLEO_ROOT TRIPLEO_SH_ARGS NETISO_V4 NETISO_V6 TOCI_JOBTYPE UNDERCLOUD_SSL UNDERCLOUD_HEAT_CONVERGENCE RUN_TEMPEST_TESTS JOB_NAME OVB UNDERCLOUD_IDEMPOTENT MULTINODE CONTROLLER_HOSTS COMPUTE_HOSTS SUBNODES_SSH_KEY TEST_OVERCLOUD_DELETE OVERCLOUD OSINFRA UNDERCLOUD_SANITY_CHECK FEATURE_BRANCH OVERCLOUD_ROLES UPGRADE_RELEASE OVERCLOUD_MAJOR_UPGRADE MAJOR_UPGRADE UNDERCLOUD_MAJOR_UPGRADE CA_SERVER UNDERCLOUD_TELEMETRY UNDERCLOUD_UI UNDERCLOUD_VALIDATIONS PREDICTABLE_PLACEMENT OPSTOOLS_REPO_ENABLED UPGRADE_ENV BOOTSTRAP_SUBNODES_MINIMAL MULTINODE_ENV_PATH; do
        if [ -n "${!VAR:+x}" ]; then
            echo "export $VAR=\"${!VAR}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
        fi
    done
    for role in $OVERCLOUD_ROLES; do
        eval hosts=\${${role}_hosts}
        echo "export ${role}_hosts=\"${hosts}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
}
