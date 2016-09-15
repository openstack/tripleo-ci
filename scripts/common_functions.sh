# Tripleo CI functions

# Revert a commit for tripleo ci
# $1 : project name e.g. nova
# $2 : hash id of commit to revert
# $3 : bug id of reason for revert (used to skip revert if found in commit
#      that triggers ci).
function temprevert(){
    # Before reverting check to ensure this isn't the related fix
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping temprevert because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$1
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
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping pin because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$1
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
    if git --git-dir=$TRIPLEO_ROOT/${ZUUL_PROJECT#*/}/.git log -1 | grep -iE "bug.*$3" ; then
        echo "Skipping cherrypick because bug fix $3 was found in git message."
        return 0
    fi

    pushd $TRIPLEO_ROOT/$PROJ_NAME
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
            # NOTE(pabelanger): Sadly, nbd module is missing from CentOS 7,
            # so we need to convert the image to raw format.  A fix for this
            # would be support raw instack images in our nightly builds.
            qemu-img convert -f qcow2 -O raw ${IMAGE} ${IMAGE/qcow2/raw}
            rm -rf ${IMAGE}
            sudo kpartx -avs ${IMAGE/qcow2/raw}
            # The qcow2 images may be a whole disk or single partition
            sudo mount /dev/mapper/loop0p1 $MOUNTDIR || sudo mount /dev/loop0 $MOUNTDIR
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
    sudo mv $MOUNTDIR/etc/resolv.conf{,_}
    echo -e "nameserver 10.1.8.10\nnameserver 8.8.8.8" | sudo dd of=$MOUNTDIR/etc/resolv.conf
    sudo yum remove -y galera
    sudo cp /etc/yum.repos.d/delorean* $MOUNTDIR/etc/yum.repos.d
    sudo rm -f $MOUNTDIR/etc/yum.repos.d/epel*
    sudo chroot $MOUNTDIR /bin/yum update -y
    sudo yum install -y galera
    sudo rm -f $MOUNTDIR/etc/yum.repos.d/delorean*
    sudo mv -f $MOUNTDIR/etc/resolv.conf{_,}

    case ${IMAGE##*.} in
        qcow2)
            # The yum update inside a chroot breaks selinux file contexts, fix them
            sudo chroot $MOUNTDIR setfiles /etc/selinux/targeted/contexts/files/file_contexts /
            sudo umount $MOUNTDIR
            sudo kpartx -dv ${IMAGE/qcow2/raw}
            qemu-img convert -f raw -O qcow2 ${IMAGE/qcow2/raw} ${IMAGE}
            rm -rf ${IMAGE/qcow2/raw}
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
                [[ "$PROJ" =~ diskimage-builder|python-tripleoclient ]] && return 1
                ;;
            overcloud-full.tar)
                [[ "$PROJ" =~ diskimage-builder|tripleo-image-elements|tripleo-puppet-elements|instack-undercloud|python-tripleoclient ]] && return 1
                ;;
            *)
                return 1
                ;;
        esac

    done
    return 0
}

function extract_logs(){
    local name=$1
    mkdir -p $WORKSPACE/logs/$name
    # Exclude journal files because they're large and not useful in a browser
    tar -C $WORKSPACE/logs/$name -xf $WORKSPACE/logs/$name.tar.xz var --exclude=journal
}

function postci(){
    set -x
    set +e
    stop_metric "tripleo.ci.total.seconds"
    if [ -e $TRIPLEO_ROOT/delorean/data/repos/ ] ; then
        # I'd like to tar up repos/current but tar'ed its about 8M it may be a
        # bit much for the log server, maybe when we are building less
        find $TRIPLEO_ROOT/delorean/data/repos -name "*.log" | XZ_OPT=-3 xargs tar -cJf $WORKSPACE/logs/delorean_repos.tar.xz
        extract_logs delorean_repos
    fi
    if [ "${SEED_IP:-}" != "" ] ; then
        SANITIZED_SEED_ADDRESS=$(sanitize_ip_address ${SEED_IP})
        # Generate extra state information from the running undercloud
        ssh root@${SEED_IP} 'export TRIPLEO_ROOT='"$TRIPLEO_ROOT""; $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh"

        # Get logs from the undercloud
        ssh root@${SEED_IP} $TARCMD > $WORKSPACE/logs/undercloud.tar.xz
        extract_logs undercloud

        # when we ran get_host_info.sh on the undercloud it left the output of nova list in /tmp for us
        for INSTANCE in $(ssh root@${SEED_IP} cat /tmp/nova-list.txt | grep ACTIVE | awk '{printf"%s=%s\n", $4, $12}') ; do
            IP=${INSTANCE//*=}
            SANITIZED_ADDRESS=$(sanitize_ip_address ${IP})
            NAME=${INSTANCE//=*}
            ssh $SSH_OPTIONS root@${SEED_IP} su jenkins -c \"scp $SSH_OPTIONS $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh heat-admin@${SANITIZED_ADDRESS}:/tmp\"
            timeout -s 15 -k 600 300 ssh $SSH_OPTIONS root@${SEED_IP} su jenkins -c \"ssh $SSH_OPTIONS heat-admin@$IP sudo /tmp/get_host_info.sh\"
            ssh $SSH_OPTIONS root@${SEED_IP} su jenkins -c \"ssh $SSH_OPTIONS heat-admin@$IP $TARCMD\" > $WORKSPACE/logs/${NAME}.tar.xz
            extract_logs $NAME
        done
        # post metrics
        scp $SSH_OPTIONS root@${SANITIZED_SEED_ADDRESS}:${METRICS_DATA_FILE} /tmp/seed-metrics
        cat /tmp/seed-metrics >> ${METRICS_DATA_FILE}
        # This spams the postci output with largely uninteresting trace output
        set +x
        echo -n 'Recording Heat deployment times...'
        # We're only interested in the resources that take the most time
        long_times=/tmp/long-deploy-times.log
        head -n 50 $WORKSPACE/logs/undercloud/var/log/heat-deploy-times.log > $long_times
        while read line; do
            # $line should look like "ResourceName 123.0", so concatenating all
            # of this together we should end up with a call that looks like:
            # record_metric tripleo.overcloud.ha.resources.ResourceName 123.0
            record_metric tripleo.overcloud.${TOCI_JOBTYPE}.resources.${line}
        done <$long_times
        echo 'Finished'
        set -x
        metrics_to_graphite "23.253.94.71" #Dan's temp graphite server
        if [ -z "${LEAVE_RUNNING:-}" ] && [ -n "${HOST_IP:-}" ] ; then
            destroy_vms &> $WORKSPACE/logs/destroy_vms.log
        fi
    elif [ "$OSINFRA" = "1" ] ; then
        local i=2
        sudo $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh
        $TARCMD > $WORKSPACE/logs/primary_node.tar.xz
        # Extract /var/log for easy viewing
        tar xf $WORKSPACE/logs/primary_node.tar.xz -C $WORKSPACE/logs/ var/log
        for ip in $(cat /etc/nodepool/sub_nodes_private); do
            mkdir $WORKSPACE/logs/subnode-$i/
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                sudo $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                $TARCMD > $WORKSPACE/logs/subnode-$i/subnode-$i.tar.xz
            # Extract /var/log for easy viewing
            tar xf $WORKSPACE/logs/subnode-$i/subnode-$i.tar.xz -C $WORKSPACE/logs/subnode-$i/ var/log
            # These files are causing the publish logs ansible
            # task to fail with an rsync error:
            # "symlink has no referent"
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                sudo rm -f /etc/sahara/rootwrap.d/sahara.filters
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                sudo rm -f /etc/cinder/rootwrap.d/os-brick.filters
            let i+=1
        done
    fi

    sudo chown -R $USER $WORKSPACE
    # Make sure zuuls log gathering can read everything in the $WORKSPACE, it also contains a
    # link to ml2_conf.ini so this also need to be made read only
    sudo find /etc/neutron/plugins/ml2/ml2_conf.ini $WORKSPACE -type f | sudo xargs chmod 644
    return 0
}

function delorean_build_and_serve {
    DELOREAN_BUILD_REFS=
    for PROJFULLREF in $ZUUL_CHANGES ; do
        PROJ=$(filterref $PROJFULLREF)
        # If ci is being run for a change to ci its ok not to have a ci produced repository
        if [ "$PROJ" == "tripleo-ci" ] ; then
            mkdir -p $TRIPLEO_ROOT/delorean/data/repos/current
            touch $TRIPLEO_ROOT/delorean/data/repos/current/delorean-ci.repo
        else
            # Note we only add the project once for it to be built
            if ! echo $DELOREAN_BUILD_REFS | egrep "( |^)$PROJ( |$)"; then
                DELOREAN_BUILD_REFS="$DELOREAN_BUILD_REFS $PROJ"
            fi
        fi
    done

    # Build packages
    if [ -n "$DELOREAN_BUILD_REFS" ] ; then
        $TRIPLEO_ROOT/tripleo-ci/scripts/tripleo.sh --delorean-build $DELOREAN_BUILD_REFS
    fi

    # kill the http server if its already running
    ps -ef | grep -i python | grep SimpleHTTPServer | awk '{print $2}' | xargs --no-run-if-empty kill -9 || true
    pushd $TRIPLEO_ROOT/delorean/data/repos
    sudo iptables -I INPUT -p tcp --dport 8766 -i eth1 -j ACCEPT
    python -m SimpleHTTPServer 8766 1>$WORKSPACE/logs/yum_mirror.log 2>$WORKSPACE/logs/yum_mirror_error.log &
    popd
}

function dummy_ci_repo {
    # If we have no ZUUL_CHANGES then this is a periodic job, we wont be
    # building a ci repo, create a dummy one.
    if [ -z "${ZUUL_CHANGES:-}" ] ; then
        ZUUL_CHANGES=${ZUUL_CHANGES:-}
        mkdir -p $TRIPLEO_ROOT/delorean/data/repos/current
        touch $TRIPLEO_ROOT/delorean/data/repos/current/delorean-ci.repo
    fi
    ZUUL_CHANGES=${ZUUL_CHANGES//^/ }
}

function layer_ci_repo {
    # Find the path to the trunk repository used
    TRUNKREPOUSED=$(grep -Eo "[0-9a-z]{2}/[0-9a-z]{2}/[0-9a-z]{40}_[0-9a-z]+" /etc/yum.repos.d/delorean.repo)

    # Layer the ci repository on top of it
    sudo wget http://$MY_IP:8766/current/delorean-ci.repo -O /etc/yum.repos.d/delorean-ci.repo
    # rewrite the baseurl in delorean-ci.repo as its currently pointing a http://trunk.rdoproject.org/..
    sudo sed -i -e "s%baseurl=.*%baseurl=http://$MY_IP:8766/current/%" /etc/yum.repos.d/delorean-ci.repo
    sudo sed -i -e 's%priority=.*%priority=1%' /etc/yum.repos.d/delorean-ci.repo
}


function echo_vars_to_deploy_env {
    for VAR in CENTOS_MIRROR http_proxy INTROSPECT MY_IP no_proxy NODECOUNT OVERCLOUD_DEPLOY_ARGS OVERCLOUD_UPDATE_ARGS PACEMAKER SSH_OPTIONS STABLE_RELEASE TRIPLEO_ROOT TRIPLEO_SH_ARGS NETISO_V4 NETISO_V6 TOCI_JOBTYPE UNDERCLOUD_SSL RUN_TEMPEST_TESTS RUN_PING_TEST JOB_NAME OVB UNDERCLOUD_IDEMPOTENT MULTINODE CONTROLLER_HOSTS COMPUTE_HOSTS SUBNODES_SSH_KEY TEST_OVERCLOUD_DELETE OVERCLOUD OSINFRA UNDERCLOUD_SANITY_CHECK PINGTEST_TEMPLATE; do
        echo "export $VAR=\"${!VAR}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
}


# Enclose IPv6 addresses in brackets.
# This is needed for scp command where the first column of IPv6 address gets
# interpreted as the separator between address and path otherwise.
# $1 : IP address to sanitize
function sanitize_ip_address {
    ip=$1
    if [[ $ip =~ .*:.* ]]; then
        echo \[$ip\]
    else
        echo $ip
    fi
}
