"""Bank $01 past the relocated InitScrollHDMA is vanilla battle-animation code, not free space.

JP's btlgfx_code3 runs from $01:E300 to $01:FF34: SetMonsterScroll, TeleportPalAnim, the special and summon
animations. Battle still `jsl`s them; the patch may only reuse InitScrollHDMA's old bytes ($01:EBD2-$01:ED61).
"""
from __future__ import annotations

from pathlib import Path

import pytest

from kintsuki import Emu

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"
VANILLA_BATTLE_CODE = (0x01ED62, 0x01FF34)


def _file_offset(address: int) -> int:
    return (address >> 16 & 0x7F) * 0x8000 + (address & 0x7FFF)


def test_the_battle_animation_code_in_bank_01_is_untouched() -> None:
    if not ROM.exists():
        pytest.skip(f"ff4.sfc not built at {ROM}")
    lo, hi = VANILLA_BATTLE_CODE
    vanilla = ROM.read_bytes()[_file_offset(lo):_file_offset(hi) + 1]
    emu = Emu(load_srm_sidecar=False)
    emu.load_rom(str(ROM))  # applies build/ff4.ips
    patched = bytes(emu.read_range(lo, hi - lo + 1))
    emu.close()
    changed = [lo + i for i, (a, b) in enumerate(zip(vanilla, patched, strict=True)) if a != b]
    assert not changed, f"patched over vanilla battle code at ${changed[0]:06X} ({len(changed)} bytes)"
