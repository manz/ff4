"""A dialog [delay] ends however the intro is played.

The delay counted from a direct-page read ($0600 + 0) instead of zero, and waited for the count to equal the
duration exactly: at the third dot of Cecil's "Soit..." (the intro's second message) that byte held $80, past
the duration, and the dialog spun until the counter wrapped.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button, Emu

ROM = Path(__file__).resolve().parents[1] / "build/ff4.sfc"
PAUSE_DURATION = 0x7E08F4


def test_the_intro_delays_end():
    if not ROM.exists():
        pytest.skip("ROM not built")
    e = Emu(load_srm_sidecar=False)
    e.load_rom(str(ROM))
    e.reset()
    try:
        for i in range(37):  # title, then the Red Wings intro up to the soldier's line
            e.run_frames(60)
            if i % 3 == 0:
                button = Button.START if i < 12 else Button.A
                e.press(0, button)
                e.run_frames(6)
                e.release(0, button)
        paused_frames = 0
        for frame in range(0, 1200, 2):
            if frame % 8 == 0:
                e.press(0, Button.A)
            if frame % 8 == 4:
                e.release(0, Button.A)
            e.run_frames(2)
            paused_frames = paused_frames + 2 if e.read(PAUSE_DURATION) else 0
            assert paused_frames < 200, "a dialog delay never ended"
    finally:
        e.close()
