#   Copyright 2021 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License"); you may
#   not use this file except in compliance with the License. You may obtain
#   a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#   License for the specific language governing permissions and limitations
#   under the License.
#
#

import unittest
import tripleo_get_hash.tripleo_hash_info as thi
import tripleo_get_hash.exceptions as exc
import test.fakes as test_fakes
import requests_mock
from unittest import mock
from unittest.mock import mock_open


@mock.patch('builtins.open', new_callable=mock_open, read_data=test_fakes.CONFIG_FILE)
class TestGetHashInfo(unittest.TestCase):
    """In this class we test the functions and instantiation of the
    TripleOHashInfo class. The builtin 'open' function is mocked at a
    class level so we can mock the config.yaml with the contents of the
    fakes.CONFIG_FILE
    """

    def test_hashes_from_commit_yaml(self, mock_config):
        sample_commit_yaml = test_fakes.TEST_COMMIT_YAML_COMPONENT
        expected_result = (
            '476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3',
            '476a52df13202a44336c8b01419f8b73b93d93eb',
            '1f5a41f31db8e3eb51caa9c0e201ab0583747be8',
            'None',
        )
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/component/common/current-tripleo/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_COMPONENT,
            )
            mock_hash_info = thi.TripleOHashInfo(
                'centos8', 'master', 'common', 'current-tripleo'
            )
            actual_result = mock_hash_info._hashes_from_commit_yaml(sample_commit_yaml)
            self.assertEqual(expected_result, actual_result)

    def test_resolve_repo_url_component_commit_yaml(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            # test component url
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/component/common/current-tripleo/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_COMPONENT,
            )
            c8_component_hash_info = thi.TripleOHashInfo(
                'centos8', 'master', 'common', 'current-tripleo'
            )
            repo_url = c8_component_hash_info._resolve_repo_url("https://woo")
            self.assertEqual(
                repo_url,
                'https://woo/centos8-master/component/common/current-tripleo/commit.yaml',
            )

    def test_resolve_repo_url_centos8_repo_md5(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            # test vanilla centos8 url
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            c8_hash_info = thi.TripleOHashInfo(
                'centos8', 'master', None, 'current-tripleo'
            )
            repo_url = c8_hash_info._resolve_repo_url("https://woo")
            self.assertEqual(
                repo_url, 'https://woo/centos8-master/current-tripleo/delorean.repo.md5'
            )

    def test_resolve_repo_url_centos7_commit_yaml(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            # test centos7 url
            req_mock.get(
                'https://trunk.rdoproject.org/centos7-master/current-tripleo/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_CENTOS_7,
            )
            c7_hash_info = thi.TripleOHashInfo(
                'centos7', 'master', None, 'current-tripleo'
            )
            repo_url = c7_hash_info._resolve_repo_url("https://woo")
            self.assertEqual(
                repo_url, 'https://woo/centos7-master/current-tripleo/commit.yaml'
            )

    def test_get_tripleo_hash_info_centos8_md5(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            created_hash_info = thi.TripleOHashInfo(
                'centos8', 'master', None, 'current-tripleo'
            )
            self.assertIsInstance(created_hash_info, thi.TripleOHashInfo)
            self.assertEqual(created_hash_info.full_hash, test_fakes.TEST_REPO_MD5)
            self.assertEqual(created_hash_info.tag, 'current-tripleo')
            self.assertEqual(created_hash_info.os_version, 'centos8')
            self.assertEqual(created_hash_info.release, 'master')

    def test_get_tripleo_hash_info_component(self, mock_config):
        expected_commit_hash = '476a52df13202a44336c8b01419f8b73b93d93eb'
        expected_distro_hash = '1f5a41f31db8e3eb51caa9c0e201ab0583747be8'
        expected_full_hash = '476a52df13202a44336c8b01419f8b73b93d93eb_1f5a41f3'
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-victoria/component/common/tripleo-ci-testing/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_COMPONENT,
            )
            created_hash_info = thi.TripleOHashInfo(
                'centos8', 'victoria', 'common', 'tripleo-ci-testing'
            )
            self.assertIsInstance(created_hash_info, thi.TripleOHashInfo)
            self.assertEqual(created_hash_info.full_hash, expected_full_hash)
            self.assertEqual(created_hash_info.distro_hash, expected_distro_hash)
            self.assertEqual(created_hash_info.commit_hash, expected_commit_hash)
            self.assertEqual(created_hash_info.component, 'common')
            self.assertEqual(created_hash_info.tag, 'tripleo-ci-testing')
            self.assertEqual(created_hash_info.release, 'victoria')

    def test_get_tripleo_hash_info_centos7_commit_yaml(self, mock_config):
        expected_commit_hash = 'b5ef03c9c939db551b03e9490edc6981ff582035'
        expected_distro_hash = '76ebc4655502820b7677579349fd500eeca292e6'
        expected_full_hash = 'b5ef03c9c939db551b03e9490edc6981ff582035_76ebc465'
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos7-master/tripleo-ci-testing/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_CENTOS_7,
            )
            created_hash_info = thi.TripleOHashInfo(
                'centos7', 'master', None, 'tripleo-ci-testing'
            )
            self.assertIsInstance(created_hash_info, thi.TripleOHashInfo)
            self.assertEqual(created_hash_info.full_hash, expected_full_hash)
            self.assertEqual(created_hash_info.distro_hash, expected_distro_hash)
            self.assertEqual(created_hash_info.commit_hash, expected_commit_hash)
            self.assertEqual(created_hash_info.os_version, 'centos7')

    def test_bad_config_file(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos7-master/tripleo-ci-testing/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_CENTOS_7,
            )
            with mock.patch(
                'builtins.open',
                new_callable=mock_open,
                read_data=test_fakes.BAD_CONFIG_FILE,
            ):
                self.assertRaises(
                    exc.TripleOHashInvalidConfig,
                    thi.TripleOHashInfo,
                    'centos7',
                    'master',
                    None,
                    'tripleo-ci-testing',
                )

    def test_missing_config_file(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos7-master/tripleo-ci-testing/commit.yaml',
                text=test_fakes.TEST_COMMIT_YAML_CENTOS_7,
            )
            with mock.patch('os.path.isfile') as mock_is_file:
                mock_is_file.return_value = False
                self.assertRaises(
                    exc.TripleOHashMissingConfig,
                    thi.TripleOHashInfo,
                    'centos7',
                    'master',
                    None,
                    'tripleo-ci-testing',
                )
