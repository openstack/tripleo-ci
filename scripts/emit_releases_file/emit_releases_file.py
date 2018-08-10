import argparse
import logging
import logging.handlers
import os
import re
import requests
import yaml

# Define releases
RELEASES = ['newton', 'ocata', 'pike', 'queens', 'rocky', 'master']
# Define long term releases
LONG_TERM_SUPPORT_RELEASES = ['queens']

# NAMED DLRN HASHES
NEWTON_HASH_NAME = 'current-passed-ci'
CURRENT_HASH_NAME = 'current-tripleo'
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
    log_handler = logging.handlers.WatchedFileHandler(
        os.path.expanduser(log_file))
    logger.addHandler(log_handler)


def load_featureset_file(featureset_file):
    logger = logging.getLogger('emit-releases')
    try:
        with open(featureset_file, 'r') as stream:
            featureset = yaml.safe_load(stream)
    except Exception as e:
        logger.error("The featureset file: {} can not be "
                     "opened.".format(featureset_file))
        logger.exception(e)
        raise e
    return featureset


def get_dlrn_hash(release, hash_name, retries=10, timeout=4):
    logger = logging.getLogger('emit-releases')
    full_hash_pattern = re.compile('[a-z,0-9]{40}_[a-z,0-9]{8}')
    repo_url = ('https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' %
                (release, hash_name))
    for retry_num in range(retries):
        repo_file = None
        try:
            repo_file = requests.get(repo_url, timeout=timeout)
        except Exception as e:
            logger.warning("Attempt {} of {} to get DLRN hash threw an "
                           "exception.".format(retry_num + 1, retries))
            logger.exception(e)
            pass
        else:
            if repo_file is not None and repo_file.ok:
                break

            elif repo_file:
                logger.warning("Attempt {} of {} to get DLRN hash returned "
                               "status code {}.".format(retry_num + 1,
                                                        retries,
                                                        repo_file.status_code))
            else:
                logger.warning("Attempt {} of {} to get DLRN hash failed to "
                               "get a response.".format(retry_num + 1,
                                                        retries))

    if repo_file is None or not repo_file.ok:
        raise RuntimeError("Failed to retrieve repo file from {} after "
                           "{} retries".format(repo_url, retries))

    full_hash = full_hash_pattern.findall(repo_file.text)
    logger.info("Got DLRN hash: {} for the named hash: {} on the {} "
                "release".format(full_hash[0], hash_name, release))
    return full_hash[0]


def compose_releases_dictionary(stable_release, featureset, upgrade_from,
                                is_periodic=False):
    logger = logging.getLogger('emit-releases')
    if stable_release not in RELEASES:
        raise RuntimeError("The {} release is not supported by this tool"
                           "Supported releases: {}".format(
                               stable_release, RELEASES))

    if (featureset.get('overcloud_upgrade') or
        featureset.get('undercloud_upgrade')) and \
            stable_release == RELEASES[0]:
        raise RuntimeError("Cannot upgrade to {}".format(RELEASES[0]))

    if featureset.get('undercloud_upgrade') and stable_release == 'ocata':
        raise RuntimeError("Undercloud upgrades are not supported from "
                           "newton to ocata")

    if featureset.get('overcloud_upgrade') and \
       featureset.get('undercloud_upgrade'):
        raise RuntimeError("This tool currently only supports upgrading the "
                           "undercloud OR the overcloud NOT both.")

    if (featureset.get('overcloud_upgrade') or
        featureset.get('ffu_overcloud_upgrade')) and \
            not featureset.get('mixed_upgrade'):
        raise RuntimeError("Overcloud upgrade has to be mixed upgrades")

    if featureset.get('ffu_overcloud_upgrade') and \
            stable_release not in LONG_TERM_SUPPORT_RELEASES:
        raise RuntimeError(
            "{} is not a long-term support release, and cannot be "
            "used in a fast forward upgrade. Current long-term support "
            "releases:  {}".format(stable_release, LONG_TERM_SUPPORT_RELEASES))

    if stable_release == 'newton':
        current_hash = get_dlrn_hash(stable_release, NEWTON_HASH_NAME)
    elif is_periodic:
        current_hash = get_dlrn_hash(stable_release, PROMOTION_HASH_NAME)
    else:
        current_hash = get_dlrn_hash(stable_release, CURRENT_HASH_NAME)

    releases_dictionary = {
        'undercloud_install_release': stable_release,
        'undercloud_install_hash': current_hash,
        'undercloud_target_release': stable_release,
        'undercloud_target_hash': current_hash,
        'overcloud_deploy_release': stable_release,
        'overcloud_deploy_hash': current_hash,
        'overcloud_target_release': stable_release,
        'overcloud_target_hash': current_hash
    }

    if featureset.get('mixed_upgrade'):
        if featureset.get('overcloud_upgrade'):
            logger.info('Doing an overcloud upgrade')
            deploy_release = get_relative_release(stable_release, -1)
            if deploy_release == 'newton':
                deploy_hash = get_dlrn_hash(deploy_release, NEWTON_HASH_NAME)
            else:
                deploy_hash = get_dlrn_hash(deploy_release, CURRENT_HASH_NAME)
            releases_dictionary['overcloud_deploy_release'] = deploy_release
            releases_dictionary['overcloud_deploy_hash'] = deploy_hash

        elif featureset.get('ffu_overcloud_upgrade'):
            logger.info('Doing an overcloud fast forward upgrade')
            deploy_release = get_relative_release(stable_release, -3)
            if deploy_release == 'newton':
                deploy_hash = get_dlrn_hash(deploy_release, NEWTON_HASH_NAME)
            else:
                deploy_hash = get_dlrn_hash(deploy_release, CURRENT_HASH_NAME)
            releases_dictionary['overcloud_deploy_release'] = deploy_release
            releases_dictionary['overcloud_deploy_hash'] = deploy_hash

    elif featureset.get('undercloud_upgrade'):
        logger.info('Doing an undercloud upgrade')
        install_release = get_relative_release(stable_release, -1)
        install_hash = get_dlrn_hash(install_release, CURRENT_HASH_NAME)
        releases_dictionary['undercloud_install_release'] = install_release
        releases_dictionary['undercloud_install_hash'] = install_hash

    elif featureset.get('overcloud_update'):
        logger.info('Doing an overcloud update')
        previous_hash = get_dlrn_hash(stable_release, PREVIOUS_HASH_NAME)
        releases_dictionary['overcloud_deploy_hash'] = previous_hash

    logger.debug("stable_release: %s, featureset: %s", stable_release,
                 featureset)

    logger.info('output releases: %s', releases_dictionary)

    return releases_dictionary


def shim_convert_old_release_names(releases_names, is_periodic):
    # TODO(trown): Remove this shim when we no longer need to use the
    # old style double release files.

    # Remove unspected side-effects
    modified_releases_name = releases_names.copy()

    oc_deploy_release = releases_names['overcloud_deploy_release']
    oc_target_release = releases_names['overcloud_target_release']
    uc_install_release = releases_names['undercloud_install_release']

    if oc_deploy_release != oc_target_release:
        release_file = "{}-undercloud-{}-overcloud".format(
            uc_install_release, oc_deploy_release)
        modified_releases_name['undercloud_install_release'] = release_file
        modified_releases_name['undercloud_target_release'] = release_file
        modified_releases_name['overcloud_deploy_release'] = release_file
        modified_releases_name['overcloud_target_release'] = release_file
    elif is_periodic:
        for key in [
                'undercloud_install_release', 'undercloud_target_release',
                'overcloud_deploy_release', 'overcloud_target_release'
        ]:
            modified_releases_name[
                key] = "promotion-testing-hash-" + releases_names[key]

    return modified_releases_name


def write_releases_dictionary_to_bash(releases_dictionary, bash_file_name):
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
'''.format(**releases_dictionary)
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
                         'and a featureset file.')
    parser.add_argument('--stable-release',
                        choices=RELEASES,
                        required=True,
                        help='Release that the change being tested is from.\n'
                             'All other releases are calculated from this\n'
                             'basis.')
    parser.add_argument('--featureset-file',
                        required=True,
                        help='Featureset file which will be introspected to\n'
                             'infer what type of upgrade is being performed\n'
                             '(if any).')
    parser.add_argument('--output-file', default=default_output_file,
                        help='Output file containing dictionary of releases\n'
                             'for the provided featureset and release.\n'
                             '(default: %(default)s)')
    parser.add_argument('--log-file', default=default_log_file,
                        help='log file to print debug information from\n'
                             'running the script.\n'
                             '(default: %(default)s)')
    parser.add_argument('--upgrade-from', action='store_false',
                        help='Upgrade FROM the change under test instead\n'
                             'of the default of upgrading TO the change\n'
                             'under test.')

    parser.add_argument('--is-periodic', action='store_true',
                        help='Specify if the current running job is periodic')

    args = parser.parse_args()

    setup_logging(args.log_file)
    logger = logging.getLogger('emit-releases')

    featureset = load_featureset_file(args.featureset_file)

    releases_dictionary = compose_releases_dictionary(args.stable_release,
                                                      featureset,
                                                      args.upgrade_from,
                                                      args.is_periodic)

    releases_dictionary = shim_convert_old_release_names(releases_dictionary,
                                                         args.is_periodic)

    if not write_releases_dictionary_to_bash(
            releases_dictionary, args.output_file):
        exit(1)
