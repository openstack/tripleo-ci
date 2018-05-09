import logging
import re
import requests

RELEASES = ['newton', 'ocata', 'pike', 'queens', 'master']
LONG_TERM_SUPPORT_RELEASES = ['queens']


def get_relative_release(release, relative_idx):
    current_idx = RELEASES.index(release)
    absolute_idx = current_idx + relative_idx
    return RELEASES[absolute_idx]


def get_dlrn_hash(release, hash_name, retries=10):
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
            # TODO(trown): Handle exceptions
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
            logging.info('Doing an overcloud upgrade')
            deploy_release = get_relative_release(stable_release, -1)
            releases_dictionary['overcloud_deploy_release'] = deploy_release

        elif featureset.get('ffu_overcloud_upgrade'):
            logging.info('Doing an overcloud fast forward upgrade')
            deploy_release = get_relative_release(stable_release, -3)
            releases_dictionary['overcloud_deploy_release'] = deploy_release

    elif featureset.get('undercloud_upgrade'):
        logging.info('Doing an undercloud upgrade')
        install_release = get_relative_release(stable_release, -1)
        releases_dictionary['undercloud_install_release'] = install_release

    elif featureset.get('overcloud_update'):
        logging.info('Doing an overcloud update')
        releases_dictionary['overcloud_deploy_hash'] = \
            'previous-current-tripleo'

    logging.debug("stable_release: %s, featureset: %s", stable_release,
                  featureset)

    logging.info('output releases: %s', releases_dictionary)

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

    # TODO read the feature set from a file path passed in the arguments
    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }

    # TODO read this from an argumment
    stable_release = 'queens'

    releases_dictionary = compose_releases_dictionary(stable_release,
                                                      featureset)

    releases_dictionary = shim_convert_old_release_names(
        releases_dictionary)
