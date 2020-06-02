#!/usr/bin/env python

# Example usage:
# python move_bugs.py --no-dry-run --priority-less-than High tripleo stein-3 train-1
# python move_bugs.py --no-dry-run tripleo stein-3 stein-rc1
# python move_bugs.py --no-dry-run --priority-less-than High tripleo stein-rc1 train-1
# python move_bugs.py --no-dry-run --priority-less-than Critical tripleo stein-rc1 train-1
# python move_bugs.py --no-dry-run tripleo stein-rc1 train-1

import argparse
import lazr.restfulclient.errors
import os
import sys

# import sqlite3

from launchpadlib import launchpad

# LP_DB = os.path.expanduser('~/.launchpadlib/tripleo')
LP_CACHE_DIR = os.path.expanduser('~/.launchpadlib/cache')
LP_OPEN_STATUS = ['New', 'Incomplete', 'Confirmed', 'Triaged', 'In Progress']
LP_CLOSED_STATUS = ['Fix Released', 'Fix Committed']
LP_EXPIRED_STATUS = ['Expired']
LP_IMPORTANCE = ['Undecided', 'Critical', 'High', 'Medium', 'Low', 'Wishlist']

# def connect_db():
#     conn = sqlite3.connect(LP_DB)
#     return conn

# NOTES:
# lp_attributes: Data fields of this object. You can read from these might
# be able to write to some of them.
#
# lp_collections: List of launchpad objects associated with this object.
#
# lp_entries: Other Launchpad objects associated with this one.
#
# lp_operations: The names of Launchpad methods you can call on the object.


def no_creds():
    print("No active credentials")
    sys.exit(1)


def login():
    lp = launchpad.Launchpad.login_with(
        application_name='tripleo-bugs',
        service_root='production',
        launchpadlib_dir=LP_CACHE_DIR,
        credential_save_failed=no_creds,
        version='devel',
    )
    return lp


def validate_milestone(project, milestone):
    _milestone = project.getMilestone(name=milestone)
    if not _milestone:
        parser.error('Requested milestone {} does not exist'.format(milestone))
    return _milestone


def validate_importance(importance):
    if importance not in LP_IMPORTANCE:
        parser.error(
            'Provided importance {} is not one of: {}'.format(
                importance, ', '.join(LP_IMPORTANCE)
            )
        )
    return importance


def get_importance_from_input(args):
    if args.priority_less_than:
        return LP_IMPORTANCE[LP_IMPORTANCE.index(args.priority_less_than) + 1 :]
    if args.priority_greater_than:
        return LP_IMPORTANCE[: LP_IMPORTANCE.index(args.priority_greater_than)]
    return args.priority


def main(args):
    lp = login()
    project = lp.projects[args.projectname]
    to_milestone = validate_milestone(project, args.to_milestone)
    from_milestone = validate_milestone(project, args.from_milestone)

    # TODO: switch to exclude in progress bugs
    # bug_status = ['New', 'Incomplete', 'Confirmed', 'Triaged']
    bug_status = LP_OPEN_STATUS
    from_importance = get_importance_from_input(args)
    print("Moving bugs from {} to {}".format(from_milestone.name, to_milestone.name))
    print("Limiting to importance: {}".format(from_importance))
    bugs = project.searchTasks(
        status=bug_status, milestone=from_milestone, importance=from_importance
    )

    failed = set()
    success = set()
    for b in bugs:
        bug = b.bug
        # print("{}\t{}\t{}".format(b.bug.id, b.importance, b.status))

        print(
            "Moving {} from {} to {} ...".format(
                bug.id, from_milestone.name, to_milestone.name
            ),
            end='',
        )
        b.milestone = to_milestone
        try:
            if args.no_dry_run:
                b.lp_save()
                print(" SAVED!")
            else:
                print(" SKIPPED!")
            success.add(bug.id)
        except lazr.restfulclient.errors.ServerError as e:
            print("ERROR - Timeout", e)
            failed.add(bug.id)
        except Exception as e:
            print("ERROR - {}".format(e))

    print("Moved {} Bugs".format(len(success)))
    print("Failed to move {} Bugs".format(len(failed)))
    if failed:
        print("Failed to move the following bugs:")
        for bugid in failed:
            print("http://bugs.launchpad.net/bugs/{}".format(bugid))

    # milestones = project.active_milestones

    # tags = project.official_bug_tags
    # tags = ['ui', 'tech-debt']

    # print("{}".format(",".join(['tag']+LP_OPEN_STATUS)))
    # for T in tags:
    #     res = [T]
    #     for S in LP_OPEN_STATUS:
    #         bugs = lpt.searchTasks(tags=T, status=S)
    #         res = res + [str(len(bugs))]
    #     print("{}".format(",".join(res)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Change Move bugs")
    parser.add_argument('projectname', default='tripleo', help='The project to act on')
    limiting = parser.add_mutually_exclusive_group()
    limiting.add_argument(
        '--priority-less-than',
        type=validate_importance,
        dest='priority_less_than',
        help='All bugs with with importance less than ' 'the provided value',
    )
    limiting.add_argument(
        '--priority-greater-than',
        type=validate_importance,
        dest='priority_greater_than',
        help='All bugs with with importance greater than ' 'the provided value',
    )
    limiting.add_argument(
        '--priority',
        type=validate_importance,
        dest='priority',
        help='All bugs with with the provided importance',
    )
    parser.add_argument('from_milestone', help='Milestone to move from (queens-1)')
    parser.add_argument('to_milestone', help='Milestone to move to (queens-2)')
    parser.add_argument(
        '--no-dry-run',
        dest='no_dry_run',
        help='Execute the move for real.',
        action='store_true',
    )

    args = parser.parse_args()
    main(args)
