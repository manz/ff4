"""The equipped-hands popup renders its glyphs once per character and hand items.

Vanilla transfers the popup window again every ~20 frames; each transfer asks whether the character or a hand's item
changed since the glyphs were drawn. The check read carry after `cmp` and `cpy`, which set it on equal values, so
every transfer re-rendered both hands on the main thread, two to three frames of work each time.
"""
from __future__ import annotations

from _ff4kintsuki import (
    CECIL_SLOT,
    CMD_ITEM,
    choose_command,
    kss_path,
    load_emu_from_kss,
    tap,
    wait_for_turn,
    walk_into_battle,
)
from kintsuki import Button

KSS = kss_path("ff4-before-field-inventory.kss")
HANDS = 2
IDLE_FRAMES = 120  # several of vanilla's window transfers


def test_the_popup_renders_once_while_it_shows():
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    try:
        walk_into_battle(e)
        wait_for_turn(e, CECIL_SLOT)
        choose_command(e, CMD_ITEM)
        e.run_frames(30)
        renders = []
        render_hand = e.lookup_symbol_addr("battle/equip_window._render_hand")
        assert render_hand is not None
        e.add_exec_callback(render_hand, render_hand, lambda *_: renders.append(e.frame_count))
        tap(e, Button.UP, gap=12)  # from the top of the list into the popup
        e.run_frames(IDLE_FRAMES)
        assert len(renders) == HANDS
    finally:
        e.close()
