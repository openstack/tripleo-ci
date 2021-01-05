# Copyright 2020 Red Hat Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import glob
import pytest
import subprocess


def _get_build_log(image):
    """
    Retrieve the inidividual log filename for a given image
    e.g. ./logs/container-builds/**/<image>-build.log
    """
    # compose the log filename
    log = f"{ image }-build.log"
    # glob search in ./logs/container-builds/**/<image>-build.log
    logfile = f"./{ pytest.logs_dir }/{ pytest.build_dir }/**/{ log }"
    for f in glob.glob(logfile, recursive=True):
        # return only first match
        return f
    # log not found, return glob string
    return logfile


def test_container_is_built(image):
    """
    Test if container image is built
    """
    # image in skip list, skip the build check
    if image in pytest.excluded_containers:
        pytest.skip("container image excluded: {}".format(image))

    # [TEST 1]: check if image exists
    cmd = ['podman', 'images', image]
    proc = subprocess.run(
        cmd, universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    # buildah images <image> should return 0 and image should be in stdout
    assert image in proc.stdout and proc.returncode == 0, proc.stderr
    print(proc.stdout)

    # [TEST 2]: check if build log has errors
    try:
        # read log file
        with open(_get_build_log(image), 'r') as build_log:
            log = build_log.read()
        # test if any error is found in the log
        assert 'Error:' not in log, f"Image failed to build: { image }"
    except IOError as err:
        print(f"Warning: Build log not found: { err }")

    # [TEST N+1]: additional tests can be added here
