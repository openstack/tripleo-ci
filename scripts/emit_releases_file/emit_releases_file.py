import argparse
import logging
import logging.handlers
import os
import re
import requests
import yaml

# Define releases
RELEASES = ['newton', 'ocata', 'pike', 'queens', 'master']
# Define long term releases
LONG_TERM_SUPPORT_RELEASES = ['queens']


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


def get_dlrn_hash(release, hash_name, retries=10):
    logger = logging.getLogger('emit-releases')
    full_hash_pattern = re.compile('[a-z,0-9]{40}_[a-z,0-9]{8}')
    repo_url = ('https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo'
                % (release, hash_name))
    for retry_num in range(retries):
        repo_file = None
        # Timeout if initial connection is longer than default
        # TCP packet retransmission window (3 secs), or if the
        # sending of the data takes more than 27 seconds.
        try:
            repo_file = requests.get(repo_url, timeout=(3.05, 27))
        except Exception as e:
            logger.exception(e)
            pass
        else:
            if repo_file is not None and repo_file.ok:
                break

    if repo_file is None or not repo_file.ok:
        raise RuntimeError("Failed to retrieve repo file from {} after "
                           "{} retries".format(repo_url, retries))

    full_hash = full_hash_pattern.findall(repo_file.content)
    return full_hash[0]


def compose_releases_dictionary(stable_release, featureset):
    logger = logging.getLogger('emit-releases')
    if stable_release not in RELEASES:
        raise RuntimeError("The {} release is not supported by this tool"
                           "Supported releases: {}".format(
                               stable_release, RELEASES))

    if (featureset.get('overcloud_upgrade') or
        featureset.get('undercloud_upgrade')) and \
            stable_release == RELEASES[0]:
        raise RuntimeError("Cannot upgrade to {}".format(RELEASES[0]))

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

    releases_dictionary = {
        'undercloud_install_release': stable_release,
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': stable_release,
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': stable_release,
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': stable_release,
        'overcloud_target_hash': 'current-tripleo'
    }

    if featureset.get('mixed_upgrade'):
        if featureset.get('overcloud_upgrade'):
            logger.info('Doing an overcloud upgrade')
            deploy_release = get_relative_release(stable_release, -1)
            releases_dictionary['overcloud_deploy_release'] = deploy_release

        elif featureset.get('ffu_overcloud_upgrade'):
            logger.info('Doing an overcloud fast forward upgrade')
            deploy_release = get_relative_release(stable_release, -3)
            releases_dictionary['overcloud_deploy_release'] = deploy_release

    elif featureset.get('undercloud_upgrade'):
        logger.info('Doing an undercloud upgrade')
        install_release = get_relative_release(stable_release, -1)
        releases_dictionary['undercloud_install_release'] = install_release

    elif featureset.get('overcloud_update'):
        logger.info('Doing an overcloud update')
        releases_dictionary['overcloud_deploy_hash'] = \
            'previous-current-tripleo'

    logger.debug("stable_release: %s, featureset: %s", stable_release,
                 featureset)

    logger.info('output releases: %s', releases_dictionary)

    return releases_dictionary


def shim_convert_old_release_names(releases_names):
    # TODO(trown): Remove this shim when we no longer need to use the
    # old style double release files.

    oc_deploy_release = releases_names['overcloud_deploy_release']
    oc_target_release = releases_names['overcloud_target_release']
    uc_install_release = releases_names['undercloud_install_release']

    if oc_deploy_release != oc_target_release:
        release_file = "undercloud-{}-overcloud-{}".format(
            uc_install_release, oc_deploy_release)
        releases_names['undercloud_install_release'] = release_file
        releases_names['undercloud_target_release'] = release_file
        releases_names['overcloud_deploy_release'] = release_file
        releases_names['overcloud_target_release'] = release_file

    return releases_names


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
    args = parser.parse_args()

    setup_logging(args.log_file)
    logger = logging.getLogger('emit-releases')

    featureset = load_featureset_file(args.featureset_file)

    releases_dictionary = compose_releases_dictionary(args.stable_release,
                                                      featureset)

    releases_dictionary = shim_convert_old_release_names(
        releases_dictionary)
