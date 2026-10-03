"""Equip screen inventory list: a rolling list over the whole inventory.

Once a slot is picked, the list under the equip screen must walk the
inventory in order, one item per row, and render the rows a scroll
reveals - vanilla drew it once, two items per row, which the
single-column item rows turned into every second item and a single
page.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button
from PIL import Image

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")
GOLDENS = Path(__file__).parent / "goldens" / "equip_inventory"
INVENTORY = 0x7E1440
INVENTORY_SLOTS = 48
VISIBLE_ROWS = 6
SCROLL_POS = 0x7E1B2A
CURSOR_ROW = 0x7E1B28
PICTURE = (13, 9, 13 + 256, 9 + 224)
LIST_BAND = (110, 224)
DRAW_ITEM_NAME = 0x019060  # every rendered row's name goes through here
EQUIP_ITEM_PICK = 0x01BF61  # `lda $1440,x` on A, X = picked slot * 2


def _open_list():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=60)  # Equiper
    tap(e, Button.A, gap=120)  # first character
    return e


@pytest.fixture
def list_emu():
    e = _open_list()
    yield e
    e.close()


def _inventory_ids(emu) -> list[int]:
    return [emu.read(INVENTORY + 2 * i) for i in range(INVENTORY_SLOTS)]


def test_every_item_renders_while_scrolling_down(list_emu):
    rendered: list[int] = []
    list_emu.add_exec_callback(
        DRAW_ITEM_NAME, DRAW_ITEM_NAME, lambda _pc, _op: rendered.append(list_emu.get_state().a & 0xFF)
    )
    tap(list_emu, Button.A, gap=90)  # first slot -> list
    for _ in range(INVENTORY_SLOTS):
        tap(list_emu, Button.DOWN, gap=16)
    expected = {i for i in _inventory_ids(list_emu) if i}
    assert expected <= set(rendered)


def test_a_picks_the_item_under_the_cursor(list_emu):
    picked: list[int] = []
    list_emu.add_exec_callback(
        EQUIP_ITEM_PICK, EQUIP_ITEM_PICK, lambda _pc, _op: picked.append(list_emu.get_state().x & 0xFFFF)
    )
    tap(list_emu, Button.A, gap=90)
    for _ in range(VISIBLE_ROWS + 9):  # five row moves, then ten scrolls
        tap(list_emu, Button.DOWN, gap=16)
    slot = list_emu.read(SCROLL_POS) + list_emu.read(CURSOR_ROW)
    tap(list_emu, Button.A, gap=30)
    assert picked and picked[0] == slot * 2


def test_hand_sits_on_its_row(list_emu, tmp_path):
    tap(list_emu, Button.A, gap=90)
    for _ in range(2):
        tap(list_emu, Button.DOWN, gap=16)
    list_emu.run_frames(30)
    list_emu.screenshot(str(tmp_path / "s.png"))
    im = Image.open(tmp_path / "s.png").convert("RGB").crop(PICTURE)
    lit = [y for y in range(*LIST_BAND) if any(sum(im.getpixel((x, y))) > 300 for x in range(24, 120))]
    tops = [y for i, y in enumerate(lit) if i == 0 or y - lit[i - 1] > 2]
    oam = bytes(list_emu.oam_read_range(0, 512))
    hand = next(oam[4 * i + 1] for i in range(128) if LIST_BAND[0] <= oam[4 * i + 1] < LIST_BAND[1])
    assert hand == tops[list_emu.read(CURSOR_ROW)] - 1


# Vanilla's first row: top border on screen line 104 (BG4VOFS $FF98), the
# slot one tile row below it, the name on the slot's bottom tile row.
VANILLA_FIRST_NAME_Y = 120
BELOW_LAST_ROW = (VANILLA_FIRST_NAME_Y - 8 + VISIBLE_ROWS * 16, 224)


def _name_tops(emu, path, band=LIST_BAND) -> list[int]:
    emu.screenshot(str(path))
    im = Image.open(path).convert("RGB").crop(PICTURE)
    lit = [y for y in range(*band) if any(sum(im.getpixel((x, y))) > 300 for x in range(24, 120))]
    return [y for i, y in enumerate(lit) if i == 0 or y - lit[i - 1] > 2]


def test_rows_sit_where_vanilla_draws_them(list_emu, tmp_path):
    tap(list_emu, Button.A, gap=90)
    list_emu.run_frames(30)
    assert _name_tops(list_emu, tmp_path / "s.png")[0] == VANILLA_FIRST_NAME_Y


def test_pre_render_row_stays_hidden(list_emu, tmp_path):
    tap(list_emu, Button.A, gap=90)
    for _ in range(VISIBLE_ROWS + 3):
        tap(list_emu, Button.DOWN, gap=16)
    list_emu.run_frames(30)
    assert _name_tops(list_emu, tmp_path / "s.png", BELOW_LAST_ROW) == []


def test_list_never_halts(list_emu):
    tap(list_emu, Button.A, gap=90)
    for button in [Button.DOWN] * INVENTORY_SLOTS + [Button.UP] * INVENTORY_SLOTS + [Button.B]:
        tap(list_emu, button, gap=12)
    assert list_emu.get_state().stp == 0


@pytest.mark.parametrize("downs, name", [(0, "open"), (5, "last_row"), (14, "scrolled")])
def test_list_golden(list_emu, downs, name):
    tap(list_emu, Button.A, gap=90)
    for _ in range(downs):
        tap(list_emu, Button.DOWN, gap=16)
    list_emu.run_frames(30)
    assert_screenshot_matches_golden(list_emu, GOLDENS / f"{name}.png")
