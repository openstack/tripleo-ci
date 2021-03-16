import os
from subprocess import run
import subprocess
import sys


def test_jobs_gerrit():
    f = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "../scripts/tripleo-jobs-gerrit.py")
    )
    result = run(
        [sys.executable, f],
        universal_newlines=True,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, result
