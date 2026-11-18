"""Rolling lists slide by the pixel (lib/rolling_inventory_engine.s, rolling_engine_hdma_rows): mid-scroll the live
HDMA table's first and last row bands are partial, every frame covering the list's full height. Before, the bands
stayed whole rows and every scroll jumped one."""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss, tap
from kintsuki import Button, Emu

FIELD_TABLE = 0x7E9800  # header band, 10 row bands (11 mid-scroll), footer band
EQUIP_TABLE = 0x7E9980  # the Fat Chocobo's: header band, 7 row bands (8 mid-scroll), footer band


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
