"""Battle item names come from the full list (items_unleashed): the name window over the battle when an item is used
($02:CB6F) shows "Plume de phénix", not the 11-character squeeze the retired items.xml held."""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import CMD_ITEM, assert_screenshot_matches_golden, choose_command, fresh_late_battle, tap
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "battle_item_names"
CURSOR_TYPE = 0x7E1823  # 5 the inventory list
PHOENIX_DOWN_ROW = 4  # in the late save's battle inventory
ITEM_NAME_WINDOW = 0x02CB6F  # vanilla's item-name branch of the attack-name window
DRAW_NAME_WINDOW = 0x02BCA2  # picks the left ($02:9304) or right ($02:9360) message window from $6CC0
LEFT_SIDE = 0x7E6CC0  # non-zero on surprise and back attacks
NAME_WINDOW = (0, 0, 256, 40)


@pytest.mark.parametrize("golden", ["phoenix_down.png", "phoenix_down_left.png"])
def test_the_used_item_s_name_window_golden(golden: str) -> None:
    """The right window and the left one (a surprise attack's) are the same centred box."""
    emu = fresh_late_battle()
    try:
        choose_command(emu, CMD_ITEM)
        for _ in range(60):
            if emu.read(CURSOR_TYPE) == 5:
                break
            emu.run_frames(2)
        emu.run_frames(10)
        for _ in range(PHOENIX_DOWN_ROW):
            tap(emu, Button.DOWN, gap=16)
        for _ in range(3):  # pick it, use it, on the first target
            tap(emu, Button.A, gap=30)
        shown: list[int] = []
        emu.add_exec_callback(ITEM_NAME_WINDOW, ITEM_NAME_WINDOW, lambda *_: shown.append(1))
        if golden.endswith("_left.png"):
            emu.add_exec_callback(DRAW_NAME_WINDOW, DRAW_NAME_WINDOW, lambda *_: emu.write(LEFT_SIDE, 1))
        for _ in range(600):
            if shown:
                break
            emu.run_frames(1)
        assert shown
        emu.run_frames(20)
        assert_screenshot_matches_golden(emu, GOLDENS / golden, region=NAME_WINDOW)
    finally:
        emu.close()
