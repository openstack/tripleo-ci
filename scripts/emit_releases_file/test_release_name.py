from emit_releases_file import compose_releases_dictionary

import pytest


@pytest.mark.parametrize('stable_release,expected_releases',
                         [('master', {
                             'undercloud_install_release': 'master',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'master',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'master',
                             'overcloud_target_hash': 'current-tripleo',
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'current-tripleo',
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'current-tripleo',
                         })])
def test_overcloud_upgrade_is_n_minus_one_to_n(stable_release,
                                               expected_releases):
    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }
    assert (compose_releases_dictionary(stable_release,
                                        featureset) == expected_releases)


@pytest.mark.parametrize('stable_release,expected_releases', [
    ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'newton',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
    }),
])
def test_ffu_overcloud_upgrade_is_n_minus_three_to_n(stable_release,
                                                     expected_releases):
    featureset = {
        'mixed_upgrade': True,
        'ffu_overcloud_upgrade': True,
    }
    assert (compose_releases_dictionary(stable_release,
                                        featureset) == expected_releases)


@pytest.mark.parametrize('stable_release,expected_releases', [
    ('master', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }),
])
def test_undercloud_upgrade_is_n_minus_one_to_n(stable_release,
                                                expected_releases):
    featureset = {
        'undercloud_upgrade': True,
    }
    assert (compose_releases_dictionary(stable_release,
                                        featureset) == expected_releases)


@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [('master', {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }), ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'queens',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
    })])
def test_overcloud_update_target_is_hash(stable_release, expected_releases):
    featureset = {
        'overcloud_update': True,
    }
    assert (compose_releases_dictionary(stable_release,
                                        featureset) == expected_releases)


@pytest.mark.parametrize('stable_release,expected_releases',
                         [('master', {
                             'undercloud_install_release': 'master',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'master',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'master',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'master',
                             'overcloud_target_hash': 'current-tripleo',
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'current-tripleo',
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'current-tripleo',
                         }), ('ocata', {
                             'undercloud_install_release': 'ocata',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'ocata',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'ocata',
                             'overcloud_target_hash': 'current-tripleo',
                         })])
def test_noop_target_is_the_same(stable_release, expected_releases):
    featureset = {}
    assert (compose_releases_dictionary(stable_release,
                                        featureset) == expected_releases)
