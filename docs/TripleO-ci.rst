TripleO CI
==========

Introduction
------------

TripleO CI is designed to run devtest [1]_  from jenkins jobs, currently in a
virtualized baremetal environment. We do this by pre creating a Test
Environment (TE) containing a number of libvirt domains on their own ovs bridge
and making them available to instances on a openstack cloud (ci-overcloud).
Each CI job consists of a single worker node (kvm instance on an ci-overcloud)
along with a TE. The TE is held in a "locked" state for the duration of the CI
test and held exclusively for the jenkins slave node.

The TripleO CI process is changing fairly quickly with plans in place to
improve its reliability/speed and consistency [2]_

Infrastructure
--------------

The TripleO CI infrastructure is currently run on 2 separate clouds
(HP1 and RH1, donated by HP and RedHat respectively) with two more
regions currently being built. Each deployment contains

* ci-overcloud : traditional kvm openstack cloud

  * Should have an allocation of public floating IP available (1 per worker
    node). Required to allow communication nodepool/jenkins [3]_.
  * Should have defined a test network which is managed by neutron in the
    ci-overcloud but should also be made available to TE hosts.

* TE Hosts : each hosting X number of actual test environments

Test Environments
-----------------

Each test environment host (TE Host) contains a number of TE's (this number
depends on resources available on the host). Each test environment will contain
a seed libvirt domain along with a number of baremetal nodes e.g.

::

  $ sudo  virsh list --all | grep _2
  217   baremetalbrbm3_2               running
  -     baremetalbrbm1_2               shut off
  -     baremetalbrbm2_2               shut off
  215   seed_2                         running

The seed has been defined with 2 nics, the first "public interface" is on an
ovs-bridge (br-ctlplane) which is shared with seeds from other TE's and a
physical nic, this will give the seed access to the ci-overcloud. The second
"private interface" is on a ovs bridge specific to that TE and is shared with
the interfaces from the other domains on its TE e.g. the private bridge of
TE 2 above might look something like this

::

    Bridge "brbm2"
        Port "vnet11"
            Interface "vnet10"
        Port "vnet10"
            Interface "vnet10"
        Port "brbm2"
            Interface "brbm2"
                type: internal

The MAC address for the TE Host has been used to register a port with neutron
on the ci-overcloud this allows instances on the ci-overcloud to communicate
with the TE host (to copy across images, start the seed etc...)

The MAC address for the public interface of each TE seed on each TE hosts is
also used to register a port with neutron on the ci-overcloud, this allows
instances on the ci-overcloud to communicate with the seed during devtest.
It also provides a route to the instances on the private bridge so the ci
instances can communicate with the undercloud or overcloud.

Each TE is associated with a "testenv-worker". This worker registers
itself with a geard broker. A ci instance can then request a TE via a geard
broker. A testenv-worker will respond with details about its TE and remain
"locked" until the ci instance releases it.

CI Overcloud Test Sequence
--------------------------

* Developer submits patch to gerrit
* Zuul requests an instance on the ci-overcloud for each job it needs to run,
  a full list of the current jobs defined can be found here [4]_ and what
  projects they are run for [5]_

   * Nodepool makes an instance available (it keeps a pool of nodes ready)

* The jenkins slave node node is handed over to a jenkins server where the
  job is started
* Jenkins runs the script devstack-gate/devstack-vm-gate-wrap.sh [6]_. Among
  other things devstack-gate sets the revision of repositories on the
  instance to the revision that needs to be tested (in `/opt/stack/new/`)
* Once the instance has been setup the tripleo-ci/toci_gate_test.sh [7]_ is run,
  this is a wrapper around TripleO ci primarily responsible for ensuring we
  don't continue with the rest of CI without an allocated TE
* ./testenv-client is used to talk to geard
   * testenv-worker on one of the TE hosts will respond providing some json
     describing it's TE (including MAC's, IP's, resources etc...). This TE is
     now locked until CI is finished or a time-out occurs.
* toci_devtest.sh is called with the details for the TE (in $TE_DATAFILE)
* ssh key are installed on the ci instance (a private key was included in the
  TE json file), this will give us restricted access to do some operations on
  the TE Host
* For each of the repositories in `/opt/stack/new/` set DIB_REPOLOCATION_*, these
  are used during disk image builds (see the source-repositories element)
* Run components from devtest - in as much as is possible this should be the
  same as a local devtest run with a few notable differences

   * libvirt domains are never undefined and redefined as the TE has been pre
     setup, instead they are simply destroyed
   * The seed image is copied over ssh to the TE host using dd
   * We ssh to the TE host to start the seed
   * When the seed boots it gets an IP from the ci-overcloud dhcp agent (we had
     registered its MAC with the overcloud)

* For each instance started during the test grab a tarball containing relevant
  logs and config files
* exit from toci_devtest.sh (releasing the TE)
* Jenkins then archives off the instance all of the files in the workspace logs
  directory
* The ci instance is deleted

Infrastructure Setup
--------------------

Setting up a ci-overcloud and TE hosts is currently a fairly manual process
with a lot of work under way to help automate it. This section currently only
gives pointers to various relevant scripts, but will be a lot more consumable
soon as various scripts are matured.

We also make the assumption here that you already have a running ironic
( or nova-bm) cloud with a number of available baremetal instances

* deploying a ci overcloud
   * devtest_overcloud.sh can be used to deploy a ci-overcloud, see
     http://git.openstack.org/cgit/openstack/tripleo-image-elements/tree/elements/tripleo-cd/deploy-ci-overcloud
* preparing a ci overcloud
   * Once an overcloud is deployed it requires certain
     images/networks/quotas etc... Scripts to automate much of this,
     and configs for each zone, can be found under
     http://git.openstack.org/cgit/openstack/tripleo-image-elements/tree/elements/tripleo-cd
* setting up TE hosts
   * TE host images need to be built and deployed
     http://git.openstack.org/cgit/openstack/tripleo-image-elements/tree/elements/tripleo-cd/bin/deploy-testenv


References
----------
.. [1] https://docs.openstack.org/tripleo-incubator/latest/devtest.html
.. [2] https://review.openstack.org/#/c/95026/
.. [3] http://docs.openstack.org/infra/system-config/index.html
.. [4] http://git.openstack.org/cgit/openstack-infra/project-config/tree/jenkins/jobs/tripleo.yaml
.. [5] http://git.openstack.org/cgit/openstack-infra/project-config/tree/zuul/layout.yaml
.. [6] http://git.openstack.org/cgit/openstack-infra/devstack-gate/tree/devstack-vm-gate-wrap.sh
.. [7] http://git.openstack.org/cgit/openstack-infra/tripleo-ci/tree/toci_gate_test.sh
