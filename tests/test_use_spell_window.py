"""DrawMagicName (small_vwf/menu_text.s draw_spell) blanks 5 cells per spell, the widest baked name.

Vanilla's 9 cells ran past the borders of the cast window ($01:DD75) and of the spell list beside the party; fewer
left the previous list's names behind when the school changes."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap
from kintsuki import Button

GOLDEN = Path(__file__).parent / "goldens" / "use_spell" / "cast_window.png"
CORNER = (0, 0, 96, 80)  # the cast window, its right border and the party window's left one
ROSA = 1


def test_the_cast_window_golden() -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    try:
        tap(emu, Button.X, gap=60)
        tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=60)  # Magie
        for _ in range(ROSA):
            tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=80)
        tap(emu, Button.A, gap=90)  # into the list
        tap(emu, Button.A, gap=90)  # Soin 3
        tap(emu, Button.A, gap=90)  # cast it: the target screen
        assert_screenshot_matches_golden(emu, GOLDEN, region=CORNER)
    finally:
        emu.close()


RYDIA = 3
SPELL_LIST = (0, 72, 256, 224)


def test_a_school_switch_leaves_no_names_behind() -> None:
    """Rituel's list, then Chimère's over it: fewer and shorter names, no tails of the previous ones."""
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    try:
        tap(emu, Button.X, gap=60)
        tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=60)  # Magie
        for _ in range(RYDIA):
            tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=80)  # Rituel
        tap(emu, Button.DOWN, gap=60)  # Chimère
        assert_screenshot_matches_golden(emu, GOLDEN.with_name("summons_after_black.png"), region=SPELL_LIST)
    finally:
        emu.close()
