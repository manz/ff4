"""Battle command window: render once per command set, never flicker.

Vanilla redraws the command window every few frames. The menu logic needs
the command list rebuilt each time, but the VWF glyph render only when the
command set changes (CMD_DIRTY_BIT); the window's overlay is re-copied
from the rendered text buffer on every redraw.

The cmd tilemap upload has to be queued after the main-view mirror and
the overlay copy, or an NMI between them shows the bare mirror (a monster
name) or a half-copied overlay for a frame.
"""
from __future__ import annotations

from kintsuki import Button
from PIL import Image

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

FIELD = kss_path("ff4-before-field-inventory.kss")
BATTLE = kss_path("ff4.kss")
PICTURE = (13, 9, 13 + 256, 9 + 224)
CMD_WINDOW = (44, 140, 108, 200)


def _fresh_battle():
    e = load_emu_from_kss(FIELD, settle_frames=60)
    tap(e, Button.B, gap=20)
    for i in range(7):
        button = (Button.LEFT, Button.RIGHT)[i % 2]
        e.press(0, button)
        e.run_frames(40)
        e.release(0, button)
    e.run_frames(200)  # Cecil's command menu is up
    return e


CMD_DIRTY = 0x7EEF9A
CMD_DIRTY_BIT = 0x20


def test_commands_render_only_when_marked_dirty():
    e = _fresh_battle()
    try:
        renders, marks = [], []
        entry = e.lookup_symbol_addr("battle_render.init_commands_list")
        e.add_exec_callback(entry, entry, lambda _pc, _op: renders.append(e.frame_count))
        e.add_write_callback(
            CMD_DIRTY, CMD_DIRTY, lambda _a, v, *_: marks.append(e.frame_count) if v & CMD_DIRTY_BIT else None
        )
        e.run_frames(240)
        assert len(renders) <= len(marks)
    finally:
        e.close()


def test_command_window_is_stable_through_a_turn(tmp_path):
    e = load_emu_from_kss(BATTLE, settle_frames=10)
    try:
        tap(e, Button.A, gap=20)
        tap(e, Button.A, gap=20)
        crops = []
        while e.frame_count < 420:
            e.run_frames(8)
            if e.frame_count >= 200:
                e.screenshot(str(tmp_path / "s.png"))
                crops.append(Image.open(tmp_path / "s.png").convert("RGB").crop(PICTURE).crop(CMD_WINDOW).tobytes())
        assert len(set(crops)) == 1
    finally:
        e.close()
