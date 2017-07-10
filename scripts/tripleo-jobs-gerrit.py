#!/usr/bin/python

import argparse
import sys
import subprocess
import json
import re
import datetime

# Do not include the -nv suffix in the job name here.  The code will handle
# reading both the voting and non-voting forms of the job if they exist.
DEFAULT_JOB_NAMES = [
    'gate-tripleo-ci-centos-7-ovb-ha-oooq',
    'gate-tripleo-ci-centos-7-ovb-updates',
    'gate-tripleo-ci-centos-7-nonha-multinode-oooq',
    'gate-tripleo-ci-centos-7-scenario001-multinode-oooq',
    'gate-tripleo-ci-centos-7-scenario002-multinode-oooq',
    'gate-tripleo-ci-centos-7-scenario003-multinode-oooq',
    'gate-tripleo-ci-centos-7-scenario004-multinode-oooq',
    'gate-tripleo-ci-centos-7-scenario001-multinode-upgrades',
    'gate-tripleo-ci-centos-7-scenario002-multinode-upgrades',
    'gate-tripleo-ci-centos-7-scenario003-multinode-upgrades',
    'gate-tripleo-ci-centos-7-scenario004-multinode-upgrades',
    'gate-tripleo-ci-centos-7-undercloud-oooq',
    'gate-tripleo-ci-centos-7-3nodes-multinode',
    'gate-tripleo-ci-centos-7-multinode-upgrades',
    'gate-tripleo-ci-centos-7-undercloud-upgrades',
    'gate-tripleo-ci-centos-7-undercloud-containers',
    'gate-tripleo-ci-centos-7-containers-multinode',
    'gate-tripleo-ci-centos-7-containers-multinode-upgrades',
    'gate-tripleo-ci-centos-7-ovb-containers-oooq',
    'gate-tripleo-ci-centos-7-ovb-fakeha-caserver',
]

DEFAULT_PROJECTS = [
    'openstack/tripleo-heat-templates',
    'openstack/dib-utils',
    'openstack/diskimage-builder',
    'openstack/instack',
    'openstack/instack-undercloud',
    'openstack/os-apply-config',
    'openstack/os-collect-config',
    'openstack/os-net-config',
    'openstack/os-refresh-config',
    'openstack/python-tripleoclient',
    'openstack-infra/tripleo-ci',
    'openstack/tripleo-common',
    'openstack/tripleo-image-elements',
    'openstack/tripleo-incubator',
    'openstack/tripleo-puppet-elements',
    'openstack/mistral',
    '^openstack/puppet-.*',
]

COLORS = {"SUCCESS": "#008800", "FAILURE": "#FF0000", "ABORTED": "#000000"}


def get_gerrit_reviews(project, status="open", branch="master", limit="30"):
    arr = []
    status_query = ''
    if status:
        status_query = 'status: %s' % status
    cmd = 'ssh review.openstack.org -p29418 gerrit' \
          ' query "%s project: %s branch: %s" --comments' \
          ' --format JSON limit: %s --patch-sets --current-patch-set'\
          % (status_query, project, branch,limit)
    p = subprocess.Popen([cmd], shell=True, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout = p.stdout
    for line in stdout.readlines():
        review = json.loads(line)
        if 'project' in review:
            arr.append(review)
    return arr


def get_jenkins_comment_message(review):
    jenkins_messages = {}
    for comment in review['comments']:
        if 'name' in comment['reviewer']:
            if comment['reviewer']['name'] == 'Jenkins':
                if "NOT_REGISTERED" in comment['message']:
                    continue
                # NOTE(bnemec): For some reason the experimental-tripleo
                # message does not include "pipeline".
                if ("check-tripleo pipeline" not in comment['message'] and
                        "check pipeline" not in comment['message'] and
                        "experimental-tripleo" not in comment['message'] and
                        "gate pipeline" not in comment['message']):
                    continue
                jenkins_messages[comment['timestamp']] = comment['message']
    return jenkins_messages


def process_jenkins_comment_message(message, job_names):
    job_results = {}
    for line in message.split('\n'):
        if line and line[0] == '-':
            split = line.split(" ",6)
            voting_job_name = split[1]
            if voting_job_name.endswith('-nv'):
                voting_job_name = voting_job_name[:-3]
            if voting_job_name in job_names:
                if len(split) > 6:
                    duration = " ".join(split[6].split()[:2])
                else:
                    duration = ''
                job_results[voting_job_name] = {'log_url': split[2],
                                                'status': split[4],
                                                'duration': duration}
    return job_results


def gen_html(data, html_file, table_file, stats_hours, job_names, options):
    fp = open(table_file, "w")
    fp.write('<table border="1" cellspacing="0">')
    fp.write("<tr class='headers'><td>&nbsp;</td>")
    for job_name in job_names:
        fp.write("<td class='headers'><b>%s</b></td>" %
                 job_name.replace("gate-tripleo-ci-centos-7-", ""))
    fp.write("</tr>")
    count = 0

    reversed_sorted_keys = [(x['id'], x['patchset']) for x in
        reversed(sorted(data.values(), key=lambda y: y['ts']))]
    passed_jobs = 0
    partial_jobs = 0
    failed_jobs = 0
    for key in reversed_sorted_keys:
        result = data[key]
        if count > 300:
            break
        if not result['ci_results']:
            continue

        if (count % 2) == 1:
            fp.write("<tr class='tr0'>")
        else:
            fp.write("<tr class='tr1'>")
        count += 1

        fp.write("<td>")
        fp.write(result['timestamp'])
        fp.write("<br/>")
        fp.write(result['project'])
        fp.write("/")
        fp.write(result['branch'])
        fp.write("<br/>")
        fp.write(result['status'])
        fp.write("</td>")

        job_columns = ""
        result_types = set()
        for job_name in job_names:
            if job_name in result['ci_results']:
                job_columns += "<td>"
                ci_result = result['ci_results'][job_name]
                color = COLORS.get(ci_result['status'], "#666666")
                result_types.add(ci_result['status'])
                job_columns += '<font color="%s">' % color
                gerrit_href = 'https://review.openstack.org/#/c/%s/%s"' % (
                    result['url'].split('/')[-1], result['patchset']
                )
                job_columns += '<a STYLE="color : %s" href="%s">%s,%s</a>' % \
                    (color, gerrit_href, result['url'].split('/')[-1],
                     result['patchset'])
                job_columns += '<br/>%s ' % (ci_result['duration'])
                job_columns += '<a STYLE="text-decoration:none" '
                job_columns += 'href="%s">log</a>' %\
                               ci_result['log_url']
                job_columns += '</font><br/>'
                job_columns += "</td>"
            else:
                job_columns += "<td>&nbsp;</td>"
        # For the purpose of these stats, let's ignore POST_FAILURE jobs
        result_types.discard('POST_FAILURE')
        if len(result_types) > 1:
            partial_jobs += 1
        elif 'FAILURE' in result_types:
            failed_jobs += 1
        else:
            passed_jobs += 1
        fp.write(job_columns)
        fp.write("</tr>")
    fp.write("<table>")
    fp.write("<p>Query parameters:</p>")
    fp.write("Branch: "+options.b+"<br/>")
    fp.write("Status: "+options.s+"<br/>")
    fp.write("Limit: "+options.l)

    total = passed_jobs + partial_jobs + failed_jobs
    fp.write("<p>Overall</p>")
    fp.write("Passed: %d/%d (%d %%)<br/>" % (
        passed_jobs,
        total,
        float(passed_jobs) / float(total) * 100
        ))
    fp.write("Partial Failures: %d/%d (%d %%)<br/>" % (
        partial_jobs,
        total,
        float(partial_jobs) / float(total) * 100
        ))
    fp.write("Complete Failures: %d/%d (%d %%)<br/>" % (
        failed_jobs,
        total,
        float(failed_jobs) / float(total) * 100
        ))

    fp.close()

    with open(html_file, "w") as f:
        f.write('<html><head/><body>')
        f.write(open(table_file).read())
        f.write("<table></body></html>")


def main(args=sys.argv[1:]):
    parser = argparse.ArgumentParser(
        description=("Get details of tripleo ci jobs and generates a html "
                     "report."))
    parser.add_argument('-o', default="tripleo-jobs.html", help="html file")
    parser.add_argument('-p', default=",".join(DEFAULT_PROJECTS),
                        help='comma separated list of projects to use.')
    parser.add_argument('-j', default=",".join(DEFAULT_JOB_NAMES),
                        help='comma separated list of jobs to monitor.')
    parser.add_argument('-s', default="", help="status")
    parser.add_argument('-b', default="master", help="branch")
    parser.add_argument('-l', default="30", help="limit")
    opts = parser.parse_args(args)

    job_names = opts.j.split(",")

    # project reviews
    proj_reviews = []
    for proj in opts.p.split(","):
        proj_reviews.extend(get_gerrit_reviews(proj, status=opts.s, branch=opts.b, limit=opts.l))
    results = {}
    for review in proj_reviews:
        for ts, message in get_jenkins_comment_message(review).iteritems():
            ci_results = process_jenkins_comment_message(message,
                                                         job_names)

            patchset = str(re.search('Patch Set (.+?):', message).group(1))
            key = (review['id'], patchset)
            results.setdefault(key, {}).update({
                'id': review['id'],
                'ts': ts,
                'status': review['status'],
                'timestamp': datetime.datetime.fromtimestamp(
                    int(ts)).strftime('%Y-%m-%d %H:%M:%S'),
                'url': review['url'],
                'patchset': patchset,
                'project': re.sub(r'.*/', '', review['project']),
                'branch': review['branch'],
                })
            results[key].setdefault(
                                    'ci_results', {}).update(ci_results)

    gen_html(results, opts.o, "%s-table" % opts.o, 24, job_names,opts)

if __name__ == '__main__':
    exit(main())
