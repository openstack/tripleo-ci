#!/usr/bin/env python

import argparse
import difflib
import json
import os
import requests

from colorama import Fore
from colorama import init

GERRIT_DETAIL_API = "https://review.opendev.org/changes/{}/detail"
GERRIT_USER_NAME = "zuul"
ZUUL_PIPELINE = "check"


def parse_ci_message(message):
    """Convert zuul's gerrit message into a dict

    Dictionary contains job name as key and job url as value
    """

    jobs = {}
    for line in message.split("\n"):
        if line[:1] == '-':
            splitted_line = line.split()
            jobs[splitted_line[1]] = splitted_line[2]
    return jobs


def get_file(logs_url, file):
    """Download a file from logs server for this job"""

    response = requests.get(logs_url + '/logs/' + file)
    if response.ok:
        return response.content
    return None


def get_last_jobs(change):
    """Get the last CI jobs execution at check pipeline for this review"""
    patchset = None
    if '/' in change:
        change_patchset = change.split('/')
        change = change_patchset[0]
        patchset = change_patchset[1]

    last_jobs = {}
    detail_url = GERRIT_DETAIL_API.format(change)
    response = requests.get(detail_url)
    if response.ok:
        sanitized_content = "\n".join(response.content.split("\n")[1:])
        detail = json.loads(sanitized_content)
        zuul_messages = [
            message
            for message in detail['messages']
            if message['author']['username'] == GERRIT_USER_NAME
            and "({} pipeline)".format(ZUUL_PIPELINE) in message['message']
        ]

        if patchset:
            patchset = "Patch Set {}".format(patchset)
            filtered = [m for m in zuul_messages if patchset in m['message']]
            if len(filtered) == 0:
                raise RuntimeError(
                    "{} not found for review {}".format(patchset, change)
                )
            last_message = filtered[0]
        else:
            last_message = zuul_messages[-1]

        last_jobs = parse_ci_message(last_message['message'])
        date = last_message['date']
    else:
        raise RuntimeError(response.content)
    return last_jobs, date


def download(jobs, file_path):
    """Download a file from all the specified jobs

    Return them as a dictionary with job name as key and file content as value
    """
    downloaded_files = {}
    for job, logs in jobs.iteritems():
        downloaded_file = get_file(logs, file_path)
        if downloaded_file:
            downloaded_files[job] = downloaded_file
        else:
            print("WARNING: {} not found at {}".format(file_path, job))
    return downloaded_files


def is_equal(lho_jobs, rho_jobs, file_path):
    """Prints differences of file_path between the lho and rho job sets"""

    lho_files = download(lho_jobs, file_path)
    rho_files = download(rho_jobs, file_path)
    print(">>>>>>> Comparing {}".format(file_path))
    if lho_files != rho_files:
        diffkeys = [k for k in lho_files if lho_files[k] != rho_files.get(k, None)]
        print("{} are different at the following jobs:".format(file_path))
        for key in diffkeys:
            print(Fore.BLUE + key)
            print(Fore.BLUE + lho + ": " + lho_jobs[key])
            print(Fore.BLUE + rho + ": " + rho_jobs[key])
            for line in difflib.unified_diff(
                lho_files[key].splitlines(), rho_files.get(key, '').splitlines()
            ):
                print(colors.get(line[0], Fore.BLACK) + line)
        return False
    print("{} files are the same".format(file_path))
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Compares files at logs.o.o from two reviews'
    )

    parser.add_argument(
        'reviews',
        metavar='review',
        nargs=2,
        help='left-side and right-side review numbers to compare it can'
        'include the specific patchset, examples:610491 or 610491/1',
    )

    parser.add_argument(
        '--files',
        type=str,
        default='playbook_executions.log,reproducer-quickstart.sh,' 'collect_logs.sh',
        help='Comma separated list of files to compare at logs.o.o '
        '(default: %(default)s)',
    )

    args = parser.parse_args()

    colors = {'-': Fore.RED, '+': Fore.GREEN, '@': Fore.YELLOW}

    # When piping colors are disabled unless you define PY_COLORS variable.
    strip = os.environ.get('PY_COLORS', '0') != '1'
    init(autoreset=True, strip=strip)
    lho = args.reviews[0]
    rho = args.reviews[1]
    lho_jobs, lho_date = get_last_jobs(lho)
    rho_jobs, rho_date = get_last_jobs(rho)

    # Compare only the job at both reviews
    jobs_intersection = set(lho_jobs.keys()) & set(rho_jobs.keys())
    lho_jobs = {job: lho_jobs[job] for job in jobs_intersection}
    rho_jobs = {job: rho_jobs[job] for job in jobs_intersection}

    print("- {}, {}".format(lho, lho_date))
    print("+ {}, {}".format(rho, rho_date))

    for file_to_compare in args.files.split(','):
        is_equal(lho_jobs, rho_jobs, file_to_compare)
