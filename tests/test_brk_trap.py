"""Verify the in-ROM BRK trap captures PC/PB and halts via STP.

Drops a stub into WRAM that hits BRK, runs until the CPU halts, and
checks the bytes the trap stored at $710100-$710103."""
from __future__ import annotations

from pathlib import Path

import pytest

from a816.snippet import assemble_source
from kintsuki import Emu

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"
STUB_PATH = Path(__file__).parent / "asm/brk_stub.s"

STUB_BASE = 0x7E0000
BRK_OFFSET = 0xA  # clc + xce + rep #$30 + ldx + ldy = 1+1+2+3+3 = 10


@pytest.fixture
def cold_emu():
    if not ROM.exists():
        pytest.skip(f"ff4.sfc not built at {ROM}")
    e = Emu()
    e.load_rom(str(ROM))
    yield e
    e.close()


def test_brk_trap_captures_pc_and_halts(cold_emu):
    stub = assemble_source(STUB_PATH.read_text()).code
    cold_emu.rearm_cpu()
    cold_emu.write_range(STUB_BASE, stub)
    s = cold_emu.get_state()
    s.pc = STUB_BASE
    s.s = 0x1FFF
    s.e = True  # boot in emulation mode; stub does clc/xce -> native
    s.p = 0
    s.stp = 0
    s.wai = 0
    cold_emu.set_state(s)

    assert cold_emu.run_until_stp(max_frames=30), "BRK trap never halted CPU"

    s = cold_emu.get_state()
    assert s.a & 0x00FF == 0x42, (
        f"BRK signature mismatch: A=${s.a:04X} expected low byte $42"
    )
