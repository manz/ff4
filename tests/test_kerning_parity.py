"""The runtime small VWF against katsuji: same tiles, the font's kerning included.

katsuji's rendering of menu_font.dat (`name_tiles` with the font as built) is the reference. The baked blobs are
kerned tighter (every pair on the glyphs, bake_names.auto_kern), so they no longer are. Each item name goes through
the game's own render_with_config from the field item menu's state; the call ends on a BRK sentinel that ff4's
brk_handler turns into STP, so every name starts from a fresh copy of the state.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss
from katsuji import VwfFont

from utils.bake_names import name_tiles, pointed_records

REPO = Path(__file__).resolve().parents[1]
NAMES = REPO / "build/gen/items_unleashed.dat"
NAME_POINTERS = REPO / "build/gen/items_unleashed.ptr"
FONT = REPO / "build/gen/menu_font.dat"
TILE_ID = 0x100  # the field list's first slot
BUDGET = 10
CHR_BUFFER = 0x703000


@pytest.fixture(scope="module")
def runtime_tiles():
    if not (NAMES.exists() and FONT.exists()):
        pytest.skip("assets not built")
    e = load_emu_from_kss(kss_path("ff4-field-inventory-open.kss"), settle_frames=60)
    buf = e.lookup_symbol_addr("vwf_text_buffer")
    cfg = e.lookup_symbol_addr("vwf_cfg")
    render = e.lookup_symbol_addr("items_menu_vwf.render_with_config_trampoline")
    state = e.save_state()

    def render_name(codes: bytes) -> bytes:
        e.load_state(state)
        for i, code in enumerate(codes + b"\x00"):
            e.write(buf + i, code)
        e.write(cfg, TILE_ID & 0xFF)
        e.write(cfg + 1, TILE_ID >> 8)
        e.write(cfg + 2, BUDGET)
        e.write(cfg + 3, 0x00)  # tilemap_base: scratch WRAM row
        e.write(cfg + 4, 0xF8)
        e.write(cfg + 6, 0x01)
        e.call(render, max_frames=5)
        return bytes(e.read(CHR_BUFFER + TILE_ID * 16 + i) for i in range(BUDGET * 16))

    yield render_name
    e.close()


def test_runtime_names_match_katsuji(runtime_tiles):
    font = VwfFont.decode(FONT.read_bytes())
    names = pointed_records(NAMES.read_bytes(), NAME_POINTERS.read_bytes(), skip=1)  # past the symbol byte
    differ = []
    for item, codes in enumerate(names):
        reference = name_tiles(font, codes)
        if not reference:
            continue
        if runtime_tiles(codes)[: len(reference)] != reference:
            differ.append(item)
    assert differ == []
