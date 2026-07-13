#!/usr/bin/env python3

import unittest

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

import scrape_terminal_screen_atspi as scraper


class StateSet:
    def __init__(self, focused=False):
        self.focused = focused

    def contains(self, state):
        return state == Atspi.StateType.FOCUSED and self.focused


class Node:
    def __init__(self, name="", role=Atspi.Role.INVALID, focused=False, interfaces=(), children=()):
        self.name = name
        self.role = role
        self.state_set = StateSet(focused)
        self.interfaces = list(interfaces)
        self.children = list(children)

    def get_name(self):
        return self.name

    def get_role(self):
        return self.role

    def get_state_set(self):
        return self.state_set

    def get_interfaces(self):
        return self.interfaces

    def get_child_count(self):
        return len(self.children)

    def get_child_at_index(self, index):
        return self.children[index]


class TextApi:
    @staticmethod
    def get_character_count(terminal):
        return len(terminal.text)

    @staticmethod
    def get_text(terminal, start, end):
        return terminal.text[start:end]


def desktop_with(*applications):
    return Node(children=applications)


def tilix_with(terminal):
    return Node(name="tilix", children=(Node(children=(terminal,)),))


class ScrapeTest(unittest.TestCase):
    def test_returns_focused_tilix_terminal_text(self):
        terminal = Node(role=Atspi.Role.TERMINAL, focused=True, interfaces=("Text",))
        terminal.text = "visible terminal text\n"

        self.assertEqual(
            scraper.scrape(desktop_with(tilix_with(terminal)), TextApi),
            "visible terminal text\n",
        )

    def test_rejects_desktop_without_tilix(self):
        with self.assertRaisesRegex(scraper.ScrapeError, "focused terminal is not Tilix"):
            scraper.scrape(desktop_with(Node(name="mate-terminal")), TextApi)

    def test_rejects_tilix_without_focused_terminal(self):
        terminal = Node(role=Atspi.Role.TERMINAL, interfaces=("Text",))

        with self.assertRaisesRegex(scraper.ScrapeError, "focused terminal is not Tilix"):
            scraper.scrape(desktop_with(tilix_with(terminal)), TextApi)

    def test_rejects_terminal_without_text_interface(self):
        terminal = Node(role=Atspi.Role.TERMINAL, focused=True)

        with self.assertRaisesRegex(
            scraper.ScrapeError,
            "focused Tilix terminal does not expose accessible text",
        ):
            scraper.scrape(desktop_with(tilix_with(terminal)), TextApi)


if __name__ == "__main__":
    unittest.main()
