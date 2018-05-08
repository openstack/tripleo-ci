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
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset)


def test_only_mixed_overcloud_upgrades_are_supported():
    featureset = {
        'overcloud_upgrade': True,
        'undercloud_upgrade': True,
    }

    stable_release = 'queens'
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset)


@pytest.mark.parametrize('upgrade_type',
                         ['ffu_overcloud_upgrade', 'overcloud_upgrade'])
def test_overcloud_upgrades_has_to_be_mixed(upgrade_type):
    featureset = {
        upgrade_type: True,
    }
    stable_release = 'queens'
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset)


@pytest.mark.parametrize('stable_release',
                         ['ocata', 'pike', 'newton', 'master'])
def test_ffu_overcloud_upgrade_only_supported_from_newton(stable_release):
    featureset = {
        'mixed_upgrade': True,
        'ffu_overcloud_upgrade': True,
    }
    with pytest.raises(RuntimeError):
        compose_releases_dictionary(stable_release, featureset)


def test_fail_with_wrong_release():
    with pytest.raises(RuntimeError):
        compose_releases_dictionary('foobar', {})
