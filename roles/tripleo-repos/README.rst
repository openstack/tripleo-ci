tripleo-repos
=============

A role to install and run tripleo-repos to setup the CentOS and RDO yum
repositories.

Role Variables
--------------

.. list-table:: Variables used for chrony
   :widths: auto
   :header-rows: 1

   * - Name
     - Default Value
     - Description
   * - `tripleo_repos_repository`
     - `git+https://opendev.org/openstack/tripleo-repos`
     - Git repository to pip install tripleo-repos from
   * - `workspace`
     - `ansible_user_dir`
     - Workspace directory to put the venv into
   * - `centos_mirror_host`
     - `http://mirror.centos.org`
     - Mirror host for CentOS repositories
   * - `rdo_mirror_host`
     - `https://trunk.rdoproject.org`
     - Mirror host for RDO repositories

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
      become: true
      roles:
        - tripleo-repos

License
-------

Apache 2.0
