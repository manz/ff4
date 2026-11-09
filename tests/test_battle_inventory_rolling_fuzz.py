"""Random walks through the battle item list: the rows on screen are the rows the cursor picks from.

The list renders each row into one of six slots (five visible, one prefetched), and the HDMA scroll shows them from
`buffer_pos`. Every render is recorded as slot -> (item index, id, quantity at render time). After each input the
visible slots must hold the items `top .. top + 4`, as they are now, with `top` the cursor's item minus its row
($63 - $60). Inputs: scrolls, swaps (A, move to another item, A), a swap started then cancelled, and closing the list
(B), reopened from the command menu.
"""
from __future__ import annotations

import random

import pytest
from _ff4kintsuki import choose_command, kss_path, load_emu_from_kss, tap
from kintsuki import Button, Emu

KSS = kss_path("ff4-battle-monsters-item.kss")
BATTLE_ITEMS = 0x7E321A  # 4-byte records: flags, id, quantity, -
TOTAL_ITEMS = 48
VISIBLE_ROWS = 5
BUFFER_SLOTS = 6
TOP_ROW, BUFFER_POS, EDGE_ROW, SLOT_INDEX = 0x7EEF97, 0x7EEF98, 0x7EEF99, 0x7EEF82
CURSOR_ITEM, CURSOR_ROW = 0x7E0063, 0x7E0060
CURSOR_TYPE, INVENTORY_CURSOR = 0x7E1823, 5
MENU_WINDOWS_OPEN, INVENTORY_WINDOW = 0x7E004A, 0x04
BATTLE_MENU_OPEN = 0x7E00D7
ITEM = 0x01  # the Item command
STEPS = 60
SEEDS = range(4)
BUTTONS = {"D": Button.DOWN, "U": Button.UP, "A": Button.A, "B": Button.B}


class ListWalk:
    """Drives the item list and keeps the slot -> rendered item record."""

    def __init__(self, emu: Emu, rng: random.Random) -> None:
        self.emu, self.rng = emu, rng
        self.slots: dict[int, tuple[int, tuple[int, int]]] = {}
        self.inputs: list[str] = []
        render = emu.lookup_symbol_addr("battle/inventory_rolling._render_item_to_circular_slot")
        assert render is not None
        emu.add_exec_callback(render, render, self._rendered)

    def _item(self, index: int) -> tuple[int, int]:
        record = BATTLE_ITEMS + 4 * index
        return self.emu.read(record + 1), self.emu.read(record + 2)

    def _rendered(self, *_) -> None:
        index = self.emu.read(EDGE_ROW)
        self.slots[self.emu.read(SLOT_INDEX)] = (index, self._item(index))

    def list_open(self) -> bool:
        return self.emu.read(CURSOR_TYPE) == INVENTORY_CURSOR and bool(self.emu.read(MENU_WINDOWS_OPEN) & INVENTORY_WINDOW)

    def press(self, key: str, gap: int | None = None) -> None:
        tap(self.emu, BUTTONS[key], gap=gap if gap is not None else self.rng.choice((2, 4, 12, 30)))
        self.inputs.append(key)

    def open_items(self) -> None:
        for _ in range(200):
            if self.emu.read(BATTLE_MENU_OPEN) and self.emu.read(CURSOR_TYPE) != INVENTORY_CURSOR:
                break
            self.emu.run_frames(5)
        choose_command(self.emu, ITEM)
        self.emu.run_frames(30)
        self.inputs.append("|item|")

    def swap(self) -> None:
        """A on the cursor's item, move to another one, A: never A twice on one item (that uses it)."""
        start = self.emu.read(CURSOR_ITEM)
        self.press("A", 30)
        direction = self.rng.choice("DU")
        for _ in range(12):
            self.press(direction)
            self.emu.run_frames(20)
            if self.emu.read(CURSOR_ITEM) != start:
                self.press("A", 30)
                return
        self.press("B", 30)

    def step(self) -> None:
        action = self.rng.choices("DUSXC", weights=(6, 5, 3, 1, 1))[0]
        if action in "DU":
            self.press(action)
        elif action == "S":
            self.swap()
        elif action == "X":
            self.press("A", 30)
            self.press("B", 30)
        else:
            self.press("B", 30)
        self.emu.run_frames(40)

    def mismatches(self) -> list[str]:
        cursor = self.emu.read(CURSOR_ITEM)
        if cursor >= TOTAL_ITEMS:  # in the equipped-hands window above the list
            return []
        top, pos = self.emu.read(TOP_ROW), self.emu.read(BUFFER_POS)
        found = [] if top == cursor - self.emu.read(CURSOR_ROW) else [f"top row {top}, cursor says otherwise"]
        for row in range(VISIBLE_ROWS):
            slot = (pos + row) % BUFFER_SLOTS
            want = (top + row, self._item(top + row))
            if self.slots.get(slot) != want:
                found.append(f"row {row} (slot {slot}): {self.slots.get(slot)}, want {want}")
        return found


@pytest.mark.parametrize("seed", SEEDS)
def test_visible_rows_follow_the_cursor(seed):
    emu = load_emu_from_kss(KSS, settle_frames=10)
    try:
        walk = ListWalk(emu, random.Random(seed))
        walk.open_items()
        for _ in range(STEPS):
            if not walk.list_open():
                walk.open_items()
                continue
            walk.step()
            if walk.list_open():
                assert walk.mismatches() == [], "".join(walk.inputs[-40:])
    finally:
        emu.close()
