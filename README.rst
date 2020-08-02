toci
====

Description
-----------

TripleO CI test framework.

Tools to help run CI jobs for TripleO. Includes things like:

* Shell scripts to help execute jobs on CI slave nodes (Jenkins slaves)
* A test environment broker framework which uses a client-server
  model to execute jobs on a remote bare metal machine in an isolated
  test environment (using VMs).
* Image elements to help build images for the test environment
  broker nodes.
* Heat templates to help deploy and maintain test environment nodes
  using an undercloud.
* Helper script(s) to generate CI status reports. (tox -ecireport -- -f)
* Helper `getthelogs` script to download important job logs locally.
  Then you may want to inspect the logs for known errors and contribute
  discovered search patterns as the
  `elastic-recheck queries <https://opendev.org/opendev/elastic-recheck/src/branch/master/queries>`_.


OpenStack Infrastructure is deploying multiple jobs with different scenarios.
OpenStack services are balanced between different scenarios because OpenStack
Infastructure Jenkins slaves can not afford the load of running everything on
the same node.

Usage Details
-------------

On March 2017, the ansible quickstart framework was added to TOCI to gradually
replace the bash scripts that drove the jobs. Part of the original framework has
been changed to allow the new framework to handle jobs, but maintaining
backwards compatibility with the original framework while jobs are being
transitioned

TOCI entry point
~~~~~~~~~~~~~~~~

Upon starting a job, based on the configuration of its layout, zuul will call
devstack-gate, which is needed for the basic nodepool node setup, but will then
pass the control to ``toci_gate_test.sh``.
During the transition, this will be a symbolic link to
``toci_gate_test-oooq.sh``.

Quickstart Transition scripts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The initial part of  ``toci_gate_test-oooq.sh`` script decides whether to exec
the original workflow or continue with the quickstart workflow, based on the job
type passed down by zuul layout parameters. To move a job to the new quickstart
framework, it is enough to propose a change to zuul layout to add a "featureset"
keyword on its type.
When using the quickstart workflow, the rest of the script will assemble a set of
arguments to pass to quickstart scripts, based on the components of the job type
separated by dashes e.g. a job type value of "periodic-ovb-featureset001"
will make the script assemble arguments to deal with "ovb" provisioning,
and set featurset001 to be the test matrix for the job.
This script will also invoke the test environment broker to create the proper
ovb environment.
At the end the ``toci_gate_test-oooq.sh`` will pass control to
``toci_quickstart.sh`` script that will actually call quickstart with its
parameters.

Quickstart Framework
~~~~~~~~~~~~~~~~~~~~

 ``toci_quickstart.sh`` consists of three parts, setup, invocationo and logs
 collection.

For more information about feature sets and test matrix please see

.. _Featureset Documentation: https://docs.openstack.org/developer/tripleo-quickstart/feature-configuration.html

from quickstart documentation
The new workflow uses the directory toci-quickstart/ to store TripleO ci specific
configurations, roles or playbooks for the quickstart workflow
The parts of quickstart under scripts/ are instead handled by the original
framework only

Original Framework
~~~~~~~~~~~~~~~~~~

Job parameters are configured in ``toci_gate_test-orig.sh``. Control passes to
one of the ``toci_instack_*.sh`` scripts (depending on the type of job being
run) which do environment-specific setup. These scripts then call
``scripts/deploy.sh`` to run the actual deployment steps.  For most things,
``deploy.sh`` simply calls ``scripts/tripleo.sh`` with the appropriate
parameters.

In ascii art, the flow of the scripts would look like:

toci_gate_test -> toci_instack_* -> deploy.sh -> tripleo.sh

There's some additional complexity that this description glosses over, but
for the most part only tripleo-ci admins need to worry about it.

temprevert, cherry-pick, pin
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are three functions available in tripleo-ci which can be used to alter
the git repos of non-tripleo projects that are used in tripleo-ci.  They only
work on projects that are part of OpenStack.  Use of these should
be avoided whenever possible as any changes made during a ci run will not
apply to regular users of TripleO.  However, they can be useful for determining
which commit broke something, and in rare cases we may want to use them
until a project can sort out a problem itself.

To apply one of these functions during a ci run, add it to the appropriate
location in the ``toci_instack_*.sh`` script.  There should be a comment that
says "Tempreverts/cherry-picks/pins go here."

.. note:: Do not include the bug number in the commit message where you
          propose adding one of these functions.  Any change whose commit
          message includes a reference to the bug will not apply the function.
          This is to allow testing of patches intended to fix the bug.

.. warning:: As of this writing, these functions all apply against the latest
             master branch of the project in question.  They do not respect
             the current-tripleo repo versions.

* temprevert

  Revert a commit from a project.  Takes 3 parameters: project, commit id,
  and bug number.  Example::

      temprevert neutron 2ad9c679ed8718633732da1e97307f9fd9647dcc 1654032

* pin

  Pin to a commit from a project.  This usually is not necessary now that our
  repos are gated by the promotion jobs.  Takes 3 parameters: project,
  commit id, and bug number.  Example::

      pin neutron 2ad9c679ed8718633732da1e97307f9fd9647dcc 1654032

* cherrypick

  Cherry-pick an active review from a project.  Takes 3 parameters: project,
  Gerrit refspec, and bug number.  The Gerrit refspec can be found under the
  download button of the change in question.  Example::

      cherrypick neutron refs/changes/49/317949/28 1654032

Service testing matrix
----------------------

The CI testing matrix for all scenarios is defined in
`tripleo-heat-templates <https://opendev.org/openstack/tripleo-heat-templates/src/branch/master/README.rst>`_.
This matrix describes the services that will run in each environment.

Feature testing matrix
----------------------

======================== ===== == =======
Feature                  nonha ha updates
------------------------ ----- -- -------
undercloud ssl             X
overcloud ssl              X
ceph                       X         X
ipv4 net-iso                   X
ipv6 net-iso                         X
pacemaker                      X     X
predictable placement          X
introspection              X
======================== ===== == =======

How to deprecate job?
---------------------

1. Move the job definition to zuul.d/deprecated-jobs.yaml
2. Change the parent job to 'tripleo-ci-deprecated'
3. Change the branches var value to 'none/deprecated'
4. Remove job usage from the project-templates and from projects.

Documentation
-------------

Please refer to the official `TripleO documentation
<https://docs.openstack.org/tripleo-docs/latest/#contributor-guide>`_
for details regarding TripleO CI.

Please refer to the official `TripleO Quickstart documentation
<https://docs.openstack.org/tripleo-quickstart/latest/>`_
for details regarding the tools used in TripleO CI.
