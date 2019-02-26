ceph-loop-device
================

This role creates the /dev/loop3 (default) loop device required when you have
ceph services in the deployment. For Stein and newer it creates three logical
volumes for use with bluestore.


Role Variables
--------------

ceph_loop_device: /dev/loop3
ceph_loop_device_file: /var/lib/ceph-osd.img
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
