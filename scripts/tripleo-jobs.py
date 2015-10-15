#!/usr/bin/python

import argparse
import datetime
import os
import sys
import time
import urllib

from jenkinsapi.jenkins import Jenkins
from jenkinsapi.utils.requester import Requester

from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy import desc

colors = {"SUCCESS": "#0d941d", "FAILURE": "#FF0000", "ABORTED": "#000000"}
Base = declarative_base()


class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True)
    dt = Column(DateTime)
    name = Column(String)
    duration = Column(Integer)
    gerrit_ref = Column(String)
    log_path = Column(String)
    zuul_ref = Column(String)
    zuul_project = Column(String)
    status = Column(String)
    url = Column(String)


job_names = [
    'gate-tripleo-ci-ironic-overcloud-f21puppet-nonha',
    'gate-tripleo-ci-ironic-overcloud-f21puppet-ha',
    'gate-tripleo-ci-ironic-overcloud-f21puppet-ceph',
]


now = datetime.datetime.now()


def get_data(session, stop_after):
    for jenkinsnumber in range(1, 8):
        jurl = 'https://jenkins%02d.openstack.org' % jenkinsnumber
        jrequester = Requester(None, None, baseurl=jurl, ssl_verify=False)
        try:
            jenkins = Jenkins(jurl, requester=jrequester)
        except:
            print "Couldn't connect to %s" % jurl
            continue

        for jobname in job_names:
            try:
                job = jenkins.get_job(jobname)
            except:
                print "Couldn't get job %s(%s)" % (jobname, jurl)
                continue
            builds = job.get_build_dict().items()
            builds.sort()
            builds.reverse()
            for buildnumber, buildurl in builds:
                thisjob = session.query(Job).filter(Job.url == buildurl).all()
                # these are finised no need to hit jenkins again
                if thisjob and thisjob[0].status in ["SUCCESS", "FAILURE",
                                                     "ABORTED"]:
                    continue
                time.sleep(.3)
                print "Checking", buildurl
                try:
                    build = job.get_build(buildnumber)
                except:
                    print "ERROR ????"
                gerrit_ref = zuul_ref = zuul_project = log_path = None
                for param in build.get_actions()['parameters']:
                    if param['name'] == "ZUUL_CHANGE_IDS":
                        gerrit_ref = param["value"].split(" ")[-1]
                    elif param['name'] == "ZUUL_REF":
                        zuul_ref = param["value"]
                    elif param['name'] == "ZUUL_PROJECT":
                        zuul_project = param["value"]
                    elif param['name'] == "LOG_PATH":
                        log_path = param["value"]
                if zuul_ref is None or gerrit_ref is None or log_path is None:
                    continue

                if thisjob:
                    print "Updating", buildurl
                    thisjob[0].status = build.get_status()
                    thisjob[0].duration = build.get_duration().seconds
                    continue
                print "Saving", buildurl
                session.add(Job(dt=build.get_timestamp(),
                                duration=build.get_duration().seconds,
                                status=build.get_status(),
                                name=jobname,
                                gerrit_ref=gerrit_ref,
                                log_path=log_path,
                                zuul_ref=zuul_ref,
                                zuul_project=zuul_project,
                                url=buildurl))
            session.commit()


def gen_html(session, html_file, table_file, stats_hours):
    refs_done = []
    fp = open(table_file, "w")
    fp.write('<table border="1" cellspacing="0">')
    fp.write("<tr class='headers'><td>&nbsp;</td>")
    for job_name in job_names:
        fp.write("<td class='headers'><b>%s</b></td>" %
                 job_name.replace("gate-tripleo-ironic-", ""))
    fp.write("</tr>")
    count = 0
    for job in session.query(Job).order_by(desc(Job.dt)):
        if count > 500:
            break
        if job.zuul_ref in refs_done:
            continue
        refs_done.append(job.zuul_ref)
        count += 1

        job_columns = ""
        # Don't need this in a few days 19/2/2015
        # (once jobs being reported are new format)
        this_gerrit_ref = job.gerrit_ref.split(" ")[-1]
        this_gerrit_num = this_gerrit_ref.split(",")[0]
        for job_name in job_names:
            job_columns += "<td>"
            for job in session.query(Job).\
                    filter(Job.zuul_ref == job.zuul_ref).\
                    filter(Job.name == job_name).\
                    order_by(desc(Job.dt)).all():

                # For recent completed jobs get the logs
                if job.status in ["SUCCESS", "FAILURE", "ABORTED"] and \
                        "ironic-undercloud" not in job.log_path:
                    td = now - job.dt
                    if ((td.seconds + (td.days*24*60*60)) <
                            (stats_hours * (60*60))):
                        parse_logs('http://logs.openstack.org/%s/console.html'
                                   % job.log_path)

                color = colors.get(job.status, "#999999")
                job_columns += '<font color="%s">' % color
                job_columns += '<a STYLE="color : %s" href="%s">%s</a>' % \
                               (color, job.url, job.dt.strftime("%m-%d %H:%M"))
                job_columns += ' - %.0f min ' % (job.duration / 60)
                job_columns += '<a STYLE="text-decoration:none" '
                job_columns += 'href="http://logs.openstack.org/%s">log</a>' %\
                               job.log_path

                successes = len(session.query(Job).
                                filter(Job.status == "SUCCESS").
                                filter(Job.name == job_name).
                                filter(Job.gerrit_ref.like("%s,%%" %
                                                           (this_gerrit_num))).
                                all())
                failures = len(session.query(Job).
                               filter(Job.status == "FAILURE").
                               filter(Job.name == job_name).
                               filter(Job.gerrit_ref.like("%s,%%" %
                                                          (this_gerrit_num))).
                               all())
                job_columns += ' %d/%d' % (successes, (successes+failures))

                job_columns += '</font><br/>'
            job_columns += "</td>"
        if (count % 2) == 1:
            fp.write("<tr class='tr0'><td>")
        else:
            fp.write("<tr class='tr1'><td>")
        project = ""
        if job.zuul_project:
            project = job.zuul_project.split("/")[-1]
        fp.write("<a href=\"https://review.openstack.org/#/"
                 "c/%s\">%s %s</a></td>"
                 % (this_gerrit_ref.replace(",", "/"),
                    this_gerrit_ref, project))
        fp.write(job_columns)
        fp.write("</tr>")
    fp.write("<table>")
    fp.close()

    with open(html_file, "w") as f:
        f.write('<html><head/><body>')
        f.write(open(table_file).read())
        f.write("<table></body></html>")


def parse_logs(logurl):
    if not os.path.isdir("./log"):
        os.mkdir("./log")
    logfile = os.path.join("./log", logurl.replace("/", "_").replace(":", "_"))
    if not os.path.isfile(logfile):
        urllib.urlretrieve(logurl, logfile)


def main(args=sys.argv[1:]):
    parser = argparse.ArgumentParser(
        description=("Get details of tripleo ci jobs and generates a html "
                     "report."))
    parser.add_argument('-f', action='store_true',
                        help='Fetch recent data from jenkins servers.')
    parser.add_argument('-n', type=int, default=3,
                        help='Stop processing downloading from jenkins after '
                             'hitting this number of builds already in the '
                             'database i.e. assume we already have the rest.')
    parser.add_argument('-o', default="tripleo-jobs.html", help="html file")
    parser.add_argument('-d', default="tripleo-jobs.db", help="sqlite file")
    opts = parser.parse_args(args)

    engine = create_engine('sqlite:///%s' % opts.d)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    if opts.f:
        get_data(session, opts.n)
    gen_html(session, opts.o, "%s-table" % opts.o, 24)

if __name__ == '__main__':
    exit(main())
