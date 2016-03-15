# Tripleo CI functions

# Revert a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to revert
# $3 : bug id of reason for revert (used to skip revert if found in commit
#      that triggers ci).
function temprevert(){
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=/opt/stack/new/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping temprevert because bug fix $3 was found in git message."
        return 0
    fi

    pushd /opt/stack/new/$1
    # Abort on fail so  we're not left in a conflict state
    git revert --no-edit $2 || git revert --abort || true
    popd
}

# Pin to a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to pin too
# $3 : bug id of reason for the pin (used to skip revert if found in commit
#      that triggers ci).
function pin(){
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=/opt/stack/new/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping pin because bug fix $3 was found in git message."
        return 0
    fi

    pushd /opt/stack/new/$1
    git reset --hard $2
    popd
}

# Cherry-pick a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : Gerrit refspec to cherry pick
# $3 : bug id of reason for the cherry pick (used to skip cherry pick if found
#      in commit that triggers ci).
function cherrypick(){
    local PROJ_NAME=$1
    local REFSPEC=$2

    # Before cherrypicking check to ensure this isn't the related fix
    if git --git-dir=/opt/stack/new/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping cherrypick because bug fix $3 was found in git message."
        return 0
    fi

    pushd /opt/stack/new/$PROJ_NAME
    git fetch https://review.openstack.org/openstack/$PROJ_NAME "$REFSPEC"
    # Abort on fail so  we're not left in a conflict state
    git cherry-pick FETCH_HEAD || git cherry-pick --abort
    popd

    # Export a DIB_REPOREF variable as well
    export DIB_REPOREF_${PROJ_NAME//-/_}=$REFSPEC

}

# echo's out a project name from a ref
# $1 : e.g. openstack/nova:master:refs/changes/87/64787/3 returns nova
function filterref(){
    PROJ=${1%%:*}
    PROJ=${PROJ##*/}
    echo $PROJ
}
