"""Fat Chocobo's deposit list (ingame/fat_chocobo.s): his list frame as wide as the inventory window it frames."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import FULL_PICTURE, assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "fat_chocobo"


def test_the_deposit_list_golden() -> None:
    emu = load_emu_from_kss(kss_path("ff4-fat-chocobo.kss"), settle_frames=30)
    try:
        tap(emu, Button.A, gap=60)  # talk to him
        tap(emu, Button.A, gap=60)  # Déposer
        assert_screenshot_matches_golden(emu, GOLDENS / "deposit.png", region=FULL_PICTURE)
    finally:
        emu.close()
