#!/usr/bin/env python

#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import datetime
from datetime import timedelta
import pytz
import re

from launchpadlib.launchpad import Launchpad

""" this returns a list of launchpad bugs """


class LaunchpadReport(object):
    def __init__(self, bugs, config):
        self.bugs = bugs
        self.config = config

    def generate(self):
        bugs_with_alerts_open = {}
        bugs_with_alerts_closed = {}
        launchpad = Launchpad.login_anonymously(
            'Red Hat Status Bot', 'production', '.cache', version='devel'
        )
        bug_statuses_open = ['Confirmed', 'Triaged', 'In Progress', 'Fix Committed']
        bug_statuses_closed = ['Fix Released']
        for label, config_string in self.bugs.items():
            c = config_string.split(',')
            project = launchpad.projects[c[0]]
            filter_re = c[1]
            for milestone in project.all_milestones:
                if re.match(filter_re, milestone.name):
                    for task in project.searchTasks(
                        milestone=milestone,
                        status=bug_statuses_open,
                        tags='promotion-blocker',
                    ):
                        now = datetime.datetime.now(pytz.UTC)
                        delay = int(self.config.get('Bug', 'delay'))
                        delay_time = now - timedelta(hours=delay)
                        if delay_time > task.date_created:
                            bugs_with_alerts_open[task.bug.id] = task.bug

                    for task in project.searchTasks(
                        milestone=milestone,
                        status=bug_statuses_closed,
                        importance='Critical',
                        tags='alert',
                    ):
                        bugs_with_alerts_closed[task.bug.id] = task.bug
            return bugs_with_alerts_open, bugs_with_alerts_closed
