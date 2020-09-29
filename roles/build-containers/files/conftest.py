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
from py.xml import html

BUILD_DIR = 'container-builds'
LOGS_DIR = 'logs'
EXCLUDE_CONTAINERS = 'containers-excluded.log'


def _get_build_link(funcargs):
    """
    Retrieves the link of the build log for a given container
    """
    # compose logfile to glob search
    log = f"{ funcargs.get('image') }-build.log"
    logfile = f"./{ LOGS_DIR }/{ BUILD_DIR }/**/{ log }"
    for f in glob.glob(logfile, recursive=True):
        # remove parent 'logs/' dir from the path
        # link will be like ./container-builds/**/<image>-build.log
        link = "./" + "/".join(f.split("/")[2:])
        # return first log file as href link
        return html.a(log, href=link)
    # log file not found
    return ""


def _get_excluded_containers_list():
    """
    Retrieves the list of excluded images to skip the build
    """
    try:
        with open(EXCLUDE_CONTAINERS) as f:
            excluded_containers_list = [line.strip() for line in f]
    except IOError:
        excluded_containers_list = []
    return excluded_containers_list


def pytest_addoption(parser):
    parser.addoption(
        "--image",
        action="append",
        default=[],
        help="list of container images to pass to test functions",
    )


def pytest_generate_tests(metafunc):
    if "image" in metafunc.fixturenames:
        metafunc.parametrize("image", metafunc.config.getoption("image"))


def pytest_configure():
    # these vars are visible from build-report.py functions
    pytest.excluded_containers = _get_excluded_containers_list()
    pytest.build_dir = BUILD_DIR
    pytest.logs_dir = LOGS_DIR


@pytest.mark.optionalhook
def pytest_html_results_table_header(cells):
    # this replaces the default 'Links' column in position #3
    cells.insert(3, html.th('Build Log'))
    cells.pop()


@pytest.mark.optionalhook
def pytest_html_results_table_row(report, cells):
    if hasattr(report, 'build_log'):
        # report.logs has the link of each build log
        cells.insert(3, html.td(report.build_log))


@pytest.mark.hookwrapper
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    # get the link for a given image build log
    report.build_log = _get_build_link(item.funcargs)
