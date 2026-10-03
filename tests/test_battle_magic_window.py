"""Battle magic window frame.

The two-column spell list fills BG3 page 1 rows 1-24 of the shared menu
buffer, and the list's scroll HDMA shows tilemap row 25 as the window's
bottom edge. The renderer has to draw that frame itself: the buffer
only carries the items window's shorter frame from battle start.

The items window shares that buffer but only draws its frame at battle
start, so opening it after the magic list has to rebuild it.

Spell names render in the battle VWF into the items window's tiles ($C0..$FB,
BG3 tiles $1C0..$1FB), only for the rows on screen. The command window slides
out under the list as it opens and back in as it closes, so its glyph tiles
must never change on the way; the items window repaints its own when it next
opens.

Starts a fresh encounter from the world map so nothing comes from a
battle an older build already set up.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button
from PIL import Image

from _ff4kintsuki import BATTLE_MENU_PANEL, PICTURE, assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")

BG3_PAGE1 = 0x7400
BOTTOM_ROW = 25
ITEMS_BOTTOM_ROW = 14
SIDE_ROWS = range(1, BOTTOM_ROW)
BORDER_LEFT, BORDER_RIGHT = 0x000B, 0x000C
BOTTOM = [0x000D, *([0x000E] * 30), 0x000F]
SPELL_TILES = range(0x1C0, 0x1FC)
CMD_GLYPHS = (0xB900, 0x300)  # command glyphs, BG3 tiles $190..$1BF
LIST_ROWS = 12
BG3_VWF_CHR = 0xB000  # BG3 tile $100 in VRAM (bytes)
CHR_BUFFER = 0x703000  # VWF CHR buffer, tile $00
CMD_WINDOW = (44, 140, 108, 200)
GOLDENS = Path(__file__).parent / "goldens" / "battle_magic"


def _row(emu, row: int) -> list[int]:
    raw = bytes(emu.vram_read_range((BG3_PAGE1 + row * 32) * 2, 64))
    return [raw[c * 2] | raw[c * 2 + 1] << 8 for c in range(32)]


def _fresh_battle():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.B, gap=20)
    for i in range(7):
        button = (Button.LEFT, Button.RIGHT)[i % 2]
        e.press(0, button)
        e.run_frames(40)
        e.release(0, button)
    e.run_frames(200)  # Cecil's command menu is up
    return e


def _open_magic(e) -> None:
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)
    e.run_frames(50)


def _open_items(e) -> None:
    for _ in range(3):
        tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)
    e.run_frames(50)


def _items_window(e) -> list[list[int]]:
    # The items transfer uploads only the rows its window shows.
    return [_row(e, r) for r in range(ITEMS_BOTTOM_ROW + 1)]


@pytest.fixture(scope="module")
def magic_emu():
    e = _fresh_battle()
    _open_magic(e)
    yield e
    e.close()


@pytest.fixture(scope="module")
def items_direct():
    e = _fresh_battle()
    _open_items(e)
    yield _items_window(e)
    e.close()


@pytest.fixture(scope="module")
def items_after_magic():
    e = _fresh_battle()
    _open_magic(e)
    tap(e, Button.B, gap=30)
    for _ in range(2):  # B leaves the cursor on Magie
        tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)
    e.run_frames(50)
    yield _items_window(e)
    e.close()


def test_bottom_border_row_is_drawn(magic_emu):
    assert _row(magic_emu, BOTTOM_ROW) == BOTTOM


def test_side_borders_run_down_to_the_bottom_row(magic_emu):
    edges = {(row[0], row[31]) for row in (_row(magic_emu, r) for r in SIDE_ROWS)}
    assert edges == {(BORDER_LEFT, BORDER_RIGHT)}


def test_items_after_magic_match_items_opened_directly(items_direct, items_after_magic):
    assert items_after_magic == items_direct


def _spell_tiles(emu) -> set[int]:
    cells = (c & 0x3FF for r in SIDE_ROWS for c in _row(emu, r))
    return {c for c in cells if c >= 0x100}


@pytest.fixture
def own_magic_emu():
    # Live emulator instances share VRAM and the framebuffer, so tests that
    # read them must not run against a module fixture another one followed.
    e = _fresh_battle()
    _open_magic(e)
    yield e
    e.close()


def test_spell_names_use_the_spell_tile_range(own_magic_emu):
    tiles = _spell_tiles(own_magic_emu)
    assert tiles and tiles <= set(SPELL_TILES)


def test_spell_glyphs_reach_vram(own_magic_emu):
    stale = [
        t
        for t in sorted(_spell_tiles(own_magic_emu))
        if bytes(own_magic_emu.vram_read_range(BG3_VWF_CHR + (t - 0x100) * 16, 16))
        != bytes(own_magic_emu.read(CHR_BUFFER + (t - 0x100) * 16 + i) for i in range(16))
    ]
    assert stale == []


def test_magic_window_golden(own_magic_emu):
    assert_screenshot_matches_golden(own_magic_emu, GOLDENS / "white_magic.png", region=BATTLE_MENU_PANEL)


def _to_turn(e, slot: int) -> None:
    # Everyone before `slot` attacks; the menu then comes up for `slot`.
    while e.read(0x7E1822) != slot:
        current = e.read(0x7E1822)
        tap(e, Button.A, gap=20)
        tap(e, Button.A, gap=20)
        for _ in range(1500):
            e.run_frames(1)
            if e.read(0x7E00D7) and e.read(0x7E1822) != current:
                break
        e.run_frames(40)


@pytest.mark.parametrize(
    ("slot", "downs", "name"),
    [(3, 1, "white"), (2, 1, "ninja"), (4, 1, "black"), (4, 2, "summon")],
)
def test_spell_list_golden(slot, downs, name):
    e = _fresh_battle()
    try:
        _to_turn(e, slot)
        for _ in range(downs):
            tap(e, Button.DOWN, gap=20)
        tap(e, Button.A, gap=20)
        e.run_frames(50)
        assert_screenshot_matches_golden(e, GOLDENS / f"{name}.png", region=BATTLE_MENU_PANEL)
    finally:
        e.close()


def _cmd_window(emu, path) -> bytes:
    emu.screenshot(str(path))
    return Image.open(path).convert("RGB").crop(PICTURE).crop(CMD_WINDOW).tobytes()


def test_command_window_comes_back_after_magic(tmp_path):
    e = _fresh_battle()
    try:
        tap(e, Button.DOWN, gap=20)  # hand on Magie, where B brings it back
        before = _cmd_window(e, tmp_path / "before.png")
        tap(e, Button.A, gap=20)
        e.run_frames(50)
        tap(e, Button.B, gap=30)
        e.run_frames(30)
        assert _cmd_window(e, tmp_path / "after.png") == before
    finally:
        e.close()


def _cmd_glyphs(emu) -> bytes:
    return bytes(emu.vram_read_range(*CMD_GLYPHS))


def _hold(e, button, frames: int, check) -> None:
    e.press(0, button)
    for f in range(frames):
        if f == 6:
            e.release(0, button)
        e.run_frames(1)
        check()


def test_command_glyphs_never_change_with_magic_up():
    # Every frame of open, a scroll down the whole list and back, and close:
    # the command window shows on screen at both ends.
    e = _fresh_battle()
    try:
        _to_turn(e, 3)  # Rosa: the longest list
        tap(e, Button.DOWN, gap=20)
        before = _cmd_glyphs(e)
        changed = []

        def check():
            if _cmd_glyphs(e) != before:
                changed.append(e.read(0x7E004A))

        _hold(e, Button.A, 60, check)
        for button in (Button.DOWN, Button.UP):
            for _ in range(LIST_ROWS - 1):
                _hold(e, button, 26, check)
        _hold(e, Button.B, 60, check)
        assert changed == []
    finally:
        e.close()


def _rosa_list_scrolled(*buttons) -> object:
    e = _fresh_battle()
    _to_turn(e, 3)
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)
    e.run_frames(50)
    for button in buttons:
        for _ in range(LIST_ROWS - 1):
            tap(e, button, gap=20)
    e.run_frames(30)
    return e


def test_spell_list_scrolled_to_the_bottom_golden():
    e = _rosa_list_scrolled(Button.DOWN)
    try:
        assert_screenshot_matches_golden(e, GOLDENS / "white_bottom.png", region=BATTLE_MENU_PANEL)
    finally:
        e.close()


def test_spell_list_scrolled_back_to_the_top_golden():
    # Every row on the way down and back took a ring slot over.
    e = _rosa_list_scrolled(Button.DOWN, Button.UP)
    try:
        assert_screenshot_matches_golden(e, GOLDENS / "white_top.png", region=BATTLE_MENU_PANEL)
    finally:
        e.close()
