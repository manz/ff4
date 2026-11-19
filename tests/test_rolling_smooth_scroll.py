"""Rolling lists slide by the pixel (lib/rolling_inventory_engine.s, rolling_engine_hdma_rows; the battle item list:
battle/inventory_rolling.s, update_list_scroll_hdma_wrapped): mid-scroll the live
HDMA table's first and last row bands are partial, every frame covering the list's full height. Before, the bands
stayed whole rows and every scroll jumped one."""
from __future__ import annotations

from _ff4kintsuki import (
    CECIL_SLOT,
    choose_command,
    kss_path,
    load_emu_from_kss,
    tap,
    wait_for_turn,
    walk_into_battle,
)
from kintsuki import Button, Emu

FIELD_TABLE = 0x7E9800  # header band, 10 row bands (11 mid-scroll), footer band
EQUIP_TABLE = 0x7E9980  # the Fat Chocobo's: header band, 7 row bands (8 mid-scroll), footer band
BATTLE_VOFS = 0x7E7F74  # the battle item list's BG3 V scroll, one word every 4 bytes, a scanline each
BATTLE_LINES = 60  # 5 rows of 12 lines
ITEM = 0x01  # the Item command


def _bands(emu: Emu, table: int) -> list[int]:
    heights, at = [], table
    while emu.read(at):
        heights.append(emu.read(at))
        at += 3
    return heights


def _row_bands_while_scrolling(emu: Emu, table: int, frames: int) -> list[tuple[int, ...]]:
    seen = []
    emu.press(0, Button.DOWN)
    for _ in range(frames):
        emu.run_frames(1)
        seen.append(tuple(_bands(emu, table)[1:-1]))
    emu.release(0, Button.DOWN)
    return seen


def _battle_runs(emu: Emu) -> list[int]:
    runs: list[list[int]] = []
    for line in range(BATTLE_LINES):
        value = emu.read16(BATTLE_VOFS + 4 * line)
        if runs and runs[-1][0] == value:
            runs[-1][1] += 1
        else:
            runs.append([value, 1])
    return [count for _, count in runs]


def _battle_list_at_the_last_row() -> Emu:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    walk_into_battle(emu)
    wait_for_turn(emu, CECIL_SLOT)
    choose_command(emu, ITEM)
    emu.run_frames(40)
    for _ in range(8):
        tap(emu, Button.DOWN, gap=30)
    emu.run_frames(30)
    return emu


def _field_at_the_last_row() -> Emu:
    emu = load_emu_from_kss(kss_path("ff4-before-inventory-opens.kss"), settle_frames=60)
    tap(emu, Button.A)
    emu.run_frames(60)
    for _ in range(9):
        tap(emu, Button.DOWN, gap=20)
    emu.run_frames(30)
    return emu


def _fat_chocobo_at_the_last_row() -> Emu:
    emu = load_emu_from_kss(kss_path("ff4-fat-chocobo.kss"), settle_frames=30)
    tap(emu, Button.A, gap=60)  # talk to him
    tap(emu, Button.A, gap=60)  # Déposer
    for _ in range(6):
        tap(emu, Button.DOWN, gap=30)
    emu.run_frames(20)
    return emu


def test_the_field_list_slides_through_rows() -> None:
    emu = _field_at_the_last_row()
    try:
        seen = _row_bands_while_scrolling(emu, FIELD_TABLE, 10)
    finally:
        emu.close()
    assert ({sum(bands) for bands in seen}, sorted({bands[0] for bands in seen})) == ({160}, [4, 8, 12, 16])


def test_the_fat_chocobo_list_slides_through_rows() -> None:
    emu = _fat_chocobo_at_the_last_row()
    try:
        seen = _row_bands_while_scrolling(emu, EQUIP_TABLE, 12)
    finally:
        emu.close()
    assert ({sum(bands) for bands in seen}, sorted({bands[0] for bands in seen})) == (
        {112}, [2, 4, 6, 8, 10, 12, 14, 16])


def test_the_battle_item_list_slides_through_rows() -> None:
    emu = _battle_list_at_the_last_row()
    try:
        emu.press(0, Button.DOWN)
        seen = []
        for _ in range(10):
            emu.run_frames(1)
            seen.append(_battle_runs(emu)[0])
        emu.release(0, Button.DOWN)
    finally:
        emu.close()
    assert len({lines for lines in seen if lines < 12}) >= 3  # vanilla's slide steps two or three a frame
