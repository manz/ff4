"""Resolve rolling-buffer state addresses from the build's `.adbg`.

`RollingBufferState` instances are declared as a816 struct casts
(`menu_rolling := (0x7E9C90 as RollingBufferState)`), which the
assembler eager-expands into per-field symbols
(`field_menu_rolling.buffer_pos`, ...). Those land in the `.adbg`
SYMBOLS section as `SymbolKind.CONSTANT`, which `Emu.lookup_symbol_addr`
does not index, so read the table directly rather than hardcoding
absolute addresses in tests. Hardcoded ones silently rotted every time
the struct grew or an instance changed arena.
"""
from __future__ import annotations

from functools import cache
from pathlib import Path

import pytest
from a816 import debug_info

ADBG = Path(__file__).resolve().parents[1] / "build" / "ff4.ips.adbg"


@cache
def _symbols() -> dict[str, int]:
    if not ADBG.exists():
        pytest.skip(f"debug info not built at {ADBG}")
    return {s.name: s.address for s in debug_info.read(ADBG).symbols}


def addr(instance: str, field: str) -> int:
    """Absolute WRAM address of `field` in the named rolling instance."""
    name = f"{instance}.{field}"
    syms = _symbols()
    if name not in syms:
        raise AssertionError(f"{name} missing from {ADBG.name} symbol table")
    return syms[name]
