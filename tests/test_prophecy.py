"""dialog/prophecy.s: Mysidia's prophecy (event special $32) told in whole pages, where the dialogue VWF used to
wait forever for a vblank with NMI off: a black screen after « Une légende ? »."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import assert_screenshot_matches_golden, field_special

GOLDENS = Path(__file__).parent / "goldens" / "prophecy"
PROPHECY = 0x00C772  # Special_32
ENDING = 0x00C871  # its ending, past the fade out: BG3 scroll, palettes, NMI
TM = 0x00212C
FIELD_TM = 0x17  # InitHWRegs' main screen, which the field keeps
FIRST_PAGE = 180  # frames to the first page, faded in and held
ENOUGH = 1500  # frames: both pages fade in, hold and fade out in about 800


def test_the_prophecy_reaches_its_ending_and_gives_the_field_its_screens_back() -> None:
    emu = field_special(PROPHECY)
    try:
        ended: list[int] = []
        main_screens: list[int] = []
        emu.add_exec_callback(ENDING, ENDING, lambda _pc, _v: ended.append(emu.frame_count))
        emu.add_write_callback(TM, TM, lambda _address, value: main_screens.append(value))
        emu.run_frames(ENOUGH)
        assert ended
        assert main_screens[-1] == FIELD_TM
    finally:
        emu.close()


def test_the_prophecy_first_page_golden() -> None:
    emu = field_special(PROPHECY)
    try:
        emu.run_frames(FIRST_PAGE)
        assert_screenshot_matches_golden(emu, GOLDENS / "first_page.png")
    finally:
        emu.close()


