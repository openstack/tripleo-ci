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


OpenStack Infrastructure is deploying multiple jobs with different scenarios.
OpenStack services are balanced between different scenarios because OpenStack
Infastructure Jenkins slaves can not afford the load of running everything on
the same node.

Usage Details
-------------

Job parameters are configured in ``toci_gate_test.sh``.  Control passes to
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
`tripleo-heat-templates <https://git.openstack.org/cgit/openstack/tripleo-heat-templates/tree/README.rst>`_.
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
