"""utils/dialog_labels.py: the inn's Oui / Non and Gils labels baked into the 8x8 font's free kana slots, and the inn
windows showing them."""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss
from katsuji import VwfFont
from katsuji import config as katsuji_config
from katsuji.script import Table

from utils import dialog_labels
from utils.bake_names import Glyphs

GOLDENS = Path(__file__).parent / "goldens" / "dialog_labels"
FONT = Path("build/gen/menu_font.dat")
FIELD_DP = 0x7E0600
EVENT_BYTES = 0x7E09D5  # the event script buffer GetNextEventByte reads, past its index
INN = 0x00EC70  # EventCmd_dc: the inn's welcome, the gils window, then the Yes / No window
SENTINEL = 0xFFFC  # where the pushed return lands


def _bake(lang: str = "fr", font_8x8: bytes | None = None) -> tuple[bytes, str]:
    glyphs = Glyphs.of(katsuji_config.load(Path("katsuji.toml")).fonts["menu"])
    font = Path("fonts/8x8.bin").read_bytes() if font_8x8 is None else font_8x8
    return dialog_labels.bake(font, VwfFont.decode(FONT.read_bytes()), glyphs, Table("text/ff4_menus.tbl"), lang)


@pytest.fixture(scope="module", params=["fr", "en"])
def baked(request) -> tuple[bytes, str]:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    return _bake(request.param)


def test_only_the_slots_change(baked) -> None:
    font = Path("fonts/8x8.bin").read_bytes()
    changed = {i // dialog_labels.TILE_BYTES for i, (a, b) in enumerate(zip(font, baked[0], strict=True)) if a != b}
    assert changed and changed <= set(dialog_labels.SLOTS)


def test_every_label_has_its_macro(baked) -> None:
    assert all(f"dialog_label_{name}()" in baked[1] for name in dialog_labels.LABELS)


def test_a_used_slot_is_refused() -> None:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    with pytest.raises(ValueError, match="not blank"):
        _bake(font_8x8=bytes(256 * dialog_labels.TILE_BYTES))  # no blank cell anywhere


@pytest.mark.parametrize(("region", "golden"), [
    ((16, 96, 88, 144), "yes_no.png"),
    ((160, 96, 240, 144), "gils.png"),
])
def test_the_inn_window_golden(region, golden) -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=60)
    try:
        emu.write(EVENT_BYTES + 1, 0)  # the inn's price index, the byte after the command
        emu.rearm_cpu()
        state = emu.get_state()
        state.pc, state.p, state.e, state.d, state.b, state.x, state.a = INN, 0x20, False, FIELD_DP & 0xFFFF, 0, 0, 0
        emu.set_state(state)
        emu.push_word(SENTINEL - 1)
        emu.run_frames(240)
        assert_screenshot_matches_golden(emu, GOLDENS / golden, region=region)
    finally:
        emu.close()
