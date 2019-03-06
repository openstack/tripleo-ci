ceph-loop-device
================

This roles creates the /dev/loop3 and /dev/loop4 (default) loop
devices required when you have Ceph services in the deployment.
The first device is used for legacy jobs which use Ceph Filestore.
The second loop device has three logical volumes created on it for
use with Ceph Bluestore.


Role Variables
--------------

ceph_loop_device: /dev/loop4
ceph_loop_device_legacy: /dev/loop3
ceph_loop_device_file: /var/lib/ceph-osd.img
ceph_loop_device_file_legacy: /var/lib/ceph-osd-legacy.img
ceph_logical_volume_group: ceph_vg
ceph_logical_volume_wal: ceph_lv_wal
ceph_logical_volume_db: ceph_lv_db
ceph_logical_volume_data: ceph_lv_data


Requirements
------------

 - ansible >= 2.4
 - python >= 2.6

Dependencies
------------

None

Example Playbooks
-----------------

.. code-block::

    - hosts: localhost
      roles:
        - ceph-loop-device

License
-------

Apache 2.0
