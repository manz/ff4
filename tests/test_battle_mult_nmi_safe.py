"""The battle multiplies survive an NMI that multiplies too.

The battle NMI draws sprites with vanilla MultHW on the hardware multiplier, and ff4 moved Mult8 ($02:8560) onto
the same hardware. An NMI between the main thread's WRMPYB write and its RDMPYL read handed the main thread its
product: the main menu's text update read its table index as $20 for 0 * 6 and copied a window's text from $0005
through the stack page into the NMI vector (betaplayer halts). Both multiplies now redo the product when the NMI
frame counter moved meanwhile.

The NMI is played by a write callback on WRMPYB: once, it multiplies 4 * 8 on the same hardware and counts a frame.
"""
from __future__ import annotations

import pytest
from _ff4kintsuki import kss_path, load_emu_from_kss

WRMPYA, WRMPYB = 0x004202, 0x004203
FRAME_COUNTER = 0x7E1813  # every battle NMI ends with `inc $1813`
MULT8_FAR = 0x02855C  # JSR Mult8; RTL: $2A = $26 * $28


@pytest.fixture
def emu():
    e = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=2)
    yield e
    e.close()


def _nmi_on_first_multiply(emu) -> list[int]:
    played: list[int] = []

    def nmi(addr, value) -> None:
        if played:
            return
        played.append(value)
        emu.write(WRMPYA, 4)
        emu.write(WRMPYB, 8)  # the NMI's own product: 32
        emu.write(FRAME_COUNTER, (emu.read(FRAME_COUNTER) + 1) & 0xFF)

    emu.add_write_callback(WRMPYB, WRMPYB, nmi)
    return played


def test_mult8_redoes_a_product_an_nmi_took(emu) -> None:
    emu.write(0x26, 0)
    emu.write(0x27, 0)
    emu.write(0x28, 6)
    emu.write(0x29, 0)
    played = _nmi_on_first_multiply(emu)
    emu.call(MULT8_FAR, max_frames=1)
    assert played, "the multiply never wrote WRMPYB"
    assert emu.read(0x2A) | emu.read(0x2B) << 8 == 0


def test_mult_hw_redoes_a_product_an_nmi_took(emu) -> None:
    emu.write(0x1C, 0)
    emu.write(0x1D, 0)
    emu.write(0x1E, 6)
    emu.write(0x1F, 0)
    played = _nmi_on_first_multiply(emu)
    emu.call(emu.lookup_symbol_addr("mult_hw_nmi_safe"), max_frames=1)
    assert played, "the multiply never wrote WRMPYB"
    assert emu.read(0x20) | emu.read(0x21) << 8 == 0
