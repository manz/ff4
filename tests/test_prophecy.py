"""dialog/prophecy.s: Mysidia's prophecy (event special $32) told like the prologue, where the dialogue VWF used to
wait forever for a vblank with NMI off: a black screen after « Une légende ? ». The prologue (special $09) shares
the window-less path."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss

GOLDENS = Path(__file__).parent / "goldens" / "prophecy"
FIELD_DP = 0x7E0600
PROPHECY = 0x00C772  # Special_32
ENDING = 0x00C871  # its ending, past the fade out: BG3 scroll, palettes, NMI
TM = 0x00212C
FIELD_TM = 0x17  # InitHWRegs' main screen, which the field keeps
SENTINEL = 0xFFFC  # where the pushed return lands
FIRST_PAGE = 180  # frames to the first page, faded in and held
ENOUGH = 1500  # frames: both pages fade in, hold and fade out in about 800


def _special(entry: int = PROPHECY):
    """A field savestate jumped into the special at `entry`, its return landing on SENTINEL."""
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=60)
    emu.rearm_cpu()
    state = emu.get_state()
    state.pc, state.p, state.e, state.d, state.b, state.x, state.a = entry, 0x20, False, FIELD_DP & 0xFFFF, 0, 0, 0
    emu.set_state(state)
    emu.push_word(SENTINEL - 1)
    return emu


def test_the_prophecy_reaches_its_ending_and_gives_the_field_its_screens_back() -> None:
    emu = _special()
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
    emu = _special()
    try:
        emu.run_frames(FIRST_PAGE)
        assert_screenshot_matches_golden(emu, GOLDENS / "first_page.png")
    finally:
        emu.close()


PROLOGUE = 0x00D3F4  # Special_09: the prologue, its text auto-scrolled letter by letter
PROLOGUE_FRAMES = 3600  # it returns after about 3100


def test_the_prologue_still_types_to_its_end() -> None:
    emu = _special(PROLOGUE)
    try:
        returned: list[int] = []
        emu.add_exec_callback(SENTINEL, SENTINEL, lambda _pc, _v: returned.append(emu.frame_count))
        emu.run_frames(300)
        assert_screenshot_matches_golden(emu, GOLDENS / "prologue_first_lines.png")
        emu.run_frames(PROLOGUE_FRAMES - 300)
        assert returned
    finally:
        emu.close()
