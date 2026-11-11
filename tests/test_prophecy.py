"""dialog/prophecy.s: Mysidia's prophecy (event special $32), where the dialogue VWF used to wait forever for a vblank
with NMI off: a black screen after « Une légende ? ». Told now as vanilla did: on the window's blue, a line at a
time rising to yellow, each page centred."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import assert_screenshot_matches_golden, field_special

GOLDENS = Path(__file__).parent / "goldens" / "prophecy"
PROPHECY = 0x00C772  # Special_32
ENDING = 0x00C871  # its ending, past the fade out: BG3 scroll, palettes, NMI
TM = 0x00212C
FIELD_TM = 0x17  # InitHWRegs' main screen, which the field keeps
FIRST_PAGE = 1000  # frames to the first page's 3 lines all up, held
SECOND_LINE_RISING = 560  # frames: the first line up, the second on its way, the last two still hidden
ENOUGH = 4000  # frames: its 3 pages end in about 3500
TEXT_COLOURS = [0x7E0CDB + line * 8 + 6 for line in range(4)]  # colour 3 of each line's palette
BLUE = 0x4000  # vanilla's window blue: a hidden line's text
YELLOW = 0x43FF  # $4000 | 31 | 31 << 5: a line's text all the way up


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




def test_the_prophecy_shows_its_lines_one_at_a_time() -> None:
    emu = field_special(PROPHECY)
    try:
        emu.run_frames(SECOND_LINE_RISING)
        first, second, third, fourth = (emu.read16(colour) for colour in TEXT_COLOURS)
        assert (first, third, fourth) == (YELLOW, BLUE, BLUE)
        assert BLUE < second < YELLOW
    finally:
        emu.close()
