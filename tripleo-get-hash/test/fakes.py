#   Copyright 2021 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License"); you may
#   not use this file except in compliance with the License. You may obtain
#   a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#   License for the specific language governing permissions and limitations
#   under the License.
#
#

TEST_COMMIT_YAML_COMPONENT = """
    commits:
    - artifacts: repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/openstack-tacker-4.1.0-0.20210325043415.476a52d.el8.src.rpm,repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/python3-tacker-doc-4.1.0-0.20210325043415.476a52d.el8.noarch.rpm,repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/python3-tacker-tests-4.1.0-0.20210325043415.476a52d.el8.noarch.rpm,repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/openstack-tacker-common-4.1.0-0.20210325043415.476a52d.el8.noarch.rpm,repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/python3-tacker-4.1.0-0.20210325043415.476a52d.el8.noarch.rpm,repos/component/common/47/6a/476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3/openstack-tacker-4.1.0-0.20210325043415.476a52d.el8.noarch.rpm
      civotes: '[]'
      commit_branch: master
      commit_hash: 476a52df13202a44336c8b01419f8b73b93d93eb
      component: common
      distgit_dir: /home/centos8-master-uc/data/openstack-tacker_distro/
      distro_hash: 1f5a41f31db8e3eb51caa9c0e201ab0583747be8
      dt_build: '1616646776'
      dt_commit: '1616646661.0'
      dt_distro: '1616411951'
      dt_extended: '0'
      extended_hash: None
      flags: '0'
      id: '21047'
      notes: OK
      project_name: openstack-tacker
      promotions: '[]'
      repo_dir: /home/centos8-master-uc/data/openstack-tacker
      status: SUCCESS
      type: rpm
"""

TEST_COMMIT_YAML_CENTOS_7 = """
    commits:
    - artifacts: repos/b5/ef/b5ef03c9c939db551b03e9490edc6981ff582035_76ebc465/openstack-tripleo-heat-templates-12.1.1-0.20200227052810.b5ef03c.el7.src.rpm,repos/b5/ef/b5ef03c9c939db551b03e9490edc6981ff582035_76ebc465/openstack-tripleo-heat-templates-12.1.1-0.20200227052810.b5ef03c.el7.noarch.rpm
      commit_branch: master
      commit_hash: b5ef03c9c939db551b03e9490edc6981ff582035
      component: None
      distgit_dir: /home/centos-master-uc/data/openstack-tripleo-heat-templates_distro/
      distro_hash: 76ebc4655502820b7677579349fd500eeca292e6
      dt_build: '1582781227'
      dt_commit: '1582780705.0'
      dt_distro: '1580409403'
      dt_extended: '0'
      extended_hash: None
      flags: '0'
      id: '86894'
      notes: OK
      project_name: openstack-tripleo-heat-templates
      repo_dir: /home/centos-master-uc/data/openstack-tripleo-heat-templates
      status: SUCCESS
      type: rpm
"""

TEST_REPO_MD5 = 'a96366960d5f9b08f78075b7560514e7'

BAD_CONFIG_FILE = """
awoo: 'foo'
"""

CONFIG_FILE = """
dlrn_url: 'https://trunk.rdoproject.org'

tripleo_releases:
  - master
  - wallaby
  - victoria
  - ussuri
  - train
  - osp16-2
  - osp17

tripleo_ci_components:
  - baremetal
  - cinder
  - clients
  - cloudops
  - common
  - compute
  - glance
  - manila
  - network
  - octavia
  - security
  - swift
  - tempest
  - tripleo
  - ui
  - validation

rdo_named_tags:
  - current
  - consistent
  - component-ci-testing
  - tripleo-ci-testing
  - current-tripleo
  - current-tripleo-rdo

os_versions:
  - centos7
  - centos8
  - rhel8

"""
