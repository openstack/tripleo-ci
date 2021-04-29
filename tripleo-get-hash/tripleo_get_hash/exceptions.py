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


class Base(Exception):
    """Base Exception"""


class TripleOHashMissingConfig(Base):
    """Missing configuration file for TripleOHashInfo. This is thrown
    when there is no config.yaml in constants.CONFIG_PATH or the local
    directory assuming execution from a source checkout.
    """

    def __init__(self, error_msg):
        super(TripleOHashMissingConfig, self).__init__(error_msg)


class TripleOHashInvalidConfig(Base):
    """Invalid configuration file for TripleOHashInfo. This is used when
    any of they keys in constants.CONFIG_KEYS is not found in config.yaml.
    """

    def __init__(self, error_msg):
        super(TripleOHashInvalidConfig, self).__init__(error_msg)


class TripleOHashInvalidParameter(Base):
    """Invalid parameters passed for TripleOHashInfo. This is thrown when
    the user passed invalid combination ofparameters parameters to the cli
    entrypoint, for example specifying --component with centos7.
    """

    def __init__(self, error_msg):
        super(TripleOHashInvalidParameter, self).__init__(error_msg)
