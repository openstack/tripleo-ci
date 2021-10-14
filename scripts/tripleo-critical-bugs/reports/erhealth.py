import requests
import re

base_url = "https://opendev.org/openstack/tripleo-ci-health-queries/raw/branch/master/output/elastic-recheck/"
health_url = "http://ci-health.tripleo.org/"


def get_health_link(bug_id):
    response = requests.get(base_url + str(bug_id) + ".yaml")
    if response.status_code == 200:
        return "\n" + health_url + "#" + str(bug_id)
    return ""


def get_bug_id_from_card(card):
    """Finds LP bug id in card name"""
    pattern = "^\\[CIX]\\[LP:((.*?))]"
    match_found = re.search(pattern, card["name"])
    if match_found:
        bug_id = match_found.group(1)
        return bug_id
    return None


def is_health_link_in_desc(card):
    """Checks if card has health link in desc"""
    pattern = health_url
    return re.search(pattern, card["desc"])


def add_health_link(card):
    """Adds health link if present to card"""
    # Updates health link in each card for now
    # This doesn't check if health link is already present
    bug_id = get_bug_id_from_card(card)
    if bug_id:
        health_link = get_health_link(bug_id)
        desc = card["desc"] + health_link
        return desc
    return card["desc"]
