"""dialog/vwf.s, letter by letter: each letter queues its own tiles for the NMI, and the window's tilemap goes up
once a page, not again with every letter."""
from __future__ import annotations

from _ff4kintsuki import field_special

STUB = 0x001FC0  # free WRAM for the opener below
PAGE = 150  # frames: Porom's first page typed out, waiting for the action button
WINDOW_MAP = 0x2C00  # the BG3 tilemap the window's map goes to, a VRAM word
PUSH = "vblank_upload.push"


def _porom_message_stub() -> bytes:
    """`lda #206 / sta $b2 / jsr GetDlgPtr1L / jsr OpenDlgWindow / jsr CloseDlgWindow / rts`."""
    return bytes([0xA9, 206, 0x85, 0xB2, 0x20, 0x04, 0xB4, 0x20, 0x0D, 0xB3, 0x20, 0xA0, 0xB3, 0x60])


def _vram_targets_of_first_page() -> list[int]:
    emu = field_special(STUB)
    try:
        emu.write_range(0x7E0000 + STUB, _porom_message_stub())
        targets: list[int] = []
        push = emu.lookup_symbol_addr(PUSH)
        emu.add_exec_callback(push, push, lambda _a, _v: targets.append(emu.get_state().y & 0xFFFF))
        emu.run_frames(PAGE)
        return targets
    finally:
        emu.close()


def test_the_window_tilemap_goes_up_once_a_page() -> None:
    assert _vram_targets_of_first_page().count(WINDOW_MAP) == 1
