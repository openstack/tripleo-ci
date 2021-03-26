from emit_releases_file import shim_convert_old_release_names


def test_converting_from_oc_upgrade_has_double_release():
    releases_name = {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'queens',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }
    expected_releases_file = {
        'undercloud_install_release': 'master-undercloud-queens-overcloud',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master-undercloud-queens-overcloud',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master-undercloud-queens-overcloud',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master-undercloud-queens-overcloud',
        'overcloud_target_hash': 'current-tripleo',
    }

    assert (
        shim_convert_old_release_names(releases_name, is_periodic=False)
        == expected_releases_file
    )

    # Also periodic jobs use the same release files
    assert (
        shim_convert_old_release_names(releases_name, is_periodic=True)
        == expected_releases_file
    )


def test_converting_from_uc_upgrade_has_single_release():
    releases_name = {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }
    expected_releases_file = {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }
    assert (
        shim_convert_old_release_names(releases_name, is_periodic=False)
        == expected_releases_file
    )


def test_converting_from_periodic_uc_upgrade_has_single_release_with_sufix():
    releases_name = {
        'undercloud_install_release': 'queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'stein',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_hash': 'current-tripleo',
    }
    expected_releases_file = {
        'undercloud_install_release': 'promotion-testing-hash-queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'promotion-testing-hash-master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'promotion-testing-hash-master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'promotion-testing-hash-master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'promotion-testing-hash-stein',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'promotion-testing-hash-master',
        'standalone_target_hash': 'current-tripleo',
    }
    assert (
        shim_convert_old_release_names(releases_name, is_periodic=True)
        == expected_releases_file
    )


def test_converting_from_noop_has_single_release():
    releases_name = {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }
    expected_releases_file = {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
    }
    assert (
        shim_convert_old_release_names(releases_name, is_periodic=False)
        == expected_releases_file
    )


def test_converting_from_periodic_noop_has_single_release_with_sufix():
    releases_name = {
        'undercloud_install_release': 'master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'stein',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'master',
        'standalone_target_hash': 'current-tripleo',
    }
    expected_releases_file = {
        'undercloud_install_release': 'promotion-testing-hash-master',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'promotion-testing-hash-master',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'promotion-testing-hash-master',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'promotion-testing-hash-master',
        'overcloud_target_hash': 'current-tripleo',
        'standalone_deploy_release': 'promotion-testing-hash-stein',
        'standalone_deploy_hash': 'current-tripleo',
        'standalone_target_release': 'promotion-testing-hash-master',
        'standalone_target_hash': 'current-tripleo',
    }
    assert (
        shim_convert_old_release_names(releases_name, is_periodic=True)
        == expected_releases_file
    )
