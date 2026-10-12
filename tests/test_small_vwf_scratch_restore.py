"""The small-VWF renderer borrows three direct-page bytes ($73-$75 off D: bits left on the tile, temp, counter) and
gives them back: `render.init` saves them to SRAM, `render.deinit` restores them. The restore read them with `lda.b`,
a direct-page load of the scratch itself, so the caller got the renderer's values back instead of its own."""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import kss_path, load_emu_from_kss, tap
from a816 import debug_info
from kintsuki import Button

ADBG = Path(__file__).resolve().parents[1] / "build" / "ff4.ips.adbg"
SCRATCH = range(0x73, 0x76)


def _address(name: str) -> int:
    if not ADBG.exists():
        pytest.skip(f"debug info not built at {ADBG}")
    return next(s.address for s in debug_info.read(ADBG).symbols if s.name == name) & 0xFFFFFF


def test_the_menu_text_renders_give_the_scratch_back() -> None:
    init, deinit_return = _address("render.init"), _address("render.make_pointers") - 1  # deinit's rts
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    open_renders: list[tuple[int, bytes]] = []
    changed: list[tuple[bytes, bytes]] = []
    renders = 0

    def scratch(d: int) -> bytes:
        return bytes(emu.read((d + offset) & 0xFFFF) for offset in SCRATCH)

    def on_init(*_) -> None:
        d = emu.get_state().d
        open_renders.append((d, scratch(d)))

    def on_deinit_return(*_) -> None:
        nonlocal renders
        if open_renders:
            d, before = open_renders.pop()
            renders += 1
            if scratch(d) != before:
                changed.append((before, scratch(d)))

    emu.add_exec_callback(init, init, on_init)
    emu.add_exec_callback(deinit_return, deinit_return, on_deinit_return)
    try:
        tap(emu, Button.X, gap=60)  # the main menu's texts
        tap(emu, Button.A, gap=60)  # the items menu's
        assert renders
        assert changed == []
    finally:
        emu.close()
