"""Verify the in-ROM BRK trap captures PC/PB and halts via STP.

Drops a stub into WRAM that hits BRK, runs until the CPU halts, and
checks the bytes the trap stored at $7E0005-$7E0008."""
from __future__ import annotations

from pathlib import Path

import pytest

from a816.program import Program
from a816.writers import Writer
from kintsuki import Emu, SymbolTable

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"
SYM = REPO / "build/ff4.sym"
STUB_PATH = Path(__file__).parent / "asm/brk_stub.s"

STUB_BASE = 0x7E0000
BRK_OFFSET = 0xA  # clc + xce + rep #$30 + ldx + ldy = 1+1+2+3+3 = 10


@pytest.fixture(scope="session")
def syms() -> SymbolTable:
    if not SYM.exists():
        pytest.skip(f"ff4.sym not built at {SYM}")
    return SymbolTable(SYM)


@pytest.fixture
def cold_emu():
    if not ROM.exists():
        pytest.skip(f"ff4.sfc not built at {ROM}")
    e = Emu()
    e.load_rom(str(ROM))
    yield e
    e.close()


class _StubWriter(Writer):
    def __init__(self) -> None:
        self.blocks: list[tuple[int, bytes]] = []

    def begin(self) -> None: ...
    def write_block_header(self, block: bytes, block_address: int) -> None: ...

    def write_block(self, block: bytes, block_address: int) -> None:
        self.blocks.append((block_address, block))

    def end(self) -> None: ...


def _assemble(src: str) -> bytes:
    program = Program()
    w = _StubWriter()
    program.assemble_string_with_emitter(src, "<test>", w)
    return b"".join(b for _, b in w.blocks)


def test_brk_trap_captures_pc_and_halts(cold_emu, syms):
    stub = _assemble(STUB_PATH.read_text())
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

    pc_lo = cold_emu.read(0x7E0006)
    pc_hi = cold_emu.read(0x7E0007)
    pb = cold_emu.read(0x7E0008)
    captured = (pb << 16) | (pc_hi << 8) | pc_lo
    expected = STUB_BASE + BRK_OFFSET + 2  # CPU pushes BRK+2
    assert captured == expected, (
        f"BRK PC mismatch: captured ${captured:06X} expected ${expected:06X}"
    )
