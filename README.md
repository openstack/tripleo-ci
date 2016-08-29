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

|        -       | scenario001 | multinode-nonha |
|:--------------:|:-----------:|:---------------:|
| keystone       |      X      |        X        |
| glance         |    file     |      swift      |
| cinder         |             |      iscsi      |
| heat           |      X      |        X        |
| mysql          |      X      |        X        |
| neutron        |     ovs     |        X        |
| rabbitmq       |      X      |        X        |
| haproxy        |      X      |        X        |
| keepalived     |      X      |        X        |
| memcached      |      X      |        X        |
| pacemaker      |      X      |        X        |
| nova           |     qemu    |        X        |
| ntp            |      X      |        X        |
| snmp           |      X      |        X        |
| timezone       |      X      |        X        |
| sahara         |      X      |                 |
| swift          |             |        X        |



Scenarios description
---------------------

scenario001 deploys the Compute kit (Keystone, Nova, Glance, Neutron) and
Sahara. Glance uses file backend because Swift is not installed.

multinode-nonha deploys the Compute kit with Cinder and Swift. Glance uses Swift
backend.
