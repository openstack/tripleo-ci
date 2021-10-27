#!/usr/bin/python

import json
import os
from datetime import datetime

import dateutil.parser
import pytz
import requests
from dateutil.relativedelta import relativedelta

BOARD_BLACKLIST = os.environ.get('TRELLO_BOARD_BLACKLIST')

#
# API CONTEXT OBJECT
#


class ApiContext(object):
    def __init__(self, config):
        self.config = config
        self._apiVersion = 1
        self.apiToken = config.get('TrelloConfig', 'token')
        self.apiKey = config.get('TrelloConfig', 'api_key')
        self._payload = {'key': self.apiKey, 'token': self.apiToken}

    @property
    def ApiRootUrl(self):
        return "https://trello.com/%s" % self._apiVersion

    @property
    def Payload(self):
        return self._payload


#
# BOARDS
#
class Boards(object):
    def __init__(self, context):
        self._api = context

    # note: it's not currently possible to nuke a board, only to close it
    def create(self, name, description=None):
        "create a new board."
        response = requests.post(
            "%s/boards" % self._api.ApiRootUrl,
            params=self._api.Payload,
            data=dict(name=name, desc=description),
        )
        response.raise_for_status()
        jsonResponse = json.loads(response.text)
        return jsonResponse

    def get_all_by_member(self, memberNameOrId):
        "Obtain data struct for a board by name."

        memberBoardsUrl = '{0}/members/{1}/boards'.format(
            self._api.ApiRootUrl, memberNameOrId
        )
        response = requests.get(memberBoardsUrl, params=self._api.Payload)
        response.raise_for_status()
        jsonResponse = json.loads(response.text)
        return jsonResponse

    def get_name(self, boardId):
        "Obtain data struct for a board by name."

        memberBoardsUrl = '{0}/boards/{1}'.format(self._api.ApiRootUrl, boardId)
        response = requests.get(memberBoardsUrl, params=self._api.Payload)
        response.raise_for_status()
        jsonResponse = json.loads(response.text)
        return jsonResponse['name']

    def get_all_by_member_and_name(
        self, memberNameOrId, boardName, raiseExceptionIfDuplicates=True
    ):
        "Get all boards for a member, and return those matching a name (handles duplicate names)."
        boards = self.get_all_by_member(memberNameOrId)
        boardsToReturn = [b for b in boards if b['name'] == boardName]

        if raiseExceptionIfDuplicates:
            if len(boardsToReturn) != 1:
                raise AssertionError(
                    "ERROR: get_all_by_member_and_name({0}, {1}) - NO DUPES ALLOWED".format(
                        memberNameOrId, boardName
                    )
                )

        return boardsToReturn

    def get_lists(self, boardId):
        "Get all lists on a board."

        boardListsUrl = '{0}/boards/{1}/lists'.format(self._api.ApiRootUrl, boardId)
        resp = requests.get(boardListsUrl, params=self._api.Payload)
        resp.raise_for_status()
        jsonResp = json.loads(resp.text)
        return jsonResp

    def get_cards(self, boardId):
        "Get all cards on a board."

        boardListsUrl = '{0}/boards/{1}/cards'.format(self._api.ApiRootUrl, boardId)
        resp = requests.get(boardListsUrl, params=self._api.Payload)
        resp.raise_for_status()
        jsonResp = json.loads(resp.text)
        return jsonResp

    def get_lists_by_name(self, boardId, listName, raiseExceptionIfDuplicates=True):
        "Get all lists associated with a board by name."
        lists = self.get_lists(boardId)
        listsToReturn = [lst for lst in lists if lst['name'] == listName]

        if raiseExceptionIfDuplicates:
            if len(listsToReturn) != 1:
                raise AssertionError(
                    "ERROR: get_lists_by_name({0}, {1}) - NO DUPES ALLOWED".format(
                        boardId, listName
                    )
                )

        return listsToReturn

    def get_lists_by_id(self, boardId, listId, raiseExceptionIfDuplicates=True):
        "Get all lists associated with a board by id."
        lists = self.get_lists(boardId)
        listsToReturn = [lst for lst in lists if lst['id'] == listId]

        # if raiseExceptionIfDuplicates == True:
        #    if len(listsToReturn) != 1:
        #        raise AssertionError("ERROR: get_lists_by_id({0}, {1}) - NO DUPES ALLOWED".format(boardId, listId))

        return listsToReturn

    # TODO: for now do this expensive way (getting everything and filtering) vs. a nice nuanced query
    def get_single_by_member_and_name(self, memberNameOrId, boardName):
        board = self.get_all_by_member_and_name(memberNameOrId, boardName)
        id = board[0]['id']
        return id

    def get_single_list_by_name(self, boardId, listName):
        lists = self.get_lists_by_name(boardId, listName)
        id = lists[0]['id']
        return id

    def get_single_list_by_id(self, boardId, listId):
        lists = self.get_lists_by_id(boardId, listId)
        try:
            name = lists[0]['name']
        except IndexError:
            name = "unknown"
        return name


#
# MEMBERS
#
class Members(object):
    def __init__(self, context):
        self._api = context

    def get_member(self, memberName):
        "Get member data based on name"
        membersUrl = '{0}/members/{1}'.format(self._api.ApiRootUrl, memberName)
        response = requests.get(membersUrl, params=self._api.Payload)
        response.raise_for_status()
        return json.loads(response.text)

    def get_member_id(self, memberName):
        "Get member id based on name"
        return self.get_member(memberName)['id']

    def get_member_name(self, memberId):
        "Get member name based on id"
        return self.get_member(memberId)['fullName'].encode('ascii', 'ignore')

    def get_member_names_from_list(self, memberId):
        "Get member name based on id"
        if isinstance(memberId, list):
            names = [self.get_member_name(member) for member in memberId]
            return ', '.join(names)
        else:
            raise TypeError()

    def get_member_cards(self, memberId):
        # get all the open cards from a particular member
        membersUrl = '{0}/members/{1}/cards/open'.format(self._api.ApiRootUrl, memberId)
        response = requests.get(membersUrl, params=self._api.Payload)
        response.raise_for_status()

        # scrub trello cards for blacklisted boards
        data = json.loads(response.text)
        remove_list = []
        # create a list of cards that are blacklisted
        for i in range(len(data)):
            if BOARD_BLACKLIST == data[i]['idBoard'].encode("ascii"):
                remove_list.append(i)
        return data


#
# CARDS
#
class Cards(object):
    def __init__(self, context):
        self._api = context

    def get_card(self, cardId):
        cardUrl = '{0}/cards/{1}'.format(self._api.ApiRootUrl, cardId)
        response = requests.get(cardUrl, params=self._api.Payload)
        response.raise_for_status()
        return json.loads(response.text)

    def get_card_due_date(self, cardId):
        "Get member id based on name"
        return self.get_card(cardId)['due']

    def get_card_labels(self, cardId):
        return self.get_card(cardId)['labels']

    def get_card_members(self, cardId):
        return self.get_card(cardId)['idMembers']

    def create(self, name, idList, due=None, desc=None):
        "create a new card, optionally setting a due date and description."
        response = requests.post(
            "%s/cards" % self._api.ApiRootUrl,
            params=self._api.Payload,
            data=dict(name=name, idList=idList, due=due, desc=desc),
        )
        response.raise_for_status()
        return json.loads(response.text)

    def add_comment_to_card(self, cardId, comment):
        "Add a member to a card"
        postMemberToCardUrl = '{0}/cards/{1}/actions/comments'.format(
            self._api.ApiRootUrl, cardId
        )
        response = requests.post(
            postMemberToCardUrl, params=self._api.Payload, data={'text': comment}
        )
        response.raise_for_status()
        return json.loads(response.text)

    def add_due_date_to_card(self, card, date):
        "Add a due date to a trello card"
        putDueDateToCardUrl = '{0}/cards/{1}'.format(self._api.ApiRootUrl, card['id'])
        response = requests.put(
            putDueDateToCardUrl, params=self._api.Payload, data={'due': date}
        )
        response.raise_for_status()
        return json.loads(response.text)

    def check_card_overdue(self, cardId, blocking_labels, overdue_notice):
        now = datetime.now(pytz.utc)
        due = dateutil.parser.parse(self.get_card_due_date(cardId))
        delta = relativedelta(now, due)
        if delta.days > 0 or delta.months > 0:
            if not self.check_card_blocked_label(cardId, blocking_labels):
                self.add_comment_to_card(cardId, overdue_notice)
                return True
        else:
            return False

    def check_card_blocked_label(self, cardId, blocking_labels):
        labels = self.get_card_labels(cardId)
        if [label for label in labels if label['name'] in blocking_labels]:
            return True
        else:
            return False

    def get_cards(self, listId, filterArg="all"):
        "Get cards on a given list"
        getCardsUrl = '{0}/lists/{1}/cards/{2}'.format(
            self._api.ApiRootUrl, listId, filterArg
        )
        response = requests.get(getCardsUrl, params=self._api.Payload)
        response.raise_for_status()
        return json.loads(response.text)

    def update(self, card_id, desc):
        "update card"
        url = "%s/cards/%s" % (self._api.ApiRootUrl, card_id)
        response = requests.put(url, params=self._api.Payload, data=dict(desc=desc))
        response.raise_for_status()
        return json.loads(response.text)
