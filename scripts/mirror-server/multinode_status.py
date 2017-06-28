#!/usr/bin/env python
import gzip
import logging
import os
import re
import requests
from requests import ConnectionError
from requests.exceptions import Timeout
import sys

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
log = logging.getLogger('scraper')
log.setLevel(logging.DEBUG)

dlrn_re = re.compile(
    r'((?P<p1>[0-9a-z]{2})/(?P<p2>[0-9a-z]{2})/(?P=p1)(?P=p2)[0-9a-z_]+)')


class config(object):
    WEB_TIMEOUT = (3.05, 1)
    runs = 4  # parse jobs from last 4 runs
    jobs = [
        'periodic-tripleo-ci-centos-7-scenario001-multinode-oooq',
        'periodic-tripleo-ci-centos-7-scenario002-multinode-oooq',
        'periodic-tripleo-ci-centos-7-scenario003-multinode-oooq',
        'periodic-tripleo-ci-centos-7-scenario004-multinode-oooq',
    ]
    api_url = 'http://health.openstack.org/runs/key/build_name/%s/recent'
    cache_file = "/tmp/cached_results_for_multinode_jobs.gz"
    # Only master now
    base_dir = '/var/www/html/builds/'


class Web(object):
    """Download web page

       Web class for downloading web page
    """
    def __init__(self, url):
        self.url = url

    def get(self):
        """Get web file

        :return: request obj
        """
        log.debug("GET %s", self.url)
        try:
            req = requests.get(self.url, timeout=config.WEB_TIMEOUT)
        except ConnectionError:
            log.error("Connection error when retrieving %s", self.url)
            return None
        except Timeout:
            log.error("Timeout reached when retrieving %s", self.url)
            return None
        except Exception as e:
            log.error("Unknown error when retrieving %s: %s", self.url, str(e))
            return None
        if int(req.status_code) != 200:
            log.warn("Page %s got status %s", self.url, req.status_code)
        return req


def last_runs(job, limit=1):
    web = Web(config.api_url % job)
    data = web.get()
    if data.ok:
        try:
            return data.json()[:limit]
        except ValueError as e:
            log.error("Failed to get JSON from %s:%s", config.api_url % job, e)
    else:
        log.error("Failed to get API data for %s", config.api_url % job)
    return []


def extract_dlrn(url):
    repo_url = url + "/logs/undercloud/etc/yum.repos.d/delorean.repo.txt.gz"
    web = Web(repo_url)
    req = web.get()
    if not req.ok:
        log.debug("Trying to download repo file again")
        web = Web(repo_url)
        req = web.get()
    if not req.ok:
        log.error("Failed to retrieve repo file: %s", repo_url)
        return None
    else:
        for line in req.content.split("\n"):
            if dlrn_re.search(line):
                return dlrn_re.search(line).group(1)
    log.error("Failed to find DLRN trunk hash in the file %s", repo_url)
    return None


def check_cached_result(link):
    if os.path.exists(config.cache_file):
        with gzip.open(config.cache_file, "rb") as f:
            for line in f:
                if link in line:
                    return line.split("=")[1].strip()
    return None


def add_to_cache(link, dlrn):
    with gzip.open(config.cache_file, "ab") as f:
        f.write(link + "=" + dlrn + "\n")


def process_job(run):
    link = run['link']
    result = run['status'] == 'success'
    dlrn = check_cached_result(link)
    if not dlrn:
        dlrn = extract_dlrn(link)
        if dlrn:
            add_to_cache(link, dlrn)
    return dlrn, result


def found(dlrn):
    if not dlrn:
        return False
    metadata = os.path.join(config.base_dir, dlrn, "metadata.txt")
    return os.path.exists(metadata)


def add_job_to_metadata(dlrn, job):
    path = os.path.join(config.base_dir, dlrn, "metadata.txt")
    success = job + "=SUCCESS"
    with open(path, "r") as f:
        if success in f.read():
            return
    with open(path, "a") as f:
        f.write(success + "\n")


def main():
    jobs = sys.argv[1:] or config.jobs
    for job in jobs:
        log.debug("Working on job %s", job)
        for run in last_runs(job, config.runs):
            log.debug("Checking run from %s and link %s",
                      run["start_date"], run["link"])
            dlrn_hash, passed = process_job(run)
            log.debug("Extracted DLRN=%s passed=%s",
                      str(dlrn_hash), str(passed))
            if passed and found(dlrn_hash):
                log.debug("Adding success to metdata of %s", dlrn_hash)
                add_job_to_metadata(dlrn_hash, job)


if __name__ == '__main__':
    main()
