"""The place-name window stays up for the first steps on a new map.

Vanilla closes it on the first step ($00:A9FB), so walking in with the pad held hid the name before it could be read.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss

WINDOW_STATE = 0x7E06EA  # 0 up, 1 closing, 2 closed
STEP_FRAMES = 16


@pytest.fixture
def walking():
    e = load_emu_from_kss(kss_path("ff4-with-town-name.kss"), settle_frames=0)
    e.press(0, Button.UP)
    yield e
    e.close()


def test_the_name_stays_up_for_the_first_steps(walking) -> None:
    walking.run_frames(3 * STEP_FRAMES)
    assert walking.read(WINDOW_STATE) == 0


def test_walking_on_closes_it(walking) -> None:
    walking.run_frames(5 * STEP_FRAMES)
    assert walking.read(WINDOW_STATE) != 0
