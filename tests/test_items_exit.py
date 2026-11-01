"""Leaving Objets fades out before the list's scroll HDMA goes: the list window doesn't jump up on screen first."""
from __future__ import annotations

import numpy as np
from numpy.typing import NDArray

from _ff4kintsuki import frame_picture, kss_path, load_emu_from_kss, tap
from kintsuki import Button

EXIT_FRAMES = 40
BORDER_X = 4  # a column through the Objets window's bottom border and the list window's top one


def _border_rows(picture: NDArray[np.uint8]) -> tuple[int, ...] | None:
    """The white lines of the borders at BORDER_X (brighter than the window by a ratio that holds while the screen
    fades), None once the screen is too dark to tell."""
    column = picture[:, BORDER_X].sum(axis=-1)
    window = column[30]
    if window < 20:
        return None
    return tuple(y for y in range(24, 96) if column[y] > 8 * window)


def test_the_list_window_stays_put_while_lit() -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    try:
        tap(emu, Button.X, gap=60)
        tap(emu, Button.A, gap=80)  # Objets
        start = _border_rows(frame_picture(emu))
        emu.set_input(0, 1 << int(Button.B))
        rows = []
        for frame in range(EXIT_FRAMES):
            emu.run_frames(1)
            if frame == 6:
                emu.set_input(0, 0)
            rows.append(_border_rows(frame_picture(emu)))
        assert {row for row in rows if row is not None} == {start}
    finally:
        emu.close()
