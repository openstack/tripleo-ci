#!/usr/bin/env python
# Originally from https://gitlab.cee.redhat.com/whayutin/launchpad_bugs/-/blob/master/launchpad_close_old_bugs.py
import argparse
import json
import os
import sys

from datetime import datetime, timedelta
from launchpadlib.launchpad import Launchpad

cachedir = "{}/.launchpadlib/cache/".format(os.path.expanduser('~'))


def get_bugs(status, tag=None, previous_days=None):
    # launchpad = Launchpad.login_anonymously(
    #    'OOOQ Ruck Rover', 'production', cachedir, version='devel')
    launchpad = Launchpad.login_with('lKfbPKz0qdwdjVLjtnTF', 'production')
    project = launchpad.projects['tripleo']

    # Filter by Status and Tag
    if tag is not None and previous_days is None:
        bugs = project.searchTasks(status=status, tags=tag)
    # Filter by Status only
    elif tag is None and previous_days is None:
        bugs = project.searchTasks(status=status)
    # Filter by Status and Number of Days
    elif tag is None and previous_days is not None:
        days_to_search = datetime.utcnow() - timedelta(days=int(previous_days))
        bugs = project.searchTasks(status=status, created_before=days_to_search)
    # Filter by Tag, Status and Number of Days
    elif tag is not None and previous_days is not None:
        days_to_search = datetime.utcnow() - timedelta(days=int(previous_days))
        bugs = project.searchTasks(
            status=status, created_before=days_to_search, tags=tag
        )
    else:
        print("invalid combination of parameters")
        sys.exit(1)

    return bugs


def print_as_csv(bug_tasks):
    if bug_tasks:
        for bug_task in bug_tasks:
            print(
                ('{},{},{},{},"{}"').format(
                    bug_task.bug.id,
                    bug_task.status,
                    json.dumps(bug_task.bug.tags)
                    .replace(',', ' ')
                    .replace('"', '')
                    .replace('[', '')
                    .replace(']', ''),
                    bug_task.web_link,
                    json.dumps(bug_task.bug.title)
                    .replace('"', "'")
                    .replace("\\n", "")
                    .replace("\\", ""),
                )
            )


def close_bug(bug_tasks):
    if bug_tasks:
        for bug_task in bug_tasks:
            bug_task.status = "Incomplete"
            bug_task.lp_save()
            print(bug_task.bug.id)


def main():

    parser = argparse.ArgumentParser(
        description="Print launchpad bugs as influxdb lines"
    )

    parser.add_argument('--tag')
    parser.add_argument(
        '--status',
        nargs='+',
        default=['New', 'Triaged', 'In Progress', 'Confirmed', 'Fix Committed'],
    ),
    parser.add_argument('--previous_days', default=365)
    args = parser.parse_args()

    # print_as_csv(get_bugs(args.status,
    #                      args.tag,
    #                      args.previous_days))

    close_bug(get_bugs(args.status, args.tag, args.previous_days))


if __name__ == '__main__':
    main()
