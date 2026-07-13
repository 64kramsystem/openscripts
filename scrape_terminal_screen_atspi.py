#!/usr/bin/env python3

import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


class ScrapeError(Exception):
    pass


def children(node):
    for index in range(node.get_child_count()):
        yield node.get_child_at_index(index)


def descendants(node):
    for child in children(node):
        yield child
        yield from descendants(child)


def scrape(desktop, text_api=Atspi.Text):
    tilix_apps = [node for node in children(desktop) if node.get_name() == "tilix"]
    terminals = (
        node
        for app in tilix_apps
        for node in descendants(app)
        if node.get_role() == Atspi.Role.TERMINAL
        and node.get_state_set().contains(Atspi.StateType.FOCUSED)
    )
    terminal = next(terminals, None)
    if terminal is None:
        raise ScrapeError("focused terminal is not Tilix")
    if "Text" not in terminal.get_interfaces():
        raise ScrapeError("focused Tilix terminal does not expose accessible text")

    character_count = text_api.get_character_count(terminal)
    return text_api.get_text(terminal, 0, character_count)


def main():
    Atspi.init()
    try:
        print(scrape(Atspi.get_desktop(0)), end="")
    except ScrapeError as error:
        print(f"scrape_terminal_screen: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
