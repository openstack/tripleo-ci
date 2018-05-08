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
        'undercloud_install_release': 'undercloud-master-overcloud-queens',
        'undercloud_install_hash': 'current-tripleo',
        'undercloud_target_release': 'undercloud-master-overcloud-queens',
        'undercloud_target_hash': 'current-tripleo',
        'overcloud_deploy_release': 'undercloud-master-overcloud-queens',
        'overcloud_deploy_hash': 'current-tripleo',
        'overcloud_target_release': 'undercloud-master-overcloud-queens',
        'overcloud_target_hash': 'current-tripleo',
    }
    assert (shim_convert_old_release_names(releases_name) ==
            expected_releases_file)


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
    assert (shim_convert_old_release_names(releases_name) ==
            expected_releases_file)


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
    assert (shim_convert_old_release_names(releases_name) ==
            expected_releases_file)
