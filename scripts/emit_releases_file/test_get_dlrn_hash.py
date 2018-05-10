from emit_releases_file import get_dlrn_hash

import mock
import pytest

@mock.patch('requests.get')
def test_get_dlrn_hash(mock_get):
    mock_response = mock.Mock()
    mock_response.content = ('[delorean]\nname=delorean-openstack-nova-81c23c04'
                             '7e8e0fc03b54164921f49fdb4103202c\nbaseurl=https:/'
                             '/trunk.rdoproject.org/centos7/81/c2/81c23c047e8e0'
                             'fc03b54164921f49fdb4103202c_b333f915\nenabled=1\n'
                             'gpgcheck=0\npriority=1')
    release = 'master'
    hash_name = 'current-tripleo'
    repo_url = ('https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo'
                % (release, hash_name))
    mock_get.return_value = mock_response
    assert (get_dlrn_hash(release, hash_name) ==
            '81c23c047e8e0fc03b54164921f49fdb4103202c_b333f915')
    mock_get.assert_called_once_with(repo_url, timeout=(3.05, 27))


@mock.patch('requests.get')
def test_null_response_raises_runtimeerror(mock_get):
    release = 'master'
    hash_name = 'current-tripleo'
    repo_url = ('https://trunk.rdoproject.org/centos7-%s/%s/delorean.repo' %
                (release, hash_name))
    mock_get.return_value = None
    with pytest.raises(RuntimeError):
        get_dlrn_hash(release, hash_name)
    mock_get.assert_called_with(repo_url, timeout=(3.05, 27))
    assert (10 == mock_get.call_count)
