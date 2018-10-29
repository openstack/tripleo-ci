from emit_releases_file import compose_releases_dictionary

import mock
import pytest


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases',
                         [('master', {
                             'undercloud_install_release': 'master',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'master',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'rocky',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'master',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'master',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'master',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('rocky', {
                             'undercloud_install_release': 'rocky',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'rocky',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'rocky',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'rocky',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'rocky',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'queens',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'queens',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'pike',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'pike',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         })])
def test_overcloud_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                               stable_release,
                                               expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo'),
             mock.call(expected_releases['overcloud_deploy_release'],
             'current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases',
                         [('master', {
                             'undercloud_install_release': 'master',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'master',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'rocky',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'master',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'master',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'master',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('rocky', {
                             'undercloud_install_release': 'rocky',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'rocky',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'rocky',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'rocky',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'rocky',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'queens',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'queens',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'old-current-tripleo',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_release': 'pike',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_target_release': 'pike',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                         })])
def test_period_overcloud_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                                      stable_release,
                                                      expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing'),
             mock.call(expected_releases['overcloud_deploy_release'],
             'current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'newton',
        'overcloud_deploy_hash': 'old-current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'queens',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'queens',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_ffu_overcloud_upgrade_is_n_minus_three_to_n(mock_get_hash,
                                                     stable_release,
                                                     expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'mixed_upgrade': True,
        'ffu_overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo'),
             mock.call(expected_releases['overcloud_deploy_release'],
             'current-passed-ci')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'newton',
        'overcloud_deploy_hash': 'old-current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'queens',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'queens',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_period_ffu_overcloud_upgrade_is_n_minus_three_to_n(mock_get_hash,
                                                            stable_release,
                                                            expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'mixed_upgrade': True,
        'ffu_overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing'),
             mock.call(expected_releases['overcloud_deploy_release'],
             'current-passed-ci')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('master', {
        'undercloud_install_release': 'rocky',
        'undercloud_install_hash': 'old-current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'master',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
    ('rocky', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'old-current-tripleo',
        'undercloud_target_release': 'rocky',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'rocky',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'rocky',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'rocky',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'rocky',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
    ('queens', {
        'undercloud_install_release': 'pike',
        'undercloud_install_hash': 'old-current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'queens',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'queens',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'queens',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
    ('pike', {
        'undercloud_install_release': 'ocata',
        'undercloud_install_hash': 'old-current-tripleo',
        'undercloud_target_release': 'pike',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'pike',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'pike',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'pike',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'pike',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_undercloud_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                                stable_release,
                                                expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'undercloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo'),
             mock.call(expected_releases['undercloud_install_release'],
             'current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('master', {
        'undercloud_install_release': 'rocky',
        'undercloud_install_hash': 'old-current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'master',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_period_undercloud_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                                       stable_release,
                                                       expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo']
    featureset = {
        'undercloud_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing'),
             mock.call(expected_releases['undercloud_install_release'],
             'current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('master', {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'rocky',
        'standalone_deploy_newest_hash': 'old-current',
        'standalone_deploy_hash': 'old-current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_standalone_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                                stable_release,
                                                expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo',
                                 'old-current']
    featureset = {
        'standalone_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo'),
             mock.call(expected_releases['standalone_deploy_release'],
                       'current-tripleo'),
             mock.call(expected_releases['standalone_deploy_release'],
                       'current')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases', [
    ('master', {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'rocky',
        'standalone_deploy_newest_hash': 'old-current',
        'standalone_deploy_hash': 'old-current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
    }),
])
def test_period_standalone_upgrade_is_n_minus_one_to_n(mock_get_hash,
                                                       stable_release,
                                                       expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'old-current-tripleo',
                                 'old-current']
    featureset = {
        'standalone_upgrade': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing'),
             mock.call(expected_releases['standalone_deploy_release'],
                       'current-tripleo'),
             mock.call(expected_releases['standalone_deploy_release'],
                       'current')])


@mock.patch('emit_releases_file.get_dlrn_hash')
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
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_deploy_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
        'standalone_target_release': 'master'
    }), ('rocky', {
        'undercloud_install_release': 'rocky',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'rocky',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'rocky',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'rocky',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_deploy_release': 'rocky',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
        'standalone_target_release': 'rocky'
    }), ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'queens',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_deploy_release': 'queens',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
        'standalone_target_release': 'queens',
    }), ('pike', {
        'undercloud_install_release': 'pike',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'pike',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'pike',
        'standalone_deploy_newest_hash': 'current',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'pike',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_deploy_release': 'pike',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
        'standalone_target_release': 'pike'
    }), ('ocata', {
        'undercloud_install_release': 'ocata',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'ocata',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'ocata',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'ocata',
        'overcloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'ocata',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_deploy_release': 'ocata',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'current-tripleo',
        'standalone_target_release': 'ocata'
    })])
def test_overcloud_update_target_is_hash(mock_get_hash,
                                         stable_release,
                                         expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'current-tripleo',
                                 'previous-current-tripleo']
    featureset = {
        'overcloud_update': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo'),
             mock.call(expected_releases['overcloud_deploy_release'],
             'previous-current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [('master', {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'tripleo-ci-testing',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'tripleo-ci-testing',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'tripleo-ci-testing',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'tripleo-ci-testing',
        'standalone_deploy_release': 'master',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'tripleo-ci-testing',
        'standalone_target_release': 'master'
    }), ('rocky', {
        'undercloud_install_release': 'rocky',
        'undercloud_install_hash': 'tripleo-ci-testing',
        'undercloud_target_release': 'rocky',
        'undercloud_target_hash': 'tripleo-ci-testing',
        'overcloud_deploy_release': 'rocky',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'rocky',
        'overcloud_target_hash': 'tripleo-ci-testing',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'tripleo-ci-testing',
        'standalone_deploy_release': 'rocky',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'tripleo-ci-testing',
        'standalone_target_release': 'rocky'
    }), ('queens', {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'tripleo-ci-testing',
        'undercloud_target_release': 'queens',
        'undercloud_target_hash': 'tripleo-ci-testing',
        'overcloud_deploy_release': 'queens',
        'overcloud_deploy_hash': 'previous-current-tripleo',
        'overcloud_target_release': 'queens',
        'overcloud_target_hash': 'tripleo-ci-testing',
        'standalone_deploy_newest_hash': 'current',
        'standalone_deploy_hash': 'tripleo-ci-testing',
        'standalone_deploy_release': 'queens',
        'standalone_target_newest_hash': 'current',
        'standalone_target_hash': 'tripleo-ci-testing',
        'standalone_target_release': 'queens'
    })])
def test_period_overcloud_update_target_is_hash(mock_get_hash,
                                                stable_release,
                                                expected_releases):
    mock_get_hash.side_effect = ['current',
                                 'tripleo-ci-testing',
                                 'previous-current-tripleo',
                                 'old-current']
    featureset = {
        'overcloud_update': True,
    }
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing'),
             mock.call(expected_releases['overcloud_deploy_release'],
                       'previous-current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
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
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_release': 'master',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                             'standalone_target_release': 'master'
                         }), ('rocky', {
                             'undercloud_install_release': 'rocky',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'rocky',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'rocky',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'rocky',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_deploy_release': 'rocky',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                             'standalone_target_release': 'rocky'
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_deploy_release': 'queens',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                             'standalone_target_release': 'queens'
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_deploy_release': 'pike',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                             'standalone_target_release': 'pike'
                         }), ('ocata', {
                             'undercloud_install_release': 'ocata',
                             'undercloud_install_hash': 'current-tripleo',
                             'undercloud_target_release': 'ocata',
                             'undercloud_target_hash': 'current-tripleo',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'current-tripleo',
                             'overcloud_target_release': 'ocata',
                             'overcloud_target_hash': 'current-tripleo',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'current-tripleo',
                             'standalone_deploy_release': 'ocata',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'current-tripleo',
                             'standalone_target_release': 'ocata'
                         })])
def test_noop_target_is_the_same(mock_get_hash,
                                 stable_release,
                                 expected_releases):
    mock_get_hash.side_effect = ['current', 'current-tripleo']
    featureset = {}
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'current-tripleo')])


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize('stable_release,expected_releases',
                         [('master', {
                             'undercloud_install_release': 'master',
                             'undercloud_install_hash': 'tripleo-ci-testing',
                             'undercloud_target_release': 'master',
                             'undercloud_target_hash': 'tripleo-ci-testing',
                             'overcloud_deploy_release': 'master',
                             'overcloud_deploy_hash': 'tripleo-ci-testing',
                             'overcloud_target_release': 'master',
                             'overcloud_target_hash': 'tripleo-ci-testing',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'tripleo-ci-testing',
                             'standalone_deploy_release': 'master',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'tripleo-ci-testing',
                             'standalone_target_release': 'master'
                         }), ('rocky', {
                             'undercloud_install_release': 'rocky',
                             'undercloud_install_hash': 'tripleo-ci-testing',
                             'undercloud_target_release': 'rocky',
                             'undercloud_target_hash': 'tripleo-ci-testing',
                             'overcloud_deploy_release': 'rocky',
                             'overcloud_deploy_hash': 'tripleo-ci-testing',
                             'overcloud_target_release': 'rocky',
                             'overcloud_target_hash': 'tripleo-ci-testing',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'tripleo-ci-testing',
                             'standalone_deploy_release': 'rocky',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'tripleo-ci-testing',
                             'standalone_target_release': 'rocky'
                         }), ('queens', {
                             'undercloud_install_release': 'queens',
                             'undercloud_install_hash': 'tripleo-ci-testing',
                             'undercloud_target_release': 'queens',
                             'undercloud_target_hash': 'tripleo-ci-testing',
                             'overcloud_deploy_release': 'queens',
                             'overcloud_deploy_hash': 'tripleo-ci-testing',
                             'overcloud_target_release': 'queens',
                             'overcloud_target_hash': 'tripleo-ci-testing',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'tripleo-ci-testing',
                             'standalone_deploy_release': 'queens',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'tripleo-ci-testing',
                             'standalone_target_release': 'queens'
                         }), ('pike', {
                             'undercloud_install_release': 'pike',
                             'undercloud_install_hash': 'tripleo-ci-testing',
                             'undercloud_target_release': 'pike',
                             'undercloud_target_hash': 'tripleo-ci-testing',
                             'overcloud_deploy_release': 'pike',
                             'overcloud_deploy_hash': 'tripleo-ci-testing',
                             'overcloud_target_release': 'pike',
                             'overcloud_target_hash': 'tripleo-ci-testing',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'tripleo-ci-testing',
                             'standalone_deploy_release': 'pike',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'tripleo-ci-testing',
                             'standalone_target_release': 'pike'
                         }), ('ocata', {
                             'undercloud_install_release': 'ocata',
                             'undercloud_install_hash': 'tripleo-ci-testing',
                             'undercloud_target_release': 'ocata',
                             'undercloud_target_hash': 'tripleo-ci-testing',
                             'overcloud_deploy_release': 'ocata',
                             'overcloud_deploy_hash': 'tripleo-ci-testing',
                             'overcloud_target_release': 'ocata',
                             'overcloud_target_hash': 'tripleo-ci-testing',
                             'standalone_deploy_newest_hash': 'current',
                             'standalone_deploy_hash': 'tripleo-ci-testing',
                             'standalone_deploy_release': 'ocata',
                             'standalone_target_newest_hash': 'current',
                             'standalone_target_hash': 'tripleo-ci-testing',
                             'standalone_target_release': 'ocata'
                         })])
def test_periodic_noop_target_is_the_same(mock_get_hash,
                                          stable_release,
                                          expected_releases):
    mock_get_hash.side_effect = ['current', 'tripleo-ci-testing']
    featureset = {}
    upgrade_from = False
    assert (compose_releases_dictionary(stable_release,
                                        featureset,
                                        upgrade_from,
                                        is_periodic=True) == expected_releases)
    mock_get_hash.assert_has_calls(
            [mock.call(stable_release, 'current'),
             mock.call(stable_release, 'tripleo-ci-testing')])
