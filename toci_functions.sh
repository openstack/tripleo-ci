#!/usr/bin/env bash

get_get_repo(){
    CACHEDIR=$TOCI_WORKING_DIR/${1/[^\/]*\//}
    if [ ! -e $CACHEDIR ] ; then
        git clone https://github.com/$1.git $CACHEDIR
    else
        pushd $CACHEDIR
        # Repositories in $TOCI_WORKING_DIR aren't updated but we do fetch origin
        # this fetch will make it a little more obvious to a user that upstream has changed
        git fetch
        popd
    fi
    repo_basename=${1#*/}
    apply_patches ${repo_basename} ${repo_basename}*
}

ssh_noprompt(){
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET -o PasswordAuthentication=no $@
}

scp_noprompt(){
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET -o PasswordAuthentication=no $@
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
    ssh_noprompt $1@$2 "( set -x ; ps -ef ; df -h ; uptime ; sudo netstat -lpn ; sudo iptables-save ; sudo ovs-vsctl show ; ip addr ; dpkg -l || rpm -qa) > /var/log/host_info.txt 2>&1 ;
                                     sudo tar -czf - --exclude=udev/hwdb.bin --exclude=selinux/targeted /var/log /etc || true" > $TOCI_LOG_DIR/$2.tgz
}

# On Exit write relevant toci env to a rc file
get_tocienv(){
    declare | grep -e "^PATH=" -e "^http.*proxy" -e "^TOCI_" -e '^DIB_' -e 'CLOUD_ADMIN_PASSWORD' | sed  -e 's/^/export /g' > $TOCI_WORKING_DIR/toci_env
    # Some IP we don't want to proxy
    echo 'export no_proxy=$($TOCI_WORKING_DIR/tripleo-incubator/scripts/get-vm-ip seed),192.0.2.2,192.0.2.5,192.0.2.6,192.0.2.7,192.0.2.8' >> $TOCI_WORKING_DIR/toci_env
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

ERROR(){
    echo $@
    exit 1
}

# Check for some dependencies
function check_dependencies(){
  commands=("patch" "make" "tar" "ssh" "arp" "busybox")
  for cmd in "${commands[@]}"; do
    which "${cmd}" > /dev/null 2>&1 || ERROR "$cmd: command not found"
  done

  python -c 'import yaml' > /dev/null 2>&1 || ERROR "Please install PyYAML"

  # TODO : why do I need to do this, heat client complains without it
  python -c 'import keystoneclient' || ERROR "Please install python-keystoneclient"
  export PYTHONPATH=$(python -c 'import keystoneclient; print keystoneclient.__file__.rsplit("/", 1)[0]'):$PYTHONPATH
}
