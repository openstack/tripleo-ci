
get_get_repo(){
    CACHDIR=$TOCI_CACHE_DIR/${1/\//_}
    if [ ! -e $CACHDIR ] ; then
        git clone https://github.com/$1.git $CACHDIR
    else
        cd $CACHDIR
        git fetch
        git reset --hard origin/master
    fi
    cp -r $CACHDIR $TOCI_WORKING_DIR/${1/\//_}
}

ssh_noprompt(){
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $@
}

scp_noprompt(){
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $@
}

wait_for(){
    for x in {0..60} ; do
        $@ && return 0 || true
        sleep 10
    done
    return 1
}
