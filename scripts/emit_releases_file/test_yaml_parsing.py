from emit_releases_file import load_featureset_file

from unittest import mock
import pytest
from six import PY2
import yaml


if PY2:
    BUILTINS_OPEN = "__builtin__.open"
else:
    BUILTINS_OPEN = "builtins.open"


@mock.patch('yaml.safe_load')
@mock.patch('logging.getLogger')
def test_featureset_file_with_bad_file_path(mock_logging, mock_yaml):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_error = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.error = mock_log_error
    bad_file_exception = IOError("Dude where's my YAML!")
    mo = mock.mock_open()
    with pytest.raises(IOError):
        with mock.patch(BUILTINS_OPEN, mo, create=True) as mock_file:
            mock_file.side_effect = bad_file_exception
            featureset = load_featureset_file('some_non_existent.yaml')
            mock_yaml.assert_not_called()
            mock_file.assert_called_with('some_non_existent.yaml', 'r')
            mock_logging.assert_called_with('emit-releases')
            mock_log_error.assert_called()
            mock_log_exception.assert_called_with(bad_file_exception)
            assert featureset is None


@mock.patch('yaml.safe_load')
@mock.patch('logging.getLogger')
def test_featureset_file_with_bad_yaml(mock_logging, mock_yaml):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_error = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.error = mock_log_error
    mo = mock.mock_open()
    mock_yaml.side_effect = yaml.YAMLError()
    with pytest.raises(yaml.YAMLError):
        with mock.patch(BUILTINS_OPEN, mo, create=True) as mock_file:
            featureset = load_featureset_file('some_badly_formatted.yaml')
            mock_yaml.assert_called()
            mock_file.assert_called_with('some_badly_formatted.yaml', 'r')
            mock_logging.assert_called_with('emit-releases')
            mock_log_exception.assert_called()
            mock_log_error.assert_called()
            assert featureset is None


@mock.patch('yaml.safe_load')
@mock.patch('logging.getLogger')
def test_featureset_file_loaded_ok(mock_logging, mock_yaml):
    mock_logger = mock.MagicMock()
    mock_logging.return_value = mock_logger
    mock_log_exception = mock.MagicMock()
    mock_log_error = mock.MagicMock()
    mock_logger.exception = mock_log_exception
    mock_logger.error = mock_log_error
    ok_yaml_dict = {'some_featureset_keys': 'some_featureset_values'}
    mock_yaml.return_value = ok_yaml_dict
    mo = mock.mock_open()
    with mock.patch(BUILTINS_OPEN, mo, create=True) as mock_file:
        featureset = load_featureset_file('featureset999.yaml')
        mock_file.assert_called_with('featureset999.yaml', 'r')
        mock_yaml.assert_called()
        mock_log_exception.assert_not_called()
        mock_log_error.assert_not_called()
        assert featureset == ok_yaml_dict
