toci
====


Description
-----------

TripleO CI test framework.

By default toci builds images for seed, undercloud and overcloud hosts, it
then uses bare metal poseur nodes to set up a virtualized TripleO environment.

Options also exist so you can specify hosts to setup TripleO on a real
baremetal environment.

Configuration
-------------

If using toci to setup TripleO on a virtualized environment we recommend you
setup a proxy server for http traffic

edit ~/.toci and add a value for
```bash
export http_proxy=http://1.2.3.4:3128
```

See toci-defaults for a list of additional environment variables that can be
defined in ~/.toci in order to control things like
* Changing the architecture to amd64
* Deploying TripleO images on real baremetal hosts
* Increasing the resources allocated to bm_poseur nodes
* notifying an irc channel and uploading toci results to a server (used if
  running toci as a CI framwork)

Using Toci to setup a dev environment
-------------------------------------

I usually do this as root, in theory it will also work as a non privileged
user.

    $ git clone https://github.com/openstack-infra/tripleo-ci.git toci
    $ cd toci
    $ vi ~/.toci # Will work without a proxy but can be a lot slower
    export http_proxy=http://1.2.3.4:8080

To deploy toci run the command command

    $ ./toci.sh

Toci will start with a line outputting the working and log directories e.g.
Starting run Wed  3 Jul 11:46:39 IST 2013 ( /opt/toci /tmp/toci_logs_nGnrhLN )

Once it ran successfully (ERROR wasn't echo'd to the terminal) you should have
* seed vm
* undercloud vm
* overcloud controller vm
* overcloud compute vm

NOTE: toci will now have cloned the dependency git repositories to /opt/toci,
If you rerun toci it will NOT re-clone these again, if you would like it to
reclone the most recent version of any of these repositories you can simply
delete it before running toci.

If you would like to test a specific change locally in TripleO you can simply
edit the repository locally and commit this change to its master branch and
rerun toci. See the FAQ if you would like to do this without rebuilding all of
the images (e.g. For speed reasons, you would only like to rebuild the
overcloud images and reuse the previously built seed and undercloud image)

See FAQ.md for more information on how to use the TripleO deployment

Using Toci as a CI framework for TripleO
----------------------------------------

If running toci as part of a automated CI job several environment variables
can be defined to help make toci more suitable e.g.

*So toci cleans up after itself*
```bash
export TOCI_UPLOAD=1
export TOCI_REMOVE=1
```

*scp logs to a server when finished*
```bash
TOCI_RESULTS_DST=user@1.2.3.4:/var/www/html/toci
```

*Notify a freenode irc channel upon error*
```bash
TOCI_IRC=channeltonotify
```

*Only build and deploy the seed and undercloud*
```bash
export TOCI_DO_OVERCLOUD=0
```


Use toci to deploy on real baremetal
-----------------------------------
```bash
export TOCI_PM_DRIVER="nova.virt.baremetal.ipmi.IPMI"
#Space delimited, aligned in order
export TOCI_MACS="84:2b:22:11:11:11 84:2b:22:11:11:12 84:2b:22:11:11:13"
export TOCI_PM_IPS="10.16.111.111 10.16.111.112 10.16.111.113"
export TOCI_PM_USERS="root root root"
export TOCI_PM_PASSWORDS="passwd  passwd passwd"
```
