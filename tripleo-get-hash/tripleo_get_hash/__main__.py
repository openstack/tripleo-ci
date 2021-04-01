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

import argparse
import logging
import sys
from tripleo_get_hash.tripleo_hash_info import TripleOHashInfo
import tripleo_get_hash.exceptions as exc


def _validate_args(parsed_args):
    if parsed_args.os_version == 'centos7' and parsed_args.component is not None:
        raise exc.TripleOHashInvalidParameter('Cannot specify component for centos 7')


def main():
    TripleOHashInfo.load_logging()
    config = TripleOHashInfo.load_config()
    parser = argparse.ArgumentParser(description='tripleo-get-hash.py')
    parser.add_argument(
        '--component',
        help=('Use this to specify a component ' 'This is NOT valid for Centos 7.'),
        choices=config['tripleo_ci_components'],
    )
    parser.add_argument(
        '--dlrn-url',
        help=(
            'The URL for the delorean server to use. Defaults to '
            'https://trunk.rdoproject.org'
        ),
    )
    parser.add_argument(
        '--os-version',
        default='centos8',
        choices=config['os_versions'],
        help=('The operating system and version to fetch the build tag for'),
    )
    parser.add_argument(
        '--tag',
        default='current-tripleo',
        choices=config['rdo_named_tags'],
        help=('The known tag to retrieve the hash_info for'),
    )
    parser.add_argument(
        '--release',
        default='master',
        help=('The release of OpenStack you want the hash info for. Default master'),
        choices=config['tripleo_releases'],
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help=('Enable verbose log level for debugging'),
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logging.debug("Logging level set to DEBUG")
    _validate_args(args)

    if args.dlrn_url is not None:
        logging.debug(
            "Overriding configuration dlrn_url. Original value {}. "
            "New value {}".format(config['dlrn_url'], args.dlrn_url)
        )
        config['dlrn_url'] = args.dlrn_url
        logging.debug("Proceeding with the following configuration: {}".format(config))

    tripleo_hash_info = TripleOHashInfo(
        args.os_version,
        args.release,
        args.component,
        args.tag,
        config,
    )
    tripleo_hash_info.pretty_print()
    return tripleo_hash_info


def cli_entrypoint():
    try:
        main()
        sys.exit(0)
    except KeyboardInterrupt:
        logging.info("Exiting on user interrupt")
        raise


if __name__ == "__main__":
    main()
