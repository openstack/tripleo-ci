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

import requests_mock
import sys
import unittest
from unittest import mock
from unittest.mock import mock_open
import yaml

import tripleo_get_hash.exceptions as exc
import tripleo_get_hash.__main__ as tgh
import test.fakes as test_fakes


@mock.patch('builtins.open', new_callable=mock_open, read_data=test_fakes.CONFIG_FILE)
class TestGetHash(unittest.TestCase):
    """In this class we test the CLI invocations for this module.
    The builtin 'open' function is mocked at a
    class level so we can mock the config.yaml with the contents of the
    fakes.CONFIG_FILE
    """

    def test_centos_8_current_tripleo_stable(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-victoria/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            args = ['--os-version', 'centos8', '--release', 'victoria']
            sys.argv[1:] = args
            main_res = tgh.main()
            self.assertEqual(main_res.full_hash, test_fakes.TEST_REPO_MD5)
            self.assertEqual(
                'https://trunk.rdoproject.org/centos8-victoria/current-tripleo/delorean.repo.md5',
                main_res.dlrn_url,
            )
            self.assertEqual('centos8', main_res.os_version)
            self.assertEqual('victoria', main_res.release)

    def test_verbose_logging_on(self, mock_config):
        args = ['--verbose']
        debug_msgs = []

        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            with self.assertLogs() as captured:
                sys.argv[1:] = args
                tgh.main()
            debug_msgs = [
                record.message
                for record in captured.records
                if record.levelname == 'DEBUG'
            ]
        self.assertIn('Logging level set to DEBUG', debug_msgs)

    def test_verbose_logging_off(self, mock_config):
        debug_msgs = []
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://trunk.rdoproject.org/centos8-master/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            args = ['--tag', 'current-tripleo', '--os-version', 'centos8']
            with self.assertLogs() as captured:
                sys.argv[1:] = args
                tgh.main()
            debug_msgs = [
                record.message
                for record in captured.records
                if record.levelname == 'DEBUG'
            ]
        self.assertEqual(debug_msgs, [])

    def test_invalid_unknown_components(self, mock_config):
        args = ['--component', 'nosuchcomponent']
        sys.argv[1:] = args
        self.assertRaises(SystemExit, lambda: tgh.main())

    def test_valid_tripleo_ci_components(self, mock_config):
        config_file = open("fake_config_file")  # open is mocked at class level
        config_yaml = yaml.safe_load(config_file.read())
        config_file.close()
        # interate for each of config components
        for component in config_yaml['tripleo_ci_components']:
            with requests_mock.Mocker() as req_mock:
                req_mock.get(
                    "https://trunk.rdoproject.org/centos8-master/component/{}/current-tripleo/commit.yaml".format(
                        component
                    ),
                    text=test_fakes.TEST_COMMIT_YAML_COMPONENT,
                )
                args = ['--component', "{}".format(component)]
                sys.argv[1:] = args
                main_res = tgh.main()
                self.assertEqual(
                    "https://trunk.rdoproject.org/centos8-master/component/{}/current-tripleo/commit.yaml".format(
                        component
                    ),
                    main_res.dlrn_url,
                )
                self.assertEqual("{}".format(component), main_res.component)

    def test_invalid_component_centos7(self, mock_config):
        args = ['--os-version', 'centos7', '--component', 'tripleo']
        sys.argv[1:] = args
        self.assertRaises(exc.TripleOHashInvalidParameter, lambda: tgh.main())

    def test_invalid_os_version(self, mock_config):
        args = ['--os-version', 'rhelos99', '--component', 'tripleo']
        sys.argv[1:] = args
        self.assertRaises(SystemExit, lambda: tgh.main())

    def test_invalid_unknown_tag(self, mock_config):
        args = ['--tag', 'nosuchtag']
        sys.argv[1:] = args
        self.assertRaises(SystemExit, lambda: tgh.main())

    def test_valid_rdo_named_tags(self, mock_config):
        config_file = open("fake_config_file")  # open is mocked at class level
        config_yaml = yaml.safe_load(config_file.read())
        config_file.close()
        # iterate for each of config named tags
        for tag in config_yaml['rdo_named_tags']:
            with requests_mock.Mocker() as req_mock:
                req_mock.get(
                    "https://trunk.rdoproject.org/centos8-master/{}/delorean.repo.md5".format(
                        tag
                    ),
                    text=test_fakes.TEST_REPO_MD5,
                )
                args = ['--tag', "{}".format(tag)]
                sys.argv[1:] = args
                main_res = tgh.main()
                self.assertEqual(
                    "https://trunk.rdoproject.org/centos8-master/{}/delorean.repo.md5".format(
                        tag
                    ),
                    main_res.dlrn_url,
                )
                self.assertEqual(tag, main_res.tag)

    def test_override_dlrn_url(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://awoo.com/awoo/centos8-master/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            args = ['--dlrn-url', 'https://awoo.com/awoo']
            sys.argv[1:] = args
            main_res = tgh.main()
            self.assertEqual(
                'https://awoo.com/awoo/centos8-master/current-tripleo/delorean.repo.md5',
                main_res.dlrn_url,
            )

    def test_override_os_version_release_rhel8(self, mock_config):
        with requests_mock.Mocker() as req_mock:
            req_mock.get(
                'https://awoo.com/awoo/rhel8-osp16-2/current-tripleo/delorean.repo.md5',
                text=test_fakes.TEST_REPO_MD5,
            )
            args = [
                '--dlrn-url',
                'https://awoo.com/awoo',
                '--os-version',
                'rhel8',
                '--release',
                'osp16-2',
            ]
            sys.argv[1:] = args
            main_res = tgh.main()
            self.assertEqual('rhel8', main_res.os_version)
            self.assertEqual('osp16-2', main_res.release)
            self.assertEqual(
                'https://awoo.com/awoo/rhel8-osp16-2/current-tripleo/delorean.repo.md5',
                main_res.dlrn_url,
            )


if __name__ == '__main__':
    unittest.main()
