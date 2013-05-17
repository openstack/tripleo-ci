
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
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET $@
}

scp_noprompt(){
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET $@
}

wait_for(){
    LOOPS=$1
    SLEEPTIME=$2
    shift ; shift
    i=0
    while [ $i -lt $LOOPS ] ; do
        i=$((i + 1))
        $@ && return 0 || true
        sleep $SLEEPTIME
    done
    return 1
}
