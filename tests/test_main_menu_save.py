"""The main menu's Sauver where saving isn't allowed ($1A02 = 0): greyed, not gone.

Vanilla greys セーブ by storing the attribute $24 over its cells; Sauver is small-VWF text in tiles $3xx, so a whole
$24 dropped its tile bits and the cells showed the 8x8 font's blank tiles."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap
from kintsuki import Button

GOLDEN = Path(__file__).parent / "goldens" / "main_menu" / "save_greyed.png"
COMMANDS = (176, 0, 256, 152)
SAVE_ALLOWED = 0x7E1A02


def test_sauver_is_greyed() -> None:
    emu = load_emu_from_kss(kss_path("ff4-key-inventory.kss"), settle_frames=10)
    try:
        assert emu.read(SAVE_ALLOWED) == 0
        tap(emu, Button.X, gap=60)
        assert_screenshot_matches_golden(emu, GOLDEN, region=COMMANDS)
    finally:
        emu.close()
