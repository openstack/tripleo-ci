#!/usr/bin/env python
# Copyright 2016 Red Hat Inc.
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

# Usage: openstack stack event list -f json overcloud | \
#        heat-deploy-times.py [list of resource names]
# If no resource names are provided, all of the resources will be output.

import json
import sys
import time

def process_events(all_events, events):
    times = {}
    for event in all_events:
        name = event['resource_name']
        status = event['resource_status']
        # Older clients return timestamps in the first format, newer ones
        # append a Z.  This way we can handle both formats.
        try:
            strptime = time.strptime(event['event_time'],
                                     '%Y-%m-%dT%H:%M:%S')
        except ValueError:
            strptime = time.strptime(event['event_time'],
                                     '%Y-%m-%dT%H:%M:%SZ')
        etime = time.mktime(strptime)
        if name in events:
            if status == 'CREATE_IN_PROGRESS':
                times[name] = {'start': etime, 'elapsed': None}
            elif status == 'CREATE_COMPLETE' or status == 'CREATE_FAILED':
                times[name]['elapsed'] = etime - times[name]['start']
    for name, data in sorted(times.items(),
                             key = lambda x: x[1]['elapsed'],
                             reverse=True):
        elapsed = 'Still in progress'
        if times[name]['elapsed'] is not None:
            elapsed = times[name]['elapsed']
        print '%s %s' % (name, elapsed)

if __name__ == '__main__':
    stdin = sys.stdin.read()
    all_events = json.loads(stdin)
    events = sys.argv[1:]
    if not events:
        events = set()
        for event in all_events:
            events.add(event['resource_name'])
    process_events(all_events, events)
