"""dialog/prologue.s and the VWF's SCROLL_LINES: the prologue (event special $09) scrolls up line by line, as vanilla's
auto-scrolling dialogue did, instead of typing its pages."""
from __future__ import annotations

from collections import Counter
from itertools import pairwise
from pathlib import Path

from _ff4kintsuki import SPECIAL_RETURN, assert_screenshot_matches_golden, field_special

GOLDENS = Path(__file__).parent / "goldens" / "prologue"
PROLOGUE = 0x00D3F4  # Special_09
BAND_SCROLL_DP = 0x0006BB  # $bb: BG3's scroll in the dialogue band, which the window IRQ sets
PIXEL_FRAMES = 8  # vanilla's auto-scroll: a pixel every 8 frames
SCROLLING = 1200  # frames: several lines in
FIRST_PAGE = 704  # frames to the first page's 4 lines, its last one blank, scrolled into the band
ENOUGH = 6000  # frames: it returns after about 5640, vanilla after about 5900
FONT = 0x0AF000  # the 8x8 font vwfinit copies to BG3
BG3_CHR = 0x6000
BORROWED = slice(0x80 * 16, 0x80 * 16 + 0x340)  # the font tiles the fifth line set borrows, in bytes


def test_the_prologue_scrolls_a_pixel_every_8_frames() -> None:
    emu = field_special(PROLOGUE)
    try:
        steps: list[int] = []
        emu.add_write_callback(BAND_SCROLL_DP, BAND_SCROLL_DP, lambda _a, _v: steps.append(emu.frame_count))
        emu.run_frames(SCROLLING)
        gaps = Counter(later - earlier for earlier, later in pairwise(steps))
        assert gaps.most_common(1)[0][0] == PIXEL_FRAMES
    finally:
        emu.close()


def test_the_prologue_first_page_golden() -> None:
    emu = field_special(PROLOGUE)
    try:
        emu.run_frames(FIRST_PAGE)
        assert_screenshot_matches_golden(emu, GOLDENS / "first_page.png")
    finally:
        emu.close()


def test_the_prologue_returns_with_the_font_it_borrowed_back() -> None:
    emu = field_special(PROLOGUE)
    try:
        returned: list[int] = []
        emu.add_exec_callback(SPECIAL_RETURN, SPECIAL_RETURN, lambda _pc, _v: returned.append(emu.frame_count))
        emu.run_frames(ENOUGH)
        assert returned
        font = bytes(emu.read_range(FONT + BORROWED.start, BORROWED.stop - BORROWED.start))
        vram = bytes(emu.vram_read_range(BG3_CHR * 2 + BORROWED.start, BORROWED.stop - BORROWED.start))
        assert vram == font
    finally:
        emu.close()
