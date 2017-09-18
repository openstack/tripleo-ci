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
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"
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
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"
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
    DELOREAN_BUILD_REFS="${DELOREAN_BUILD_REFS:-} $1"

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
    sudo mv $MOUNTDIR/etc/resolv.conf{,_}
    if [ "$CA_SERVER" == "1" ] ; then
        # NOTE(jaosorior): This IP is hardcoded for the FreeIPA server (the CA).
        echo -e "nameserver 192.168.24.250\nnameserver 8.8.8.8" | sudo dd of=$MOUNTDIR/etc/resolv.conf
    else
        echo -e "nameserver 10.1.8.10\nnameserver 8.8.8.8" | sudo dd of=$MOUNTDIR/etc/resolv.conf
    fi
    sudo cp /etc/yum.repos.d/delorean* $MOUNTDIR/etc/yum.repos.d
    sudo rm -f $MOUNTDIR/etc/yum.repos.d/epel*
    sudo chroot $MOUNTDIR /bin/yum clean all
    sudo chroot $MOUNTDIR /bin/yum update -y
    sudo rm -f $MOUNTDIR/etc/yum.repos.d/delorean*
    sudo mv -f $MOUNTDIR/etc/resolv.conf{_,}

    case ${IMAGE##*.} in
        qcow2)
            # The yum update inside a chroot breaks selinux file contexts, fix them
            sudo chroot $MOUNTDIR setfiles /etc/selinux/targeted/contexts/files/file_contexts /
            sudo umount $MOUNTDIR
            sudo kpartx -dv ${IMAGE/qcow2/raw}
            qemu-img convert -c -f raw -O qcow2 ${IMAGE/qcow2/raw} ${IMAGE}
            sudo rm -rf ${IMAGE/qcow2/raw}
            sudo losetup -d /dev/loop0
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

    # The updates job already takes a long time, always use cache for it
    [ -n "$OVERCLOUD_UPDATE_ARGS" ] && return 0

    CACHEDOBJECT=$1

    for PROJFULLREF in $ZUUL_CHANGES ; do
        PROJ=$(filterref $PROJFULLREF)

        case $CACHEDOBJECT in
            ${UNDERCLOUD_VM_NAME}.qcow2)
                [[ "$PROJ" =~ instack-undercloud|diskimage-builder|tripleo-image-elements|tripleo-puppet-elements ]] && return 1
                ;;
            ipa_images.tar)
                [[ "$PROJ" =~ diskimage-builder|python-tripleoclient|tripleo-common|tripleo-image-elements ]] && return 1
                ;;
            overcloud-full.tar)
                [[ "$PROJ" =~ diskimage-builder|tripleo-image-elements|tripleo-puppet-elements|instack-undercloud|python-tripleoclient|tripleo-common ]] && return 1
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
    local logs_tar="$WORKSPACE/logs/$name.tar.xz"

    if [[ -f $logs_tar ]]; then
        # Exclude journal files because they're large and not useful in a browser
        tar -C $WORKSPACE/logs/$name -xf $logs_tar var --exclude=journal
    else
        echo "$logs_tar doesn't exist. Nothing to untar"
    fi
}

function postci(){
    local exit_val=${1:-0}
    set -x
    set +e
    stop_metric "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.ci.total.seconds"
    if [[ "$POSTCI" == "0" ]]; then
        sudo chown -R $USER $WORKSPACE
        sudo iptables -I INPUT -p tcp -j ACCEPT
        return 0
    fi
    start_metric "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.postci.seconds"
    if [ -e $TRIPLEO_ROOT/delorean/data/repos/ ] ; then
        # I'd like to tar up repos/current but tar'ed its about 8M it may be a
        # bit much for the log server, maybe when we are building less
        find $TRIPLEO_ROOT/delorean/data/repos -name "*.log" | XZ_OPT=-3 xargs tar -cJf $WORKSPACE/logs/delorean_repos.tar.xz
        extract_logs delorean_repos
    fi

    # Persist the deploy.env, as it can help with debugging and local testing
    cp $TRIPLEO_ROOT/tripleo-ci/deploy.env $WORKSPACE/logs/

    # Generate extra state information from the running undercloud
    sudo -E $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh
    sudo -E $TRIPLEO_ROOT/tripleo-ci/scripts/get_docker_logs.sh
    eval $JLOGCMD

    if [ "$OVB" == "1" ] ; then
        # Get logs from the undercloud
        # Log collection takes a while.  Let's start these in the background
        # so they can run in parallel, then we'll wait for them to complete
        # after they're all running.
        (
            $TARCMD $HOME/*.log > $WORKSPACE/logs/undercloud.tar.xz
            extract_logs undercloud
        ) &

        # when we ran get_host_info.sh on the undercloud it left the output of nova list in /tmp for us
        for INSTANCE in $(cat /tmp/nova-list.txt | grep ACTIVE | awk '{printf"%s=%s\n", $4, $12}') ; do
            IP=${INSTANCE//*=}
            SANITIZED_ADDRESS=$(sanitize_ip_address ${IP})
            NAME=${INSTANCE//=*}
            (
                scp $SSH_OPTIONS $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh heat-admin@${SANITIZED_ADDRESS}:/tmp
                scp $SSH_OPTIONS $TRIPLEO_ROOT/tripleo-ci/scripts/get_docker_logs.sh heat-admin@${SANITIZED_ADDRESS}:/tmp
                timeout -s 15 -k 600 300 ssh $SSH_OPTIONS heat-admin@$IP sudo /tmp/get_host_info.sh
                timeout -s 15 -k 600 300 ssh $SSH_OPTIONS heat-admin@$IP sudo /tmp/get_docker_logs.sh
                ssh $SSH_OPTIONS heat-admin@$IP $JLOGCMD
                ssh $SSH_OPTIONS heat-admin@$IP $TARCMD > $WORKSPACE/logs/${NAME}.tar.xz
                extract_logs $NAME
            ) &
        done
        # Wait for the commands we started in the background to complete
        wait
        # This spams the postci output with largely uninteresting trace output
        set +x
        echo -n 'Recording Heat deployment times...'
        # We can't record all of the Heat deployment times because a number of
        # them include IDs that change every run, which makes them pretty
        # useless as Graphite metrics.  However, there are some important ones
        # we do want to record over time, so explicitly capture those.
        captured_deploy_times=/tmp/captured-deploy-times.log
        # Make sure there is a trailing space after all the names so they don't
        # match resources that have ids appended.
        egrep 'overcloud |AllNodesDeploySteps |ControllerDeployment_Step. |ComputeDeployment_Step. |CephStorageDeploymentStep. |Controller |CephStorage |Compute |ServiceChain |NetworkDeployment |UpdateDeployment ' $WORKSPACE/logs/undercloud/var/log/heat-deploy-times.log > $captured_deploy_times
        while read line; do
            # $line should look like "ResourceName 123.0", so concatenating all
            # of this together we should end up with a call that looks like:
            # record_metric tripleo.master.ha.overcloud.resources.ResourceName 123.0
            record_metric tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.overcloud.resources.${line}
        done <$captured_deploy_times
        echo 'Finished'
        set -x
        stop_metric "tripleo.${STABLE_RELEASE:-master}.${TOCI_JOBTYPE}.postci.seconds"
        # post metrics
        if [ $exit_val -eq 0 ]; then
            metrics_to_graphite "66.187.229.172" # Graphite server in rh1
        fi
    elif [ "$OSINFRA" = "1" ] ; then
        local i=2
        $TARCMD $HOME/*.log > $WORKSPACE/logs/primary_node.tar.xz
        # Extract /var/log for easy viewing
        tar xf $WORKSPACE/logs/primary_node.tar.xz -C $WORKSPACE/logs/ var/log etc --exclude=var/log/journal
        # Clean out symlinks, because these seem to break reporting job results
        find $WORKSPACE/logs/etc -type l | xargs -t rm -f
        for ip in $(cat /etc/nodepool/sub_nodes_private); do
            mkdir $WORKSPACE/logs/subnode-$i/
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                sudo $TRIPLEO_ROOT/tripleo-ci/scripts/get_host_info.sh
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                sudo $TRIPLEO_ROOT/tripleo-ci/scripts/get_docker_logs.sh
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip $JLOGCMD
            ssh $SSH_OPTIONS -i /etc/nodepool/id_rsa $ip \
                $TARCMD > $WORKSPACE/logs/subnode-$i/subnode-$i.tar.xz
            # Extract /var/log and /etc for easy viewing
            tar xf $WORKSPACE/logs/subnode-$i/subnode-$i.tar.xz -C $WORKSPACE/logs/subnode-$i/ var/log etc --exclude=var/log/journal
            # Clean out symlinks, because these seem to break reporting job results
            find $WORKSPACE/logs/subnode-$i/etc -type l | xargs -t rm -f
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
    sudo find $WORKSPACE -type d -exec chmod 755 {} \;
    # Make sure zuuls log gathering can read everything in the $WORKSPACE, it also contains a
    # link to ml2_conf.ini so this also need to be made read only
    sudo find /etc/neutron/plugins/ml2/ml2_conf.ini $WORKSPACE -type f | sudo xargs chmod 644
    # Allow all ports before we finish up.  This should avoid
    # https://bugs.launchpad.net/tripleo/+bug/1649742 which we've now spent far
    # too much time debugging.  It's currently only happening on the mitaka
    # branch anyway, so once that branch goes EOL we can probably remove this.
    sudo iptables -I INPUT -p tcp -j ACCEPT

    # record the size of the logs directory
    # -L, --dereference     dereference all symbolic links
    du -L -ch $WORKSPACE/logs/* | sort -rh | head -n 200 &> $WORKSPACE/logs/log-size.txt || true

    return 0
}

function delorean_build_and_serve {
    DELOREAN_BUILD_REFS=${DELOREAN_BUILD_REFS:-}
    for PROJFULLREF in $ZUUL_CHANGES ; do
        PROJ=$(filterref $PROJFULLREF)
        # If ci is being run for a change to ci its ok not to have a ci produced repository
        excluded_proj="tripleo-ci tripleo-quickstart tripleo-quickstart-extras puppet-openstack-integration grenade"
        if [[ " $excluded_proj " =~ " $PROJ " ]]; then
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
    # rewrite the baseurl in delorean-ci.repo as its currently pointing a https://trunk.rdoproject.org/..
    sudo sed -i -e "s%baseurl=.*%baseurl=http://$MY_IP:8766/current/%" /etc/yum.repos.d/delorean-ci.repo
    sudo sed -i -e 's%priority=.*%priority=1%' /etc/yum.repos.d/delorean-ci.repo
}


function echo_vars_to_deploy_env {
    CALLER=$(caller)
    echo "# Written via echo_vars_to_deploy_env from $CALLER" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    for VAR in CENTOS_MIRROR http_proxy INTROSPECT MY_IP no_proxy NODECOUNT OVERCLOUD_DEPLOY_ARGS OVERCLOUD_UPDATE_ARGS PACEMAKER SSH_OPTIONS STABLE_RELEASE TRIPLEO_ROOT TRIPLEO_SH_ARGS NETISO_V4 NETISO_V6 TOCI_JOBTYPE UNDERCLOUD_SSL UNDERCLOUD_HEAT_CONVERGENCE RUN_TEMPEST_TESTS RUN_PING_TEST JOB_NAME OVB UNDERCLOUD_IDEMPOTENT MULTINODE CONTROLLER_HOSTS COMPUTE_HOSTS SUBNODES_SSH_KEY TEST_OVERCLOUD_DELETE OVERCLOUD OSINFRA UNDERCLOUD_SANITY_CHECK OVERCLOUD_PINGTEST_ARGS FEATURE_BRANCH OVERCLOUD_ROLES UPGRADE_RELEASE OVERCLOUD_MAJOR_UPGRADE MAJOR_UPGRADE UNDERCLOUD_MAJOR_UPGRADE CA_SERVER UNDERCLOUD_TELEMETRY UNDERCLOUD_UI UNDERCLOUD_VALIDATIONS PREDICTABLE_PLACEMENT OPSTOOLS_REPO_ENABLED UPGRADE_ENV UNDERCLOUD_CONTAINERS BOOTSTRAP_SUBNODES_MINIMAL MULTINODE_ENV_PATH; do
        echo "export $VAR=\"${!VAR}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
    for role in $OVERCLOUD_ROLES; do
        eval hosts=\${${role}_hosts}
        echo "export ${role}_hosts=\"${hosts}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
}

# Same function as above, but for oooq jobs (less variables defined)
function echo_vars_to_deploy_env_oooq {
    CALLER=$(caller)
    echo "# Written via echo_vars_to_deploy_env from $CALLER" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    for VAR in CENTOS_MIRROR http_proxy MY_IP no_proxy NODECOUNT SSH_OPTIONS STABLE_RELEASE TRIPLEO_ROOT TOCI_JOBTYPE JOB_NAME SUBNODES_SSH_KEY FEATURE_BRANCH BOOTSTRAP_SUBNODES_MINIMAL; do
        echo "export $VAR=\"${!VAR}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
    # TODO(gcerami) uncomment this code if 3nodes jobs are implemented before the bootstrap role
    # in quickstart. If the bootstrap role is implemented first, this function can be completely
    # removed
    #for role in $OVERCLOUD_ROLES; do
    #    eval hosts=\${${role}_hosts}
    #    echo "export ${role}_hosts=\"${hosts}\"" >> $TRIPLEO_ROOT/tripleo-ci/deploy.env
    #done
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

function get_image {
    local img="$1"
    http_proxy= wget -T 60 --tries=3 --progress=dot:mega http://$MIRRORSERVER/builds/current-tripleo/$img -O $img || {
        wget -T 60 --tries=3 --progress=dot:mega http://66.187.229.139/builds/current-tripleo/$img -O $img
    }
}


function prepare_images_oooq {
    get_image ipa_images.tar
    get_image overcloud-full.tar
    tar -xvf overcloud-full.tar
    tar -xvf ipa_images.tar
    update_image $PWD/ironic-python-agent.initramfs
    update_image $PWD/overcloud-full.qcow2
    cp ironic-python-agent.* ~/
    cp overcloud-full.qcow2 overcloud-full.initrd overcloud-full.vmlinuz ~/
    rm -f overcloud-full.tar ipa_images.tar
}

function subnodes_scp_deploy_env {
    for ip in $(cat /etc/nodepool/sub_nodes); do
        sanitized_address=$(sanitize_ip_address $ip)
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo mkdir -p $TRIPLEO_ROOT/tripleo-ci
        scp $SSH_OPTIONS -i /etc/nodepool/id_rsa \
            $TRIPLEO_ROOT/tripleo-ci/deploy.env ${sanitized_address}:
        ssh $SSH_OPTIONS -tt -i /etc/nodepool/id_rsa $ip \
            sudo cp deploy.env $TRIPLEO_ROOT/tripleo-ci/deploy.env
    done
}

function stop_dstat {
	ps axjf | grep bin/dstat | grep -v grep | awk '{print $2;}' | sudo xargs -t -n 1 -r kill
}

function item_in_array () {
    local item
    for item in "${@:2}"; do
        if [[ "$item" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}
