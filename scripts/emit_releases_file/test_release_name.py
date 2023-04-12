from emit_releases_file import compose_releases_dictionary

from unittest import mock
import pytest


@pytest.fixture
def hash_mock_setup():
    # We need this variables to be arrays to emulate a reference in python
    # https://stackoverflow.com/questions/12116127/python-yield-generator-variable-scope
    # For python3 we have special keyword nonlocal so we can refer the variable
    # in the inner factory function
    setup_mock = []
    calls_args = []

    def _hash_mock_setup(get_hash_mock, calls):
        get_hash_mock.side_effect = lambda r, h, t, s: calls[(r, h)]

        # Store the references to use them at tear down
        setup_mock.append(get_hash_mock)
        calls_args.append(
            [mock.call(cargs[0], cargs[1], 'centos', '7') for cargs in calls]
        )

    yield _hash_mock_setup

    # Tear down code here
    setup_mock[0].assert_has_calls(calls_args[0], any_order=True)


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'master',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'master',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'zed',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'master',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'master',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'master',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'zed',
            {
                'undercloud_install_release': 'zed',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'zed',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'zed',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'zed',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'zed',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_overcloud_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (
                expected_releases['overcloud_deploy_release'],
                'current-tripleo',
            ): 'previous-current-tripleo',
        },
    )

    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'master',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'master',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'zed',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'master',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'master',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'master',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'zed',
            {
                'undercloud_install_release': 'zed',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'zed',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'zed',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'zed',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'zed',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_period_overcloud_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'tripleo-ci-testing'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (
                expected_releases['overcloud_deploy_release'],
                'current-tripleo',
            ): 'previous-current-tripleo',
        },
    )

    featureset = {
        'mixed_upgrade': True,
        'overcloud_upgrade': True,
    }
    upgrade_from = False
    assert (
        compose_releases_dictionary(
            stable_release, featureset, upgrade_from, is_periodic=True
        )
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'zed',
                'undercloud_install_hash': 'previous-current-tripleo',
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
            },
        ),
        (
            'zed',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'previous-current-tripleo',
                'undercloud_target_release': 'zed',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'zed',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'zed',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'zed',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'zed',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'previous-current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'previous-current-tripleo',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'train',
                'undercloud_install_hash': 'previous-current-tripleo',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_undercloud_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['undercloud_install_release']
    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'current-tripleo'): 'previous-current-tripleo',
        },
    )

    featureset = {
        'undercloud_upgrade': True,
    }

    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'zed',
                'undercloud_install_hash': 'previous-current-tripleo',
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
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'previous-current-tripleo',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_period_undercloud_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['undercloud_install_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'tripleo-ci-testing'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'current-tripleo'): 'previous-current-tripleo',
        },
    )

    featureset = {
        'undercloud_upgrade': True,
    }

    upgrade_from = False
    assert (
        compose_releases_dictionary(
            stable_release, featureset, upgrade_from, is_periodic=True
        )
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'master',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'master',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'master',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'master',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'zed',
                'standalone_deploy_newest_hash': 'old-current',
                'standalone_deploy_hash': 'previous-current-tripleo',
                'standalone_target_release': 'master',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_standalone_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['standalone_deploy_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'current-tripleo'): 'previous-current-tripleo',
            (expected_release, 'current'): 'old-current',
        },
    )

    featureset = {
        'standalone_upgrade': True,
    }

    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'master',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'master',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'master',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'master',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'zed',
                'standalone_deploy_newest_hash': 'old-current',
                'standalone_deploy_hash': 'previous-current-tripleo',
                'standalone_target_release': 'master',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'old-current',
                'standalone_deploy_hash': 'previous-current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_period_standalone_upgrade_is_n_minus_one_to_n(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['standalone_deploy_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'tripleo-ci-testing'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'current-tripleo'): 'previous-current-tripleo',
            (expected_release, 'current'): 'old-current',
        },
    )

    featureset = {
        'standalone_upgrade': True,
    }
    upgrade_from = False
    assert (
        compose_releases_dictionary(
            stable_release, featureset, upgrade_from, is_periodic=True
        )
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'train',
            {
                'undercloud_install_release': 'train',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'train',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'train',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_deploy_release': 'train',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
                'standalone_target_release': 'train',
            },
        ),
    ],
)
def test_overcloud_update_train_target_is_hash(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['overcloud_deploy_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'previous-current-tripleo'): 'previous-current-tripleo',
        },
    )

    featureset = {
        'overcloud_update': True,
    }

    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
                'undercloud_install_release': 'master',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'master',
                'undercloud_target_hash': 'current',
                'overcloud_deploy_release': 'master',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'master',
                'overcloud_target_hash': 'current',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_deploy_release': 'master',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
                'standalone_target_release': 'master',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
    ],
)
def test_overcloud_minor_update_target_is_hash(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['overcloud_deploy_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
            (expected_release, 'current'): 'current',
        },
    )

    featureset = {
        'minor_update': True,
    }

    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
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
                'standalone_target_release': 'master',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'train',
            {
                'undercloud_install_release': 'train',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'train',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'previous-current-tripleo',
                'overcloud_target_release': 'train',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'train',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'train',
            },
        ),
    ],
)
def test_periodic_overcloud_update_target_is_hash(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    expected_release = expected_releases['overcloud_deploy_release']

    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'tripleo-ci-testing'): 'tripleo-ci-testing',
            (stable_release, 'current'): 'current',
            (expected_release, 'previous-current-tripleo'): 'previous-current-tripleo',
        },
    )

    featureset = {
        'overcloud_update': True,
    }
    upgrade_from = False
    assert (
        compose_releases_dictionary(
            stable_release, featureset, upgrade_from, is_periodic=True
        )
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
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
                'standalone_target_release': 'master',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
            },
        ),
        (
            'train',
            {
                'undercloud_install_release': 'train',
                'undercloud_install_hash': 'current-tripleo',
                'undercloud_target_release': 'train',
                'undercloud_target_hash': 'current-tripleo',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'current-tripleo',
                'overcloud_target_release': 'train',
                'overcloud_target_hash': 'current-tripleo',
                'standalone_deploy_hash': 'current-tripleo',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_release': 'train',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'current-tripleo',
                'standalone_target_release': 'train',
            },
        ),
    ],
)
def test_noop_target_is_the_same(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'current-tripleo'): 'current-tripleo',
            (stable_release, 'current'): 'current',
        },
    )

    featureset = {}
    upgrade_from = False
    assert (
        compose_releases_dictionary(stable_release, featureset, upgrade_from)
        == expected_releases
    )


@mock.patch('emit_releases_file.get_dlrn_hash')
@pytest.mark.parametrize(
    'stable_release,expected_releases',
    [
        (
            'master',
            {
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
                'standalone_target_release': 'master',
            },
        ),
        (
            'wallaby',
            {
                'undercloud_install_release': 'wallaby',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'wallaby',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'wallaby',
                'overcloud_deploy_hash': 'tripleo-ci-testing',
                'overcloud_target_release': 'wallaby',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'wallaby',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'wallaby',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'victoria',
            {
                'undercloud_install_release': 'victoria',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'victoria',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'victoria',
                'overcloud_deploy_hash': 'tripleo-ci-testing',
                'overcloud_target_release': 'victoria',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'victoria',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'victoria',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'ussuri',
            {
                'undercloud_install_release': 'ussuri',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'ussuri',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'ussuri',
                'overcloud_deploy_hash': 'tripleo-ci-testing',
                'overcloud_target_release': 'ussuri',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'ussuri',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'ussuri',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
            },
        ),
        (
            'train',
            {
                'undercloud_install_release': 'train',
                'undercloud_install_hash': 'tripleo-ci-testing',
                'undercloud_target_release': 'train',
                'undercloud_target_hash': 'tripleo-ci-testing',
                'overcloud_deploy_release': 'train',
                'overcloud_deploy_hash': 'tripleo-ci-testing',
                'overcloud_target_release': 'train',
                'overcloud_target_hash': 'tripleo-ci-testing',
                'standalone_deploy_newest_hash': 'current',
                'standalone_deploy_hash': 'tripleo-ci-testing',
                'standalone_deploy_release': 'train',
                'standalone_target_newest_hash': 'current',
                'standalone_target_hash': 'tripleo-ci-testing',
                'standalone_target_release': 'train',
            },
        ),
    ],
)
def test_periodic_noop_target_is_the_same(
    hash_mock, hash_mock_setup, stable_release, expected_releases
):
    hash_mock_setup(
        hash_mock,
        {
            (stable_release, 'tripleo-ci-testing'): 'tripleo-ci-testing',
            (stable_release, 'current'): 'current',
        },
    )

    featureset = {}
    upgrade_from = False
    assert (
        compose_releases_dictionary(
            stable_release, featureset, upgrade_from, is_periodic=True
        )
        == expected_releases
    )
