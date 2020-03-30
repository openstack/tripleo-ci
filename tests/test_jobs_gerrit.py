import os


def test_jobs_gerrit():
    f = os.path.join(os.path.dirname(__file__), "../scripts/tripleo-jobs-gerrit.py")
    result = os.system(f)
    assert result == 0
