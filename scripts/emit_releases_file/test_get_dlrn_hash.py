from emit_releases_file import get_dlrn_hash

from unittest import mock
import pytest


@mock.patch('logging.getLogger')
@mock.patch('requests.get')
def test_get_dlrn_hash_ok(mock_get, mock_logging):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_warning = mock.MagicMock()
    mock_log_info = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.warning = mock_log_warning
    mock_logger.info = mock_log_info
    mock_response = mock.Mock()
    mock_response.ok = True
    mock_response.text = (
        '[delorean]\nname=delorean-openstack-nova-81c23c04'
        '7e8e0fc03b54164921f49fdb4103202c\nbaseurl=https:/'
        '/trunk.rdoproject.org/centos7/81/c2/81c23c047e8e0'
        'fc03b54164921f49fdb4103202c_b333f915\nenabled=1\n'
        'gpgcheck=0\npriority=1'
    )
    mock_get.return_value = mock_response
    release = 'master'
    hash_name = 'current-tripleo'
    dlrn_hash = '81c23c047e8e0fc03b54164921f49fdb4103202c_b333f915'
    repo_url = 'https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' % (
        release,
        hash_name,
    )
    assert (
        get_dlrn_hash(release, hash_name, distro_name='centos', distro_version='7')
        == dlrn_hash
    )
    mock_get.assert_called_once_with(repo_url, timeout=8)
    mock_log_info.assert_called_once_with(
        "Got DLRN hash: {} for the named "
        "hash: {} on the {} "
        "release".format(dlrn_hash, hash_name, release)
    )
    mock_log_warning.assert_not_called()
    mock_log_exception.assert_not_called()

    # centos8 test scenario
    mock_get.reset_mock()
    mock_log_info.reset_mock()
    mock_response.text = '7e8e0fc03b54164921f49fdb4103202c'
    mock_get.return_value = mock_response
    release = 'master'
    hash_name = 'current-tripleo'
    dlrn_hash = '7e8e0fc03b54164921f49fdb4103202c'
    repo_url = 'https://trunk.rdoproject.org/centos8-%s/%s/delorean.repo.md5' % (
        release,
        hash_name,
    )
    assert (
        get_dlrn_hash(release, hash_name, distro_name='centos', distro_version='8')
        == dlrn_hash
    )
    mock_get.assert_called_once_with(repo_url, timeout=8)
    mock_log_info.assert_called_once_with(
        "Got DLRN hash: {} for the named "
        "hash: {} on the {} "
        "release".format(dlrn_hash, hash_name, release)
    )
    mock_log_warning.assert_not_called()
    mock_log_exception.assert_not_called()

    # centos9 test scenario
    mock_get.reset_mock()
    mock_log_info.reset_mock()
    mock_response.text = '1b28380bbbe279159578da5c60e567492cbb599d'
    mock_get.return_value = mock_response
    release = 'master'
    hash_name = 'current-tripleo'
    dlrn_hash = '1b28380bbbe279159578da5c60e567492cbb599d'
    repo_url = 'https://trunk.rdoproject.org/centos9-%s/%s/delorean.repo.md5' % (
        release,
        hash_name,
    )
    assert (
        get_dlrn_hash(release, hash_name, distro_name='centos', distro_version='9')
        == dlrn_hash
    )
    mock_get.assert_called_once_with(repo_url, timeout=8)
    mock_log_info.assert_called_once_with(
        "Got DLRN hash: {} for the named "
        "hash: {} on the {} "
        "release".format(dlrn_hash, hash_name, release)
    )
    mock_log_warning.assert_not_called()
    mock_log_exception.assert_not_called()


@mock.patch('logging.getLogger')
@mock.patch('requests.get')
def test_null_response_raises_runtimeerror(mock_get, mock_logging):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_warning = mock.MagicMock()
    mock_log_info = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.warning = mock_log_warning
    mock_logger.info = mock_log_info
    release = 'master'
    hash_name = 'current-tripleo'
    repo_url = 'https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' % (
        release,
        hash_name,
    )
    mock_get.return_value = None
    with pytest.raises(RuntimeError):
        get_dlrn_hash(release, hash_name)
    mock_get.assert_called_with(repo_url, timeout=8)
    assert mock_get.call_count == 20
    mock_log_info.assert_not_called()
    mock_log_warning.assert_called_with(
        "Attempt 20 of 20 to get DLRN hash " "failed to get a response."
    )
    assert mock_log_warning.call_count == 20
    mock_log_exception.assert_not_called()


@mock.patch('logging.getLogger')
@mock.patch('requests.get')
def test_get_dlrn_hash_500_then_200(mock_get, mock_logging):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_warning = mock.MagicMock()
    mock_log_info = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.warning = mock_log_warning
    mock_logger.info = mock_log_info
    mock_response_ok = mock.Mock()
    mock_response_ok.ok = True
    mock_response_ok.text = (
        '[delorean]\nname=delorean-openstack-nova-81c23c04'
        '7e8e0fc03b54164921f49fdb4103202c\nbaseurl=https:/'
        '/trunk.rdoproject.org/centos7/81/c2/81c23c047e8e0'
        'fc03b54164921f49fdb4103202c_b333f915\nenabled=1\n'
        'gpgcheck=0\npriority=1'
    )
    mock_response_bad = mock.Mock()
    mock_response_bad.ok = False
    mock_response_bad.status_code = 500
    release = 'master'
    hash_name = 'current-tripleo'
    dlrn_hash = '81c23c047e8e0fc03b54164921f49fdb4103202c_b333f915'
    repo_url = 'https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' % (
        release,
        hash_name,
    )
    mock_get.side_effect = [mock_response_bad, mock_response_ok]
    assert get_dlrn_hash(release, hash_name, retries=20) == dlrn_hash
    mock_get.assert_called_with(repo_url, timeout=8)
    mock_log_info.assert_called_once_with(
        "Got DLRN hash: {} for the named "
        "hash: {} on the {} "
        "release".format(dlrn_hash, hash_name, release)
    )
    mock_log_warning.assert_called_once_with(
        "Attempt 1 of 20 to get DLRN " "hash returned status code 500."
    )
    mock_log_exception.assert_not_called()


@mock.patch('logging.getLogger')
@mock.patch('requests.get')
def test_get_dlrn_hash_timeout(mock_get, mock_logging):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_warning = mock.MagicMock()
    mock_log_info = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.warning = mock_log_warning
    mock_logger.info = mock_log_info
    release = 'master'
    hash_name = 'current-tripleo'
    repo_url = 'https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' % (
        release,
        hash_name,
    )
    mock_get_exception = Exception("We need more power!")
    mock_get.side_effect = mock_get_exception
    with pytest.raises(RuntimeError):
        get_dlrn_hash(release, hash_name, retries=20)
    mock_get.assert_called_with(repo_url, timeout=8)
    mock_log_info.assert_not_called()
    mock_log_warning.assert_called_with(
        "Attempt 20 of 20 to get DLRN hash " "threw an exception."
    )
    assert mock_log_warning.call_count == 20
    mock_log_exception.assert_called_with(mock_get_exception)
    assert mock_log_exception.call_count == 20


@mock.patch('logging.getLogger')
@mock.patch('requests.get')
def test_get_dlrn_hash_500_10_times(mock_get, mock_logging):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_warning = mock.MagicMock()
    mock_log_info = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.warning = mock_log_warning
    mock_logger.info = mock_log_info
    mock_response = mock.Mock()
    mock_response.ok = False
    mock_response.status_code = 500
    release = 'master'
    hash_name = 'current-tripleo'
    repo_url = 'https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' % (
        release,
        hash_name,
    )
    mock_get.return_value = mock_response
    with pytest.raises(RuntimeError):
        get_dlrn_hash(release, hash_name, retries=20)
    mock_get.assert_called_with(repo_url, timeout=8)
    mock_log_info.assert_not_called()
    mock_log_warning.assert_called_with(
        "Attempt 20 of 20 to get DLRN hash " "returned status code 500."
    )
    assert mock_log_warning.call_count == 20
    mock_log_exception.assert_not_called()
