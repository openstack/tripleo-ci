toci
====


Description
-----------

TripleO CI test framework.

By default it uses bm_poseur nodes. Options exist to deploy on real hardware as well.

Configuration
-------------

edit ~/.toci and add values for
```bash
TOCI_UPLOAD=0
TOCI_RESULTS_SERVER=1.2.3.4
TOCI_CLEANUP=1
TOCI_REMOVE=1
TOCI_GIT_CHECKOUT=1
export http_proxy=http://1.2.3.4:3128
export https_proxy=http://1.2.3.4:3128

# set the arch (defaults to i386)
TOCI_ARCH="x86_64"


# The following options can be used w/ real hardware
# Space delimited, aligned in order
#export TOCI_MACS="12:34:56:78:9A:E1 12:34:56:78:9A:E2"
#export TOCI_PM_DRIVER="nova.virt.baremetal.ipmi.IPMI"
#export TOCI_PM_IPS="10.0.0.1 10.0.0.2"
#export TOCI_PM_USERS="user1 user2"
#export TOCI_PM_PASSWORDS="user1 user2"
```

Then run updated_launch.sh (this does a git update) or you can use toci.sh
directly to start the setup and tests.

Using Toci to setup a dev environment
-------------------------------------

I usualy do this a root, in theory it will also work as a non privilaged user.

    $ git clone https://github.com/toci-dev/toci.git
    $ cd toci
    $ vi ~/.toci # Will work without a proxy but a lot slower
    export http_proxy=http://192.168.1.104:8080
    export https_proxy=http://192.168.1.104:8080

To run toci here is your command, were setting
TOCI_REMOVE=0 TOCI_CLEANUP=0 so that it doesn't clean up after itself, so befor each run the virsh commands do the cleanup if there are any VM's defined

    $ for NAME in $(virsh list --name --all ); do virsh destroy $NAME ; virsh undefine --remove-all-storage $NAME ; done
    $ for NAME in $(virsh vol-list default | grep /var/ | awk '{print $1}' ); do virsh vol-delete --pool default $NAME ; done
    $ TOCI_REMOVE=0 TOCI_CLEANUP=0 ./toci.sh

Toci will start with a line outputing the working and log directories e.g.
Starting run Wed  3 Jul 11:46:39 IST 2013 ( /tmp/toci_working_g1Eb2NO /tmp/toci_logs_nGnrhLN )

On success it echo's 0 to the terminal or 1 on error

Once it ran successfully you should have a running seed node that can be used to start images. also /tmp/toci_working_* can be used as a work directory from which to build/start images e.g.

    $ . toci_env ; export ELEMENTS_PATH=$TOCI_WORKING_DIR/tripleo-image-elements/elements
    $ TOCI_WORKING_DIR/diskimage-builder/bin/disk-image-create -u -a i386 -o stackuserimage stackuser
    $ unset http_proxy ; unset https_proxy ; . ~/seedrc
    $ $TOCI_WORKING_DIR/incubator/scripts/load-image stackuserimage.qcow2
    $ nova boot --flavor 256 --key_name default stackuserimage --image  stackuserimage
