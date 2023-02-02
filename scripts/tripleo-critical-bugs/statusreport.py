#!/usr/bin/env python

# The MIT License (MIT)
# Copyright (c) 2017 Wes Hayutin <weshayutin@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""
takes a list of launchpad bugs that have the tag 'promotion-blocker'
then compares the list to cards on the cix trello board.  If there
is a lp bug that does not have a card it will open a trello card
"""

import click
import configparser

from reports.erhealth import get_health_link, add_health_link, is_health_link_in_desc
from reports.launchpad import LaunchpadReport
import reports.trello as trello


class StatusReport(object):
    """
    compares a list of launchpad bugs to a list
    of trello cards.
    """

    def __init__(self, config):
        self.config = config
        self.brief_status = {}
        self.detailed_status = {}

    def summarise_launchpad_bugs(self):
        """
        a list of open bugs with promotion-blocker
        also returns a list of closed bugs if action needs to
        be taken
        """
        if not self.config.has_section('LaunchpadBugs'):
            return

        bugs = self.config["LaunchpadBugs"]
        report = LaunchpadReport(bugs, self.config)
        bugs_with_alerts_open, bugs_with_alerts_closed = report.generate()
        return bugs_with_alerts_open, bugs_with_alerts_closed

    def print_report(self, bug_list):
        """print the bugs to the console"""
        bug_number_list = []
        for key, value in bug_list.items():
            print(key)
            bug_number_list.append(str(key))
        return bug_number_list

    def _get_config_items(self, section_name, prefix=None):
        if not self.config.has_section(section_name):
            return {}

        items = {
            k: v
            for (k, v) in self.config.items(section_name)
            if not k.startswith('_') and (prefix is None or k.startswith(prefix))
        }
        return items

    def compare_bugs_with_cards(self, list_of_bugs, cards):
        """
        compare a list of bugs to trello cards by checking for
        the bug number in the title of the trello card
        """
        open_bugs = list_of_bugs
        cards_outtage_names = []
        for card in cards:
            cards_outtage_names.append(card['name'])
            print(card['name'].encode('utf-8'))

        match = []
        for card in cards_outtage_names:
            for key in open_bugs:
                key = str(key)
                if key in card:
                    match.append(int(key))
        print("##########################################")
        print("openbugs " + str(set(open_bugs)))
        print("match " + str(set(match)))
        critical_bugs_with_out_escalation_cards = list(set(open_bugs) - set(match))
        return critical_bugs_with_out_escalation_cards

    def create_escalation(
        self, config, critical_bugs_with_out_escalation_cards, list_of_bugs, trello_list
    ):
        """
        create a trello card in the triage list of the cix board
        """
        if not critical_bugs_with_out_escalation_cards:
            print("There are no bugs that require a new escalation")
        else:
            # send email to list
            for bug in critical_bugs_with_out_escalation_cards:
                bug_title = list_of_bugs[bug].title
                bug_link = list_of_bugs[bug].web_link
                health_link = get_health_link(list_of_bugs[bug].id)

                card_title = (
                    "[CIX][LP:" + str(bug) + "][tripleoci][proa] " + str(bug_title)
                )

                # create escalation card
                trello_api_context = trello.ApiContext(config)
                trello_cards = trello.Cards(trello_api_context)
                trello_cards.create(
                    card_title, trello_list, desc=bug_link + health_link
                )


@click.command()
@click.option(
    "--config_file",
    default="config/critical-alert-escalation.cfg",
    help="Defaults to 'config/critical-alert-escalation.cfg'",
)
@click.option("--trello_token", required=True, help="Your Trello Token")
@click.option("--trello_api_key", required=True, help="Your Trello api key")
@click.option("--trello_board_id", required=True, help="The trello board id")
def main(config_file, trello_token, trello_api_key, trello_board_id):
    """
    get the list of promotion-blocker bugs
    compare the list to trello
    create cards as needed
    """

    config = configparser.ConfigParser()
    config.read(config_file)
    config['TrelloConfig']['token'] = trello_token
    config['TrelloConfig']['api_key'] = trello_api_key
    config['TrelloConfig']['board_id'] = trello_board_id

    report = StatusReport(config)

    bugs_with_alerts_open, bugs_with_alerts_closed = report.summarise_launchpad_bugs()

    print("*** open critical bugs ***")
    print("*** closed critical bugs ***")
    report.print_report(bugs_with_alerts_closed)

    trello_api_context = trello.ApiContext(config)
    trello_boards = trello.Boards(trello_api_context)

    trello_new_list = trello_boards.get_lists_by_name(
        config.get('TrelloConfig', 'board_id'), config.get('TrelloConfig', 'list_new')
    )
    trello_new_list_id = str(trello_new_list[0]['id'])

    all_cards_on_board = trello_boards.get_cards(config.get('TrelloConfig', 'board_id'))
    print("all cards " + str(len(all_cards_on_board)))

    # Add health link if available to card without health link
    for card in all_cards_on_board:
        if not is_health_link_in_desc(card):
            desc = add_health_link(card)
            trello_api_context = trello.ApiContext(config)
            trello_cards = trello.Cards(trello_api_context)
            trello_cards.update(card["id"], desc)
            print("Updated card " + card["name"])
    cards_outtage = all_cards_on_board

    critical_bugs_with_out_escalation_cards = report.compare_bugs_with_cards(
        bugs_with_alerts_open, cards_outtage
    )
    print(
        "critical bugs not tracked on board "
        + str(critical_bugs_with_out_escalation_cards)
    )

    report.create_escalation(
        config,
        critical_bugs_with_out_escalation_cards,
        bugs_with_alerts_open,
        trello_new_list_id,
    )


if __name__ == '__main__':
    main()
