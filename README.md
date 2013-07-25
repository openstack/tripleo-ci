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

I usually do this as root, in theory it will also work as a non privilaged user.

    $ git clone https://github.com/openstack-infra/tripleo-ci.git
    $ cd toci
    $ vi ~/.toci # Will work without a proxy but a lot slower
    export http_proxy=http://192.168.1.104:8080

To run toci here is your command

    $ ./toci.sh

Toci will start with a line outputing the working and log directories e.g.
Starting run Wed  3 Jul 11:46:39 IST 2013 ( /opt/toci /tmp/toci_logs_nGnrhLN )

Once it ran successfully (ERROR wasn't echo'd to the terminal) you should have
1. seed vm
2. undercloud vm
3. overcloud controller vm
4. overcloud compute vm
