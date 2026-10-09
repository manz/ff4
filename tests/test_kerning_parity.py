"""The runtime small VWF against the baked names: same tiles, kerning included.

The baked names (utils/bake_names.py) are katsuji's rendering of menu_font.dat, so they are the reference. Each
item name goes through the game's own render_with_config from the field item menu's state; the call ends on a BRK
sentinel that ff4's brk_handler turns into STP, so every name starts from a fresh copy of the state.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss

REPO = Path(__file__).resolve().parents[1]
NAMES = REPO / "build/gen/items_unleashed.dat"
BLOB = REPO / "build/gen/item_names_vwf.dat"
TABLE = REPO / "build/gen/item_names_vwf.tbl"
RECORD = 17  # a symbol byte, then 16 name bytes
TILE_ID = 0x100  # the field list's first slot
BUDGET = 10
CHR_BUFFER = 0x703000


@pytest.fixture(scope="module")
def runtime_tiles():
    if not (NAMES.exists() and BLOB.exists()):
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


def _baked(item: int) -> bytes:
    table = TABLE.read_bytes()
    offset, tiles = int.from_bytes(table[item * 4 : item * 4 + 2], "little"), table[item * 4 + 2]
    return BLOB.read_bytes()[offset : offset + tiles * 16]


def test_runtime_names_match_the_baked_ones(runtime_tiles):
    data = NAMES.read_bytes()
    differ = []
    for item in range(len(data) // RECORD):
        baked = _baked(item)
        if not baked:
            continue
        codes = data[item * RECORD + 1 : (item + 1) * RECORD].rstrip(b"\xff")
        if runtime_tiles(codes)[: len(baked)] != baked:
            differ.append(item)
    assert differ == []
