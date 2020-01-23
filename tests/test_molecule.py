# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import os
import pytest
import subprocess


# detect if we have a working docker setup and skip with warning if not
docker_skip = False
docker_reason = ''
try:
    import docker

    client = docker.from_env(timeout=5)
    if not client.ping():
        raise Exception("Failed to ping docker server.")
except Exception as e:
    docker_reason = "Skipping molecule tests due: %s" % e
    docker_skip = True


def pytest_generate_tests(metafunc):
    # detects all molecule scenarios inside the project
    matches = []
    if 'testdata' in metafunc.fixturenames:
        for role in os.listdir("./roles"):
            role_path = os.path.abspath('./roles/%s' % role)
            for _, dirnames, _ in os.walk(role_path + '/molecule'):
                for scenario in dirnames:
                    if os.path.isfile(
                        '%s/molecule/%s/molecule.yml' % (role_path, scenario)
                    ):
                        matches.append([role_path, scenario])
    metafunc.parametrize('testdata', matches)


@pytest.mark.skipif(docker_skip, reason=docker_reason)
def test_molecule(testdata):
    cwd, scenario = testdata
    cmd = ['python', '-m', 'molecule', 'test', '-s', scenario]
    print("running: %s (from %s)" % (" ".join(cmd), cwd))
    r = subprocess.call(cmd, cwd=cwd)
    assert r == 0
