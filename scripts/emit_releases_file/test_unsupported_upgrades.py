from emit_releases_file import compose_releases_dictionary
import pytest


@pytest.mark.parametrize('featureset', [{
    'mixed_upgrade': True,
    'overcloud_upgrade': True
}, {
    'undercloud_upgrade': True
}])
def test_upgrade_to_newton_is_unsupported(featureset):
    stable_release = 'newton'
    upgrade_from = False
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset, upgrade_from)


def test_only_mixed_overcloud_upgrades_are_supported():
    featureset = {
        'overcloud_upgrade': True,
        'undercloud_upgrade': True,
    }

    stable_release = 'queens'
    upgrade_from = False
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset, upgrade_from)


def test_undercloud_upgrades_from_newton_to_ocata_are_unsupported():
    featureset = {
        'undercloud_upgrade': True,
    }

    stable_release = 'ocata'
    upgrade_from = False
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset, upgrade_from)


@pytest.mark.parametrize('upgrade_type',
                         ['ffu_overcloud_upgrade', 'overcloud_upgrade'])
def test_overcloud_upgrades_has_to_be_mixed(upgrade_type):
    featureset = {
        upgrade_type: True,
    }
    stable_release = 'queens'
    upgrade_from = False
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset, upgrade_from)


@pytest.mark.parametrize('stable_release',
                         ['ocata', 'pike', 'newton', 'master'])
def test_ffu_overcloud_upgrade_only_supported_from_newton(stable_release):
    featureset = {
        'mixed_upgrade': True,
        'ffu_overcloud_upgrade': True,
    }
    upgrade_from = False
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset, upgrade_from)


def test_fail_with_wrong_release():
    with pytest.raises(RuntimeError):
        compose_releases_dictionary('foobar', {}, False)
