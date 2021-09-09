import requests

base_url = "https://opendev.org/openstack/tripleo-ci-health-queries/raw/branch/master/output/elastic-recheck/"
health_url = "http://health.sbarnea.com/"


def get_health_link(bug_id):
    response = requests.get(base_url + str(bug_id) + ".yaml")
    if response.status_code == 200:
        return health_url + "#" + str(bug_id)
    return ""
