"""The battle ATB gauge (battle/atb_gauge.s): each character's action timer as an FF6-style gauge over "/max HP".

The party window's rows list the characters in vanilla's display order (slots 1, 3, 0, 4, 2, present ones only), not
in slot order: a gauge drawn by slot showed one character's turn on another's row.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest
from _ff4kintsuki import (
    BATTLE_MENU_PANEL,
    CMD_ITEM,
    assert_screenshot_matches_golden,
    choose_command,
    fresh_late_battle,
    tap,
)
from kintsuki import Button

sys.path.insert(0, str(Path(__file__).parents[1]))
from utils import atb_gauge

GOLDENS = Path(__file__).parent / "goldens" / "battle_atb"
FONT = Path(__file__).parents[1] / "fonts" / "8x8.bin"
STRIP = Path(__file__).parents[1] / "fonts" / "atb_gauge.png"
HP_TEXT = 0x7EB9DE  # two 9-cell rows per character, the bottom one "HHHH/MMMM"
ROW = 36
BOTTOM = 18
ACTING = 0x7E1822
MENU_OPEN = 0x7E00D7
FILLING_PALETTE = 0x04  # grey while it fills, the text's white (palette 0) when full
MAIN_VIEW_HP = 0x7EBED0  # a character per 2 rows of 64 bytes; the right cap goes in the cell after the 9
DISPLAY_ORDER = (1, 3, 0, 4, 2)
DIGITS = range(0x80, 0x8A)
SLASH = 0xC7
TARGET_SELECT = 0x7E004D  # msb: the status window is up to pick a character (notes/ff4j-sfc-ram-map.txt)


def _bottom_cells(emu, row: int) -> list[tuple[int, int]]:
    base = HP_TEXT + row * ROW + BOTTOM
    return [(emu.read(base + 2 * c), emu.read(base + 2 * c + 1)) for c in range(9)]


def _row_of(emu, slot: int) -> int:
    """The party window row showing `slot` (vanilla's packing; every slot present in the late save)."""
    present = [s for s in DISPLAY_ORDER if emu.read(0x7E2000 + s * 0x80)]
    return present.index(slot)


def _fill(cells: list[tuple[int, int]]) -> int:
    return sum(tile - atb_gauge.FILL_TILES.start for tile, _ in cells[5:9])


def _right_cap(emu, row: int) -> int:
    return emu.read(MAIN_VIEW_HP + row * 128 + 64 + 9 * 2)


def test_merge_puts_the_strip_in_blank_slots() -> None:
    merged = atb_gauge.merge(FONT.read_bytes(), STRIP)
    font = FONT.read_bytes()
    changed = {i // 16 for i in range(len(font)) if merged[i] != font[i]}
    assert changed == set(atb_gauge.SLOTS)


def test_merge_refuses_a_glyph_slot() -> None:
    font = bytearray(FONT.read_bytes())
    font[atb_gauge.CAP_LEFT * 16] ^= 0xFF
    with pytest.raises(ValueError, match="not blank"):
        atb_gauge.merge(bytes(font), STRIP)


SETTING = 0x7E16B3  # Options, "Jauge ATB": bit 0 (saved; 0, off, in every save)


@pytest.fixture
def battle():
    emu = fresh_late_battle(settings=((SETTING, 1),))
    emu.run_frames(8)  # vanilla's HP text redraw puts "/max" back for a few frames before the gauge goes over it
    try:
        yield emu
    finally:
        emu.close()


def test_the_rows_keep_the_hp_and_show_a_gauge(battle) -> None:
    for row in range(5):
        cells = _bottom_cells(battle, row)
        assert cells[3][0] in DIGITS  # the current HP's last digit
        assert cells[4][0] == atb_gauge.CAP_LEFT
        assert all(tile in atb_gauge.FILL_TILES for tile, _ in cells[5:9])
        assert _right_cap(battle, row) == atb_gauge.CAP_RIGHT


def test_the_deciding_character_s_gauge_is_full(battle) -> None:
    cells = _bottom_cells(battle, _row_of(battle, battle.read(ACTING)))
    assert _fill(cells) == 32
    assert not any(attr & FILLING_PALETTE for _, attr in cells[4:])


def test_acting_empties_the_gauge(battle) -> None:
    actor = battle.read(ACTING)
    row = _row_of(battle, actor)
    tap(battle, Button.A, gap=20)  # Attack
    tap(battle, Button.A, gap=20)  # the first monster
    lowest = 32
    for _ in range(400):
        battle.run_frames(1)
        lowest = min(lowest, _fill(_bottom_cells(battle, row)))
        if lowest < 8:
            break
    assert lowest < 8


def test_the_target_picker_shows_the_max_hp(battle) -> None:
    """Picking whom an item goes to, the status window shows "/max HP" again: the max is what the choice turns on,
    and that window has no cell for the gauge's right cap."""
    choose_command(battle, CMD_ITEM)
    battle.run_frames(40)
    tap(battle, Button.DOWN, gap=20)
    tap(battle, Button.DOWN, gap=20)  # X-Potion
    tap(battle, Button.A, gap=4)
    tap(battle, Button.A, gap=40)  # use it: the hand goes to the party
    assert battle.read(TARGET_SELECT) & 0x80
    for row in range(5):
        cells = _bottom_cells(battle, row)
        assert cells[4][0] == SLASH
        assert all(tile in DIGITS for tile, _ in cells[5:9])


def test_the_party_window_golden(battle) -> None:
    assert_screenshot_matches_golden(battle, GOLDENS / "party.png", region=BATTLE_MENU_PANEL)


def _main_view_fill(emu, row: int) -> int | None:
    """Row's gauge fill as the main view shows it (what the NMI uploads), None when it shows none."""
    base = MAIN_VIEW_HP + row * 128 + 64 + 5 * 2
    tiles = [emu.read(base + 2 * c) for c in range(4)]
    if not all(t in atb_gauge.FILL_TILES for t in tiles):
        return None
    return sum(t - atb_gauge.FILL_TILES.start for t in tiles)


def test_the_gauges_never_step_back(battle) -> None:
    """Fills only grow between turns: the pace is per character (a tick of one did not restart another's), its clock
    a word (a wait of 256 updates wrapped it), a chosen command keeps the gauge full until the turn is over."""
    last: list[int | None] = [None] * 5
    steps_back = []
    for frame in range(1500):
        if battle.read(MENU_OPEN) and frame % 4 == 0:
            tap(battle, Button.A, hold=2, gap=0)  # Attack, the first monster
        battle.run_frames(1)
        for row in range(5):
            fill = _main_view_fill(battle, row)
            if fill is not None and last[row] is not None and 0 < fill < last[row]:
                steps_back.append((frame, row, last[row], fill))
            last[row] = fill
    assert steps_back == []


def test_off_by_default_the_rows_keep_their_max_hp() -> None:
    emu = fresh_late_battle()
    try:
        assert emu.read(SETTING) & 1 == 0
        for row in range(5):
            cells = _bottom_cells(emu, row)
            assert cells[4][0] == SLASH
            assert all(tile in DIGITS for tile, _ in cells[5:9])
    finally:
        emu.close()


RECORD = 0x7E2000  # a character per $80: +3 status 1 (bit 7 KO), +7 the HP
TIMERS = 0x7E2A07  # the action timer, a word, 21 bytes a fighter
ENABLED_TIMERS = 0x7E29EB  # per fighter, 2 bytes: $40 the action timer runs


def _fight(emu, frames: int, *, spare: int | None = None) -> None:
    for frame in range(frames):
        if emu.read(MENU_OPEN) and frame % 4 == 0 and emu.read(ACTING) != spare:
            tap(emu, Button.A, hold=2, gap=0)  # Attack, the first monster
        emu.run_frames(1)


def _knock_out(emu, slot: int) -> None:
    emu.write(RECORD + slot * 0x80 + 3, emu.read(RECORD + slot * 0x80 + 3) | 0x80)
    emu.write(RECORD + slot * 0x80 + 7, 0)
    emu.write(RECORD + slot * 0x80 + 8, 0)


def _revive(emu, slot: int, timer: int) -> None:
    """As vanilla's Life (battle magic effect $0a): KO cleared, a new action timer, the timer running again."""
    emu.write(RECORD + slot * 0x80 + 3, emu.read(RECORD + slot * 0x80 + 3) & 0x7E)
    emu.write(RECORD + slot * 0x80 + 7, 100)
    emu.write(TIMERS + slot * 21, timer)
    emu.write(TIMERS + slot * 21 + 1, 0)
    emu.write(TIMERS + slot * 21 + 2, 0)
    emu.write(ENABLED_TIMERS + slot * 2, 0x40)


def _filling_slot(emu) -> int:
    """A slot whose gauge is part-way: its timer still running."""
    _fight(emu, 400)
    return max(range(5), key=lambda slot: emu.read16(TIMERS + slot * 21))


def test_a_knocked_out_character_s_gauge_empties(battle) -> None:
    """Vanilla stops a KO'd character's action timer where it was: the gauge stayed part-filled, as if a turn were
    coming."""
    slot = _filling_slot(battle)
    _knock_out(battle, slot)
    _fight(battle, 120, spare=slot)
    assert _main_view_fill(battle, _row_of(battle, slot)) == 0


def test_a_revived_character_s_gauge_fills_from_empty(battle) -> None:
    """Life's new timer is a new turn even when it is shorter than the one KO stopped."""
    slot = _filling_slot(battle)
    _knock_out(battle, slot)
    _fight(battle, 60, spare=slot)
    _revive(battle, slot, timer=1)
    battle.run_frames(2)
    assert _main_view_fill(battle, _row_of(battle, slot)) < 8
