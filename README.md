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

Service testing matrix
----------------------

The CI testing matrix for all scenarios is defined in
[tripleo-heat-templates](https://git.openstack.org/cgit/openstack/tripleo-heat-templates/tree/README.rst).
This matrix describes the services that will run in each environment.
