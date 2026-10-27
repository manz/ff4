"""The sell list's hand points at the item's name: vanilla's row * 16 + 0x58 sat 8 px above the names (b0 beta)."""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss
from test_showcase import _play

NAMES_TOP = 0x60  # the first name's row on screen, as on the buy list (hand Y = name Y)
ROW = 16


def _hand_y(emu) -> int:
    """The list hand's Y: the sprite at the list's X, the quantity hand being the other one."""
    oam = emu.oam_read_range(0, 512).tobytes()
    return next(oam[i * 4 + 1] for i in range(128) if oam[i * 4] == 8 and 0 < oam[i * 4 + 1] < 0xE0)


def test_the_hand_sits_on_each_row() -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        _play(emu, ["RIGHT", "A"], 40)  # Vendre, then the quantity
        _play(emu, ["A"], 40)
        ys = [_hand_y(emu)]
        _play(emu, ["DOWN"], 40)
        ys.append(_hand_y(emu))
    finally:
        emu.close()
    assert ys == [NAMES_TOP, NAMES_TOP + ROW]
