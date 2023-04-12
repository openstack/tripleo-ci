"""
Helper script that generates environmental variables for upgrade/update.

From the stable-release parameter it calculate environmental variables
for mixed release.

It exports those environmental variables in the OUTPUT_FILE:

 - UNDERCLOUD_INSTALL_RELEASE
 - UNDERCLOUD_INSTALL_HASH
 - UNDERCLOUD_TARGET_RELEASE
 - UNDERCLOUD_TARGET_HASH
 - OVERCLOUD_DEPLOY_RELEASE
 - OVERCLOUD_DEPLOY_HASH
 - OVERCLOUD_TARGET_RELEASE
 - OVERCLOUD_TARGET_HASH
 - STANDALONE_DEPLOY_RELEASE
 - STANDALONE_DEPLOY_NEWEST_HASH
 - STANDALONE_DEPLOY_HASH
 - STANDALONE_TARGET_RELEASE
 - STANDALONE_TARGET_NEWEST_HASH
 - STANDALONE_TARGET_HASH

"""
import argparse
import logging
import logging.handlers
import os
import re
import requests
import yaml
from typing import Dict

# TODO(pojadhav): remove ussuri, victoria once we EOL victoria
# Define releases
RELEASES = [
    'train',
    'ussuri',
    'victoria',
    'wallaby',
    'zed',
    'master',
]
# Define long term releases
LONG_TERM_SUPPORT_RELEASES = ['train', 'wallaby']

# NAMED DLRN HASHES
CURRENT_HASH_NAME = 'current-tripleo'
NEWEST_HASH_NAME = 'current'
PROMOTION_HASH_NAME = 'tripleo-ci-testing'
PREVIOUS_HASH_NAME = 'previous-current-tripleo'


def get_relative_release(release, relative_idx):
    current_idx = RELEASES.index(release)
    absolute_idx = current_idx + relative_idx
    return RELEASES[absolute_idx]


def setup_logging(log_file):
    '''Setup logging for the script'''
    logger = logging.getLogger('emit-releases')
    logger.setLevel(logging.DEBUG)
    log_handler = logging.handlers.WatchedFileHandler(os.path.expanduser(log_file))
    logger.addHandler(log_handler)


def load_featureset_file(featureset_file):
    logger = logging.getLogger('emit-releases')
    try:
        with open(featureset_file, 'r') as stream:
            featureset = yaml.safe_load(stream)
    except Exception as e:
        logger.error(
            "The featureset file: {} can not be " "opened.".format(featureset_file)
        )
        logger.exception(e)
        raise e
    return featureset


def get_dlrn_hash(
    release, hash_name, distro_name='centos', distro_version='7', retries=20, timeout=8
):
    """Get the dlrn hash for the release and hash name

    Retrieves the delorean.repo for the provided release and hash name, e.g.
    https://trunk.rdoproject.org/centos7-master/current/delorean.repo for
    master and current. The hash is taken from the repo file contents
    and returned.
    :param distro_name: Distro name
    :param distro_version: Distro version
    """
    logger = logging.getLogger('emit-releases')
    full_hash_pattern = re.compile('[a-z,0-9]{40}_[a-z,0-9]{8}')
    rdo_url = os.getenv('NODEPOOL_RDO_PROXY', 'https://trunk.rdoproject.org')
    logger.error("distro %s version %s", distro_name, distro_version)
    if distro_name == 'centos' and distro_version == '7':
        repo_url = '%s/centos7-%s/%s/delorean.repo' % (rdo_url, release, hash_name)
    elif distro_name == 'centos' and distro_version in ['8', '9']:
        repo_url = '%s/centos%s-%s/%s/delorean.repo.md5' % (
            rdo_url,
            distro_version,
            release,
            hash_name,
        )
    logger.debug(
        "distro_name {} distro_version {} repo_url {}"
        "".format(distro_name, distro_version, repo_url)
    )
    for retry_num in range(retries):
        repo_file = None
        try:
            repo_file = requests.get(repo_url, timeout=timeout)
        except Exception as e:
            logger.warning(
                "Attempt {} of {} to get DLRN hash threw an "
                "exception.".format(retry_num + 1, retries)
            )
            logger.exception(e)
            continue
        if repo_file is not None and repo_file.ok:
            if distro_name == 'centos' and distro_version == '7':
                print(repo_file.text)
                full_hash = full_hash_pattern.findall(repo_file.text)[0]
            elif distro_name == 'centos' and distro_version in ['8', '9']:
                full_hash = repo_file.text
            break

        elif repo_file:
            logger.warning(
                "Attempt {} of {} to get DLRN hash returned "
                "status code {}.".format(retry_num + 1, retries, repo_file.status_code)
            )
        else:
            logger.warning(
                "Attempt {} of {} to get DLRN hash failed to "
                "get a response.".format(retry_num + 1, retries)
            )

    if repo_file is None or not repo_file.ok:
        raise RuntimeError(
            "Failed to retrieve repo file from {} after "
            "{} retries".format(repo_url, retries)
        )

    logger.info(
        "Got DLRN hash: {} for the named hash: {} on the {} "
        "release".format(full_hash, hash_name, release)
    )
    return full_hash


def compose_releases_dictionary(
    stable_release,
    featureset,
    upgrade_from,
    is_periodic=False,
    distro_name='centos',
    distro_version='7',
    target_branch_override=None,
    install_branch_override=None,
    content_provider_hashes=None,
):
    """Compose the release dictionary for stable_release and featureset

    This contains the main logic determining the contents of the release file.

    First perform some validations on the input - ensure the release is
    supported and the featureset doesn't contain conflicting directives
    like both overcloud_upgrade and undercloud_upgrade.

    The provided stable_release set as the target, and then the featureset
    determines the type of upgrade. This is used to determine the deploy
    release and hash/teg relative to the target:
      * Standalone, Undercloud and Overcloud Upgrade: deploy current-tripleo
        of previous release to stable_release and upgrade to current of
        stable_release
      * Overcloud FFWDUpgrade: as above, except deploy is set to
        tripleo-ci-testing of 3 previous releases from stable_release
    :param distro_name: Distro name
    :param distro_version: Distro version
    """
    logger = logging.getLogger('emit-releases')
    if stable_release not in RELEASES:
        raise RuntimeError(
            "The {} release is not supported by this tool"
            "Supported releases: {}".format(stable_release, RELEASES)
        )

    if (
        featureset.get('overcloud_upgrade') or featureset.get('undercloud_upgrade')
    ) and stable_release == RELEASES[0]:
        raise RuntimeError("Cannot upgrade to {}".format(RELEASES[0]))

    if featureset.get('overcloud_upgrade') and featureset.get('undercloud_upgrade'):
        raise RuntimeError(
            "This tool currently only supports upgrading the "
            "undercloud OR the overcloud NOT both."
        )

    if featureset.get('ffu_undercloud_upgrade') and featureset.get(
        'undercloud_upgrade'
    ):
        raise RuntimeError(
            "Only Fast Forward Undercloud upgrade or single release undercloud "
            "upgrade is supported, NOT both at the same time."
        )

    if (
        featureset.get('overcloud_upgrade') or featureset.get('ffu_overcloud_upgrade')
    ) and not featureset.get('mixed_upgrade'):
        raise RuntimeError("Overcloud upgrade has to be mixed upgrades")

    if (
        featureset.get('ffu_overcloud_upgrade')
        or featureset.get('ffu_undercloud_upgrade')
    ) and stable_release not in LONG_TERM_SUPPORT_RELEASES:
        raise RuntimeError(
            "{} is not a long-term support release, and cannot be "
            "used in a fast forward upgrade. Current long-term support "
            "releases:  {}".format(stable_release, LONG_TERM_SUPPORT_RELEASES)
        )

    newest_hash = get_dlrn_hash(
        stable_release, NEWEST_HASH_NAME, distro_name, distro_version
    )
    if is_periodic:
        current_hash = get_dlrn_hash(
            stable_release, PROMOTION_HASH_NAME, distro_name, distro_version
        )
    elif content_provider_hashes is not None and content_provider_hashes.get(
        target_branch_override
    ):
        current_hash = content_provider_hashes[target_branch_override]
        logger.info(
            "Using hash override {} from content provider hashes map for branch {}".format(
                current_hash, target_branch_override
            )
        )
    else:
        current_hash = get_dlrn_hash(
            stable_release, CURRENT_HASH_NAME, distro_name, distro_version
        )

    releases_dictionary = {
        'undercloud_install_release': stable_release,
        'undercloud_install_hash': current_hash,
        'undercloud_target_release': stable_release,
        'undercloud_target_hash': current_hash,
        'overcloud_deploy_release': stable_release,
        'overcloud_deploy_hash': current_hash,
        'overcloud_target_release': stable_release,
        'overcloud_target_hash': current_hash,
        'standalone_deploy_release': stable_release,
        'standalone_deploy_hash': current_hash,
        'standalone_deploy_newest_hash': newest_hash,
        'standalone_target_release': stable_release,
        'standalone_target_hash': current_hash,
        'standalone_target_newest_hash': newest_hash,
    }

    if featureset.get('mixed_upgrade'):
        if featureset.get('overcloud_upgrade'):
            logger.info('Doing an overcloud upgrade')
            deploy_release = get_relative_release(stable_release, -1)
            deploy_hash = get_dlrn_hash(
                deploy_release, CURRENT_HASH_NAME, distro_name, distro_version
            )
            releases_dictionary['overcloud_deploy_release'] = deploy_release
            releases_dictionary['overcloud_deploy_hash'] = deploy_hash

        elif featureset.get('ffu_overcloud_upgrade'):
            logger.info('Doing an overcloud fast forward upgrade')
            deploy_release = get_relative_release(stable_release, -3)
            deploy_hash = get_dlrn_hash(
                deploy_release, CURRENT_HASH_NAME, distro_name, distro_version
            )
            releases_dictionary['overcloud_deploy_release'] = deploy_release
            releases_dictionary['overcloud_deploy_hash'] = deploy_hash

    elif featureset.get('undercloud_upgrade') or featureset.get(
        'ffu_undercloud_upgrade'
    ):
        if featureset.get('undercloud_upgrade'):
            logger.info('Doing an undercloud upgrade')
            install_release = get_relative_release(stable_release, -1)
        else:
            logger.info('Doing an undercloud fast forward upgrade')
            install_release = get_relative_release(stable_release, -3)

        install_hash = ''
        if content_provider_hashes is not None and content_provider_hashes.get(
            install_branch_override
        ):
            install_hash = content_provider_hashes[install_branch_override]
            logger.info(
                "Using hash override {} for branch {}".format(
                    install_hash, install_branch_override
                )
            )
        else:
            install_hash = get_dlrn_hash(
                install_release, CURRENT_HASH_NAME, distro_name, distro_version
            )
        releases_dictionary['undercloud_install_release'] = install_release
        releases_dictionary['undercloud_install_hash'] = install_hash

    elif featureset.get('standalone_upgrade') or featureset.get(
        'ffu_standalone_upgrade'
    ):
        if featureset.get('standalone_upgrade'):
            logger.info('Doing an standalone upgrade')
            install_release = get_relative_release(stable_release, -1)
        else:
            logger.info('Doing an ffu standalone upgrade')
            install_release = get_relative_release(stable_release, -3)
        install_hash = get_dlrn_hash(
            install_release, CURRENT_HASH_NAME, distro_name, distro_version
        )
        install_newest_hash = get_dlrn_hash(
            install_release, NEWEST_HASH_NAME, distro_name, distro_version
        )
        releases_dictionary['standalone_deploy_release'] = install_release
        releases_dictionary['standalone_deploy_newest_hash'] = install_newest_hash
        releases_dictionary['standalone_deploy_hash'] = install_hash

    elif featureset.get('minor_update'):
        if is_periodic:
            previous_hash = get_dlrn_hash(
                stable_release, PREVIOUS_HASH_NAME, distro_name, distro_version
            )
            releases_dictionary['overcloud_deploy_hash'] = previous_hash
        else:
            target_newest_hash = get_dlrn_hash(
                stable_release, NEWEST_HASH_NAME, distro_name, distro_version
            )
            releases_dictionary['undercloud_target_hash'] = target_newest_hash
            releases_dictionary['overcloud_target_hash'] = target_newest_hash
            if content_provider_hashes is not None and content_provider_hashes.get(
                install_branch_override
            ):
                install_hash = content_provider_hashes[install_branch_override]
                releases_dictionary['undercloud_install_hash'] = install_hash
                releases_dictionary['overcloud_deploy_hash'] = install_hash
            if content_provider_hashes is not None and content_provider_hashes.get(
                target_branch_override
            ):
                current_hash = content_provider_hashes[target_branch_override]
                releases_dictionary['undercloud_target_hash'] = current_hash
                releases_dictionary['overcloud_target_hash'] = current_hash

    elif featureset.get('overcloud_update'):
        logger.info('Doing an overcloud update')
        previous_hash = get_dlrn_hash(
            stable_release, PREVIOUS_HASH_NAME, distro_name, distro_version
        )
        releases_dictionary['overcloud_deploy_hash'] = previous_hash

    logger.debug("stable_release: %s, featureset: %s", stable_release, featureset)

    logger.info('output releases: %s', releases_dictionary)

    return releases_dictionary


def shim_convert_old_release_names(releases_names, is_periodic):
    """Convert release names for mixed upgrade and periodics

    For overcloud upgrade jobs we start with already upgraded undercloud
    and use config files named "{{target}}-undercloud-{{deploy}}-overcloud"
    like ocata-undercloud-newton-overcloud so we need to set both deploy and
    target names to point this release config.

    For periodic jobs the deploy and target config files are in files named
    promotion-testing-hash-{{release}} so the deploy and target names are
    prefixed with promotion-testing-hash-
    """
    # TODO(trown): Remove this shim when we no longer need to use the
    # old style double release files.

    # Remove unspected side-effects
    modified_releases_name = releases_names.copy()

    oc_deploy_release = releases_names['overcloud_deploy_release']
    oc_target_release = releases_names['overcloud_target_release']
    uc_install_release = releases_names['undercloud_install_release']

    if oc_deploy_release != oc_target_release:
        release_file = "{}-undercloud-{}-overcloud".format(
            uc_install_release, oc_deploy_release
        )
        modified_releases_name['undercloud_install_release'] = release_file
        modified_releases_name['undercloud_target_release'] = release_file
        modified_releases_name['overcloud_deploy_release'] = release_file
        modified_releases_name['overcloud_target_release'] = release_file
    elif is_periodic:
        for key in [
            'undercloud_install_release',
            'undercloud_target_release',
            'overcloud_deploy_release',
            'overcloud_target_release',
            'standalone_deploy_release',
            'standalone_target_release',
        ]:
            modified_releases_name[key] = (
                "promotion-testing-hash-" + releases_names[key]
            )

    return modified_releases_name


def write_releases_dictionary_to_bash(
    releases_dictionary: Dict[str, str], bash_file_name
):
    logger = logging.getLogger('emit-releases')
    # Make it deterministic, expected constants in the proper order
    try:
        bash_script = '''#!/bin/env bash
export UNDERCLOUD_INSTALL_RELEASE="{undercloud_install_release}"
export UNDERCLOUD_INSTALL_HASH="{undercloud_install_hash}"
export UNDERCLOUD_TARGET_RELEASE="{undercloud_target_release}"
export UNDERCLOUD_TARGET_HASH="{undercloud_target_hash}"
export OVERCLOUD_DEPLOY_RELEASE="{overcloud_deploy_release}"
export OVERCLOUD_DEPLOY_HASH="{overcloud_deploy_hash}"
export OVERCLOUD_TARGET_RELEASE="{overcloud_target_release}"
export OVERCLOUD_TARGET_HASH="{overcloud_target_hash}"
export STANDALONE_DEPLOY_RELEASE="{standalone_deploy_release}"
export STANDALONE_DEPLOY_HASH="{standalone_deploy_hash}"
export STANDALONE_DEPLOY_NEWEST_HASH="{standalone_deploy_newest_hash}"
export STANDALONE_TARGET_RELEASE="{standalone_target_release}"
export STANDALONE_TARGET_NEWEST_HASH="{standalone_target_newest_hash}"
export STANDALONE_TARGET_HASH="{standalone_target_hash}"
'''.format(
            **releases_dictionary
        )
        with open(bash_file_name, 'w') as bash_file:
            bash_file.write(bash_script)
    except Exception:
        logger.exception("Writting releases dictionary")
        return False
    return True


if __name__ == '__main__':
    default_log_file = '{}.log'.format(os.path.basename(__file__))
    default_output_file = '{}.out'.format(os.path.basename(__file__))

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description='Get a dictionary of releases from a release '
        'and a featureset file.',
    )
    parser.add_argument(
        '--stable-release',
        choices=RELEASES,
        required=True,
        help='Release that the change being tested is from.\n'
        'All other releases are calculated from this\n'
        'basis.',
    )
    parser.add_argument(
        '--distro-name', choices=['centos'], required=True, help='Distribution name'
    )
    parser.add_argument(
        '--distro-version',
        choices=['7', '8', '9'],
        required=True,
        help='Distribution version',
    )
    parser.add_argument(
        '--featureset-file',
        required=True,
        help='Featureset file which will be introspected to\n'
        'infer what type of upgrade is being performed\n'
        '(if any).',
    )
    parser.add_argument(
        '--output-file',
        default=default_output_file,
        help='Output file containing dictionary of releases\n'
        'for the provided featureset and release.\n'
        '(default: %(default)s)',
    )
    parser.add_argument(
        '--log-file',
        default=default_log_file,
        help='log file to print debug information from\n'
        'running the script.\n'
        '(default: %(default)s)',
    )
    parser.add_argument(
        '--upgrade-from',
        action='store_false',
        help='Upgrade FROM the change under test instead\n'
        'of the default of upgrading TO the change\n'
        'under test.',
    )

    parser.add_argument(
        '--is-periodic',
        action='store_true',
        help='Specify if the current running job is periodic',
    )

    parser.add_argument(
        '--target-branch-override',
        help='Override to use this branch for the target version - required\n'
        'with the --content-provider-hashes argument',
    )

    parser.add_argument(
        '--install-branch-override',
        help='Override to use this branch for the install version - required\n'
        'with the --content-provider-hashes argument',
    )

    parser.add_argument(
        '--content-provider-hashes',
        help='A string representing the content provider branches and hashes\n'
        'e.g. master:abcd;wallaby:defg i.e. branch1:hash1;branch2:hash2',
    )
    args = parser.parse_args()

    setup_logging(args.log_file)
    logger = logging.getLogger('emit-releases')

    featureset = load_featureset_file(args.featureset_file)

    _content_provider_hashes = None
    # when overriding with content-provider-hashes we expect to have
    # --install-branch-override and --target-branch-override when doing
    # undercloud upgrade, and --target only when doing minor update,
    # and that these branches exist in the passed content-provider-hashes.
    if args.content_provider_hashes:
        if args.target_branch_override is None:
            raise RuntimeError(
                "Missing --target-branch-override or --install-branch-override"
                "At least --target is required with --content-provider-hashes"
            )
        if (
            args.target_branch_override not in args.content_provider_hashes
            and args.install_branch_override not in args.content_provider_hashes
        ):
            raise RuntimeError(
                "The passed content provider hashes ({}) does not contain"
                " the branches specified by --target-branch-override ({}) or"
                " --install-branch-override ({})".format(
                    args.content_provider_hashes,
                    args.target_branch_override,
                    args.install_branch_override,
                )
            )

        _content_provider_hashes = {}
        # args.content_provider_hashes 'master:1;wallaby:2'
        for keyval in args.content_provider_hashes.split(';'):
            dict_key = keyval.split(':')[0]
            dict_val = keyval.split(':')[1]
            _content_provider_hashes.update({dict_key: dict_val})

    releases_dictionary = compose_releases_dictionary(
        args.stable_release,
        featureset,
        args.upgrade_from,
        args.is_periodic,
        args.distro_name,
        args.distro_version,
        args.target_branch_override,
        args.install_branch_override,
        _content_provider_hashes,
    )

    releases_dictionary = shim_convert_old_release_names(
        releases_dictionary, args.is_periodic
    )

    if not write_releases_dictionary_to_bash(releases_dictionary, args.output_file):
        exit(1)
