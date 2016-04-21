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

# Mount a qcow image, copy in the delorean repositories and update the packages
function update_image(){
    IMAGE=$1
    MOUNTDIR=$(mktemp -d)
    case ${IMAGE##*.} in
        qcow2)
            sudo modprobe nbd max_part=8
            sudo qemu-nbd --connect=/dev/nbd0 $IMAGE
            sudo mount -o seclabel /dev/nbd0p1 $MOUNTDIR
            ;;
        initramfs)
            pushd $MOUNTDIR
            gunzip -c $IMAGE | sudo cpio -i
            ;;
    esac

    # Overwrite resources specific to the environment running this test
    # instack-undercloud does this, but for cached images it wont be correct
    sudo test -f $MOUNTDIR/root/.ssh/authorized_keys && sudo cp ~/.ssh/authorized_keys $MOUNTDIR/root/.ssh/authorized_keys
    sudo test -f $MOUNTDIR/home/stack/instackenv.json && sudo cp $TE_DATAFILE $MOUNTDIR/home/stack/instackenv.json

    # Update the installed packages on the image
    sudo cp /etc/yum.repos.d/delorean* $MOUNTDIR/etc/yum.repos.d
    sudo chroot $MOUNTDIR /bin/yum update -y
    sudo rm -f $MOUNTDIR/etc/yum.repos.d/delorean*

    case ${IMAGE##*.} in
        qcow2)
            # The yum update inside a chroot breaks selinux file contexts, fix them
            sudo chroot $MOUNTDIR setfiles /etc/selinux/targeted/contexts/files/file_contexts /
            sudo umount $MOUNTDIR
            sudo qemu-nbd --disconnect /dev/nbd0
            ;;
        initramfs)
            sudo find . -print | sudo cpio -o -H newc | gzip > $IMAGE
            popd
            ;;
    esac
    sudo rm -rf $MOUNTDIR
}

# Decide if a particular cached artifact can be used in this CI test
# Takes a single argument representing the name of the artifact being checked.
function canusecache(){
    # If we are uploading to the cache then we shouldn't use it
    [ "$CACHEUPLOAD" == 1 ] && return 1

    # We're not currently caching artifacts for stable jobs
    [ -n "$STABLE_RELEASE" ] && return 1

    CACHEDOBJECT=$1

    for PROJFULLREF in $ZUUL_CHANGES ; do
        PROJ=$(filterref $PROJFULLREF)

        case $CACHEDOBJECT in
            ${UNDERCLOUD_VM_NAME}.qcow2)
                [[ "$PROJ" =~ instack-undercloud|diskimage-builder|tripleo-image-elements|tripleo-puppet-elements ]] && return 1
                ;;
            ipa_images.tar)
                [[ "$PROJ" =~ diskimage-builder ]] && return 1
                ;;
        esac

    done
    return 0
}
