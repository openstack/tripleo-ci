#!/usr/bin/env bash

get_get_repo(){
    CACHDIR=$TOCI_CACHE_DIR/${1/[^\/]*\//}
    if [ ! -e $CACHDIR ] ; then
        git clone https://github.com/$1.git $CACHDIR
    else
        pushd $CACHDIR
        git fetch
        git reset --hard origin/master
        popd
    fi
    cp -r $CACHDIR $TOCI_WORKING_DIR/${1/[^\/]*\//}
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
        eval "$@" && return 0 || true
        sleep $SLEEPTIME
    done
    return 1
}

apply_patches(){
    pushd $TOCI_WORKING_DIR/$1
    if [ -d "$TOCI_SOURCE_DIR/patches/" ]; then
      for PATCH in $(find $TOCI_SOURCE_DIR/patches/ -name "$2") ; do
          patch -p1 -N < $PATCH || echo Error : could not apply $PATCH >> $TOCI_LOG_DIR/error-applying-patches.log
      done
    fi
    popd
}

mark_time(){
    echo $(date) : $@
}

# Get config files and logs from a host for debuging purposes
get_state_from_host(){
    scp_noprompt root@$SEED_IP:/var/log/first-boot.d.log $TOCI_LOG_DIR/first-boot.d.log || true
    ssh_noprompt root@$SEED_IP "( set -x ; ps -ef ; df -h ; uptime ; netstat -lpn ; iptables-save ; brctl show ; ip addr ; dpkg -l || rpm -qa) > /var/log/host_info.txt 2>&1 ;
                                     tar -czf - /var/log /etc || true" > $TOCI_LOG_DIR/bootstraplogs.tgz
}

# Sends a message to a freenode irc channel
send_irc(){
    exec 3<>/dev/tcp/irc.freenode.net/6667

    CHANNEL=$1
    shift
    MESSAGE=$@

    echo "Nick toci-bot" >&3
    echo "User toci-bot -i * : hi" >&3
    sleep 2
    echo "JOIN #$CHANNEL" >&3
    echo "PRIVMSG #$CHANNEL :$@" >&3
    echo "QUIT" >&3

    cat <&3 > /dev/null
}
