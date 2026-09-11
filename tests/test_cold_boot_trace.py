"""Cold-boot execution trace from the reset vector.

Loads the patched ROM, resets, and traces every instruction over the
first few frames so a black-screen / instant-BRK regression shows up as
a concrete PC + source line instead of a blank screen.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Emu

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"
ADBG = REPO / "build/ff4.ips.adbg"


def _resolve(e: Emu, full: int) -> str:
    lbl = e.lookup_label_containing(full)
    src = e.lookup_source(full)
    parts = []
    if lbl:
        parts.append(f"{lbl[0]}+{full - lbl[1]:#x}")
    if src:
        parts.append(f"{src[0]}:{src[1]}")
    return "  ".join(parts) or "?"


def test_cold_boot_trace():
    if not ROM.exists():
        pytest.skip("ROM not built")
    e = Emu(load_srm_sidecar=False)
    e.load_rom(str(ROM))
    if ADBG.exists():
        e.load_adbg(str(ADBG))
    e.rearm_cpu()
    e.reset()

    # Trace the whole 24-bit bus so we catch wherever boot diverges.
    e.tracer_start(0x000000, 0xFFFFFF, ring_capacity=1 << 16)

    halted = e.run_until_stp(max_frames=10)
    trace = e.tracer_drain()
    e.tracer_stop()

    s = e.get_state()
    rec = [e.read(0x710100 + i) for i in range(4)]
    brk_pc = rec[0] | (rec[1] << 8)
    brk_pb = rec[2]

    lines = trace.strip().splitlines()
    print(f"\n=== boot trace: {len(lines)} instrs, halted={halted} ===")
    print("--- last 40 instrs ---")
    for ln in lines[-40:]:
        print(ln)
    print("--- final state ---")
    print(f"PC=${s.b:02X}:{s.pc:04X} A=${s.a:04X} X=${s.x:04X} "
          f"Y=${s.y:04X} P=${s.p:02X} S=${s.s:04X}")
    print(f"PC source: {_resolve(e, (s.b << 16) | s.pc)}")
    if rec != [0xFF, 0xFF, 0xFF, 0xFF] and (brk_pb != 0xFF or brk_pc != 0xFFFF):
        full = (brk_pb << 16) | brk_pc
        print(f"BRK trap fired: ${brk_pb:02X}:{brk_pc:04X}  {_resolve(e, full)}")
    else:
        print("BRK trap record empty (no BRK trapped)")
    e.close()
