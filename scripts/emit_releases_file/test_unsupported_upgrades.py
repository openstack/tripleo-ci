from emit_releases_file import compose_releases_dictionary
import pytest


def test_fail_with_wrong_release():
    with pytest.raises(RuntimeError):
        compose_releases_dictionary('foobar', {}, False)
