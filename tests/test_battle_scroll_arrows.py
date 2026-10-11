"""The battle list's scroll arrows stay off screen while no list shows them.

ff4 moved the arrows (sprites 6-9) to x = $F6 for the single-column item list. Vanilla hides them with their x bit 8,
which parked the 16x16 up arrows at -10: their right six columns showed left of the monster window. The hide path
now also drops them below the screen.
"""
from __future__ import annotations

from _ff4kintsuki import choose_command, kss_path, load_emu_from_kss

UP_ARROWS = (6, 7)  # 16x16; the down arrows (8-9) are 8x8 and vanish at -10 on their own
ITEM = 0x01
CURSOR_TYPE = 0x7E1823  # 5: inventory
SCREEN_W, SCREEN_H, SIZE = 256, 224, 16


def _sprite(emu, i: int) -> tuple[int, int]:
    oam = bytes(emu.oam_read_range(0, 544))
    x, y, high = oam[i * 4], oam[i * 4 + 1], oam[512 + i // 4] >> ((i % 4) * 2)
    return (x - 256 if high & 1 else x), y


def _on_screen(x: int, y: int) -> bool:
    return -SIZE < x < SCREEN_W and y < SCREEN_H


def test_hidden_up_arrows_stay_off_screen() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    try:
        assert [i for i in UP_ARROWS if _on_screen(*_sprite(emu, i))] == []
    finally:
        emu.close()


def test_the_item_list_shows_its_arrows_at_the_right_edge() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    try:
        choose_command(emu, ITEM)
        for _ in range(30):
            if emu.read(CURSOR_TYPE) == 5:
                break
            emu.run_frames(2)
        emu.run_frames(10)
        assert [_sprite(emu, i)[0] for i in UP_ARROWS] == [0xF6, 0xF6]
    finally:
        emu.close()
