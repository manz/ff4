"""An item name printed inside a text: the chest dialog's item code ($07) and battle's TextVar_03 (« Vol : … ! »); a
spell name in battle's TextVar_04. Both battle names draw after the text before them.

Both read `items_unleashed`, where $FF is a space and $00 ends a name, and both stopped at the first $FF: a chest of
« Bouclier de lumière » read « Vous avez trouvé Bouclier! ». The dialog also drew the name's menu codes as dialog
codes (é is $A0 in the menus, $76 in the dialog), and the name, in the book font, wraps a line of its own.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest
from _ff4kintsuki import (
    ROM,
    assert_screenshot_matches_golden,
    fresh_late_battle,
    kss_path,
    load_emu_from_kss,
)
from test_battle_message_text_pointer import _use_monsters

from utils.dialog_layout import LINE_WIDTHS, dialog_layout
from utils.name_codes import drawable_in_dialog

REPO = Path(__file__).resolve().parents[1]
GEN = REPO / "build/gen"
GOLDENS = Path(__file__).parent / "goldens" / "item_names_in_text"
SHIELD_OF_LIGHT = 0x64  # « Bouclier de lumière »: three words, an è
BOOK_FONT = 2

INVENTORY = range(0x7E1440, 0x7E14A0)  # emptied: a full one shows « L'inventaire est plein. »
FIELD_DP = 0x7E0600
TREASURE = 0x00999D  # the field's item-chest branch: $08 the item, $09 bit 7 an item, $B2 the message
FOUND_ITEM = 1  # bank1-1#1, « Vous avez trouvé[br][item]! »
DIALOG_WINDOW = (0, 0, 256, 72)

STEAL_ITEM = 0x7E359A  # TextVar_03's item id
TEXT_VAR_03 = 0x02A58F
SPELL = 0x7E359A  # TextVar_04's spell id, below $48
TEXT_VAR_04 = 0x02A53B
CURE_2 = 0x0F  # « Soin 2 »
POTION = 0xCE
CELL = 2 * 6  # DrawText's cell offset in Y (2 bytes a cell): the text before the name, « Vol : »
DISPLAY_CHAR = 0x02A49B  # draw_letter's put, where TextVar_04 draws the spell's first letter
MESSAGE_IDS = 0x7E0045  # btlgfx's pointer to the next battle text id (ShowMsg reads lda ($45) at $02CBFB)
NEXT_MESSAGE = 0x02CBFB
STOLE = 29  # « Vol : [0x6]3 ! »
MESSAGE_WINDOW = (0, 0, 256, 24)
SHOWN = 30  # frames from the swapped id to the message on screen
SENTINEL = 0xFFFC  # where the pushed return lands


def _item_name(item: int) -> bytes:
    """`item`'s name in `items_unleashed`, without its symbol byte or its $00."""
    data = (GEN / "items_unleashed.dat").read_bytes()
    pointers = (GEN / "items_unleashed.ptr").read_bytes()
    start = int.from_bytes(pointers[item * 2 : item * 2 + 2], "little") + 1
    return data[start : data.index(0, start)]


def _spell_name(spell: int) -> bytes:
    """`spell`'s name in `magic_names` after its first letter (TextVar_04 draws that one apart), without its $00."""
    data = (GEN / "magic.dat").read_bytes()
    pointers = (GEN / "magic.ptr").read_bytes()
    start = int.from_bytes(pointers[spell * 2 : spell * 2 + 2], "little") + 1
    return data[start : data.index(0, start)]


def _all_names() -> list[bytes]:
    data = (GEN / "items_unleashed.dat").read_bytes()
    return [name[1:] for name in data.split(b"\x00") if len(name) > 1]


def _enter(emu, pc: int, *, dp: int = 0, db: int = 0, y: int = 0) -> None:
    """Jump `emu` to the `rts` routine at `pc` as the field and battle code run (8-bit A, 16-bit X/Y), its return
    landing on SENTINEL in the routine's bank."""
    emu.rearm_cpu()
    state = emu.get_state()
    state.pc, state.p, state.e, state.d, state.b, state.y = pc, 0x20, False, dp, db, y
    emu.set_state(state)
    emu.push_word(SENTINEL - 1)


def test_every_item_name_draws_in_the_dialog() -> None:
    if not GEN.exists():
        pytest.skip("not built")
    codes = bytes(sorted({code for name in _all_names() for code in name}))
    assert drawable_in_dialog(REPO / "text/ff4_menus.tbl", REPO / "text/ff4fr.tbl", codes) == []


def test_every_item_name_fits_its_own_dialog_line() -> None:
    if not GEN.exists():
        pytest.skip("not built")
    layout = dialog_layout()
    text = (REPO / "text/fr/items_unleashed.xml").read_text(encoding="utf-8")
    names = re.findall(r"<sn:fixed>(?:\[0x[0-9a-f]+\])?(.*?)</sn:fixed>", text)
    widest = max(layout.measure(f"{name}!", BOOK_FONT) for name in names)
    assert widest <= min(LINE_WIDTHS)


def test_a_chest_shows_the_whole_item_name() -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=60)
    try:
        for address in INVENTORY:
            emu.write(address, 0)
        emu.write(FIELD_DP + 0x08, SHIELD_OF_LIGHT)
        emu.write(FIELD_DP + 0x09, 0x80)
        emu.write(FIELD_DP + 0xB2, FOUND_ITEM)
        _enter(emu, TREASURE, dp=FIELD_DP & 0xFFFF)
        emu.run_frames(90)
        assert_screenshot_matches_golden(emu, GOLDENS / "shield_of_light_chest.png", region=DIALOG_WINDOW)
    finally:
        emu.close()


def test_a_battle_message_spells_the_whole_item_name() -> None:
    if not ROM.exists():
        pytest.skip("ROM not built")
    emu = fresh_late_battle()
    try:
        letters = bytearray()
        draw_letter = emu.lookup_symbol_addr("draw_letter")
        emu.add_exec_callback(draw_letter, draw_letter, lambda *_: letters.append(emu.get_state().a & 0xFF))
        emu.write(STEAL_ITEM, SHIELD_OF_LIGHT)
        _enter(emu, TEXT_VAR_03, db=0x7E)
        assert emu.run_until((TEXT_VAR_03 & 0xFF0000) | SENTINEL, max_frames=5)
        assert bytes(letters) == _item_name(SHIELD_OF_LIGHT)
    finally:
        emu.close()


def test_a_battle_message_spells_the_whole_spell_name() -> None:
    """TextVar_04 stopped at « Soin 2 »'s space as TextVar_03 did at an item's."""
    if not ROM.exists():
        pytest.skip("ROM not built")
    emu = fresh_late_battle()
    try:
        letters = bytearray()
        draw_letter = emu.lookup_symbol_addr("draw_letter")
        emu.add_exec_callback(draw_letter, draw_letter, lambda *_: letters.append(emu.get_state().a & 0xFF))
        emu.write(SPELL, CURE_2)
        _enter(emu, TEXT_VAR_04, db=0x7E)
        assert emu.run_until((TEXT_VAR_04 & 0xFF0000) | SENTINEL, max_frames=5)
        assert bytes(letters) == _spell_name(CURE_2)
    finally:
        emu.close()


def _first_cell(var: int, arg: int) -> int:
    """The cell offset `var`'s first letter draws at, DrawText's Y being CELL when it reaches the variable."""
    emu = fresh_late_battle()
    try:
        cells = []
        emu.add_exec_callback(DISPLAY_CHAR, DISPLAY_CHAR, lambda *_: cells.append(emu.get_state().y & 0xFFFF))
        emu.write(STEAL_ITEM, arg)
        _enter(emu, var, db=0x7E, y=CELL)
        assert emu.run_until((var & 0xFF0000) | SENTINEL, max_frames=5)
        return cells[0]
    finally:
        emu.close()


@pytest.mark.parametrize(("var", "arg"), [(TEXT_VAR_03, POTION), (TEXT_VAR_04, CURE_2)], ids=["item", "spell"])
def test_a_name_draws_after_the_text_before_it(var: int, arg: int) -> None:
    """Vanilla's TextVar_03 and _04 restart DrawText's cell offset (ldy #0): its names always open a line. « Vol :
    [0x6]3 ! » drew the name over « Vol »."""
    if not ROM.exists():
        pytest.skip("ROM not built")
    assert _first_cell(var, arg) == CELL


def test_the_steal_message_keeps_its_leading_text() -> None:
    """Battle text 29 on screen, through the Monsters item's message (its id swapped for 29): « Vol : Potion ! »."""
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    try:
        state = {"at": None, "snapshot": None}

        def swap(*_) -> None:
            if state["at"] is None:
                pointer = emu.read(MESSAGE_IDS) | emu.read(MESSAGE_IDS + 1) << 8
                emu.write(0x7E0000 | pointer, STOLE)
                emu.write(STEAL_ITEM, POTION)
                state["at"] = emu.frame_count

        emu.add_exec_callback(NEXT_MESSAGE, NEXT_MESSAGE, swap)
        run_frames = emu.run_frames

        def frame_by_frame(frames: int) -> None:
            for _ in range(frames):
                run_frames(1)
                if state["snapshot"] is None and state["at"] is not None and emu.frame_count >= state["at"] + SHOWN:
                    state["snapshot"] = emu.save_state()

        emu.run_frames = frame_by_frame
        try:
            _use_monsters(emu)
            frame_by_frame(SHOWN)
        finally:
            emu.run_frames = run_frames
        assert state["snapshot"] is not None, "no battle text shown"
        emu.load_state(state["snapshot"])
        emu.run_frames(1)
        assert_screenshot_matches_golden(emu, GOLDENS / "stole_potion.png", region=MESSAGE_WINDOW)
    finally:
        emu.close()
