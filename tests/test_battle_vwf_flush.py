"""Every VWF tile a battle window shows reaches VRAM: the CHR the renderer drew (its buffer in cart SRAM) and the
tile in VRAM agree within a few frames. A render spanning frames had its region bit taken by an NMI between its init
(the buffer cleared) and its glyphs, which were then never uploaded: the window showed the old glyphs (or none)."""
from __future__ import annotations

from _ff4kintsuki import fresh_late_battle
from _rolling_state import addr, symbol

BG3_MAP, VWF_CHR, VWF_BUFFER = 0xE000, 0xB000, 0x703000  # VRAM bytes: tilemap, tile $100; the buffer, tile $100
VWF_LAST = 0xFC
MONSTER = 0x7E2280  # monster records, $80 each: status byte 1 at +3 (bit 7 KO), HP at +7
SAMPLES_HELD = 4  # a tile differing 4 samples running (8 frames apart) is stale


def _stale(emu) -> set[int]:
    tilemap = bytes(emu.vram_read_range(BG3_MAP, 0x800))
    shown = {tilemap[i] for i in range(0, 0x800, 2) if tilemap[i + 1] & 1 and tilemap[i] < VWF_LAST}
    vram = bytes(emu.vram_read_range(VWF_CHR, 0x1000))
    drawn = bytes(emu.read_range(VWF_BUFFER, 0x1000))
    return {t for t in shown if vram[t * 16 : t * 16 + 16] != drawn[t * 16 : t * 16 + 16]}


def test_shown_vwf_tiles_reach_vram_after_a_monster_dies() -> None:
    emu = fresh_late_battle()
    try:
        emu.write(MONSTER + 3, emu.read(MONSTER + 3) | 0x80)  # monster 0 down: the monster names redraw
        emu.write_range(MONSTER + 7, bytes(2))
        held: dict[int, int] = {}
        stuck: set[int] = set()
        for frame in range(600):
            emu.run_frames(1)
            if frame % 8 == 0:
                stale = _stale(emu)
                held = {t: held.get(t, 0) + 1 for t in stale}
                stuck |= {0x100 + t for t, n in held.items() if n >= SAMPLES_HELD}
        assert stuck == set()
    finally:
        emu.close()



def test_a_render_whose_region_bit_an_nmi_took_still_reaches_vram() -> None:
    """A render that spans frames: its init clears the buffer and sets its region bit, an NMI uploads the cleared
    tiles and takes the bit, the glyphs follow a frame later (a hunt report: tile $130 blank in VRAM for 300 frames).
    Forced here by taking the region bits just before `deinit_gated`: its deinit must flag the region again."""
    emu = fresh_late_battle()
    try:
        mask = addr("battle_render_state", "pending_transfer_mask")
        deinit = symbol("messages_vwf.deinit_gated")
        emu.add_exec_callback(deinit, deinit, lambda *_: emu.write(mask, emu.read(mask) & 0x01))
        emu.write(MONSTER + 3, emu.read(MONSTER + 3) | 0x80)  # monster 0 down: the monster names redraw
        emu.write_range(MONSTER + 7, bytes(2))
        held: dict[int, int] = {}
        stuck: set[int] = set()
        for frame in range(600):
            emu.run_frames(1)
            if frame % 8 == 0:
                held = {t: held.get(t, 0) + 1 for t in _stale(emu)}
                stuck |= {0x100 + t for t, n in held.items() if n >= SAMPLES_HELD}
        assert stuck == set()
    finally:
        emu.close()
