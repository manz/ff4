"""
Unit tests for Field Inventory HDMA table generation and seam detection.

These tests verify the mathematical logic of the circular buffer scrolling
without requiring the emulator. They help understand when and why the
seam enters the border zone.

Run with: pytest tests/test_field_inventory_seam.py -v
"""

import pytest
from dataclasses import dataclass
from typing import List, Tuple, Optional


# =============================================================================
# Constants (matching inventory_rolling.s)
# =============================================================================

BUFFER_SLOTS = 11        # 11 slots (10 visible + 1 pre-render)
VISIBLE_ITEMS = 10       # Visible item rows
PIXELS_PER_SLOT = 16     # Pixels per item row
SCROLL_WRAP = 176        # 11 slots × 16 pixels = 176
TILEMAP_HEIGHT = 256     # Tilemap wraps at 256 pixels
BORDER_ZONE_MIN = 176    # Border zone starts at 176
SCROLL_LIMIT = 38        # Max scroll position


# =============================================================================
# HDMA Table Generation Logic (Python port of assembly)
# =============================================================================

@dataclass
class HDMAEntry:
    """Single HDMA table entry"""
    count: int      # Scanline count
    scroll: int     # Scroll value
    rel: int        # Relative to base scroll


@dataclass
class SeamAnalysis:
    """Analysis of seam position and status"""
    buffer_pos: int
    seam_row: int           # -1 if no seam
    seam_rel_scroll: Optional[int]
    seam_normalized: Optional[int]
    seam_in_border: bool
    all_rows: List[dict]


def calculate_vram_slot(buffer_pos: int, row: int) -> int:
    """Calculate which VRAM slot a visible row uses."""
    return (buffer_pos + row) % BUFFER_SLOTS


def calculate_seam_row(buffer_pos: int) -> int:
    """
    Calculate which visible row is the seam (where vram_slot wraps from 10 to 0).
    Returns -1 if no seam (buffer_pos == 0).
    """
    if buffer_pos == 0:
        return -1
    return BUFFER_SLOTS - buffer_pos


def calculate_scroll_value(row: int, buffer_pos: int, base_scroll: int, anim_offset: int) -> int:
    """
    Calculate the scroll value for a given row.

    This matches the assembly logic in UpdateMenuScrollHDMA:
        vram_slot = (buffer_pos + row) mod BUFFER_SLOTS
        scroll = BASE + (vram_slot * 16) - (row * 16) + anim_offset
    """
    vram_slot = calculate_vram_slot(buffer_pos, row)
    vram_offset = vram_slot * PIXELS_PER_SLOT
    scanline_offset = row * PIXELS_PER_SLOT
    return base_scroll + vram_offset - scanline_offset + anim_offset


def is_in_border_zone(rel_scroll: int) -> bool:
    """Check if a relative scroll value puts the row in the border zone."""
    # Normalize to [0, 255]
    normalized = rel_scroll % TILEMAP_HEIGHT
    return normalized >= BORDER_ZONE_MIN


def normalize_scroll(rel_scroll: int) -> int:
    """Normalize scroll value to [0, 255]."""
    return rel_scroll % TILEMAP_HEIGHT


def build_hdma_table(buffer_pos: int, base_scroll: int, anim_offset: int) -> List[HDMAEntry]:
    """
    Build the HDMA table for the given state.
    Returns list of entries (border, 10 item rows, below items).
    """
    entries = []

    # Entry 0: Border area - 48 scanlines at BASE
    entries.append(HDMAEntry(count=48, scroll=base_scroll, rel=0))

    # Entries 1-10: Item rows
    for row in range(VISIBLE_ITEMS):
        scroll = calculate_scroll_value(row, buffer_pos, base_scroll, anim_offset)
        rel = scroll - base_scroll
        entries.append(HDMAEntry(count=16, scroll=scroll, rel=rel))

    # Entry 11: Below items - 16 scanlines at BASE + 16
    below_scroll = base_scroll + 16
    entries.append(HDMAEntry(count=16, scroll=below_scroll, rel=16))

    return entries


def analyze_seam(buffer_pos: int, base_scroll: int, anim_offset: int) -> SeamAnalysis:
    """Analyze the seam position for the given state."""
    seam_row = calculate_seam_row(buffer_pos)
    entries = build_hdma_table(buffer_pos, base_scroll, anim_offset)

    all_rows = []
    seam_rel_scroll = None
    seam_normalized = None
    seam_in_border = False

    for row in range(VISIBLE_ITEMS):
        entry = entries[row + 1]  # +1 because entry 0 is border
        vram_slot = calculate_vram_slot(buffer_pos, row)
        normalized = normalize_scroll(entry.rel)
        in_border = normalized >= BORDER_ZONE_MIN

        row_info = {
            'row': row,
            'vram_slot': vram_slot,
            'rel_scroll': entry.rel,
            'normalized': normalized,
            'in_border': in_border,
            'is_seam': row == seam_row,
        }
        all_rows.append(row_info)

        if row == seam_row:
            seam_rel_scroll = entry.rel
            seam_normalized = normalized
            seam_in_border = in_border

    return SeamAnalysis(
        buffer_pos=buffer_pos,
        seam_row=seam_row,
        seam_rel_scroll=seam_rel_scroll,
        seam_normalized=seam_normalized,
        seam_in_border=seam_in_border,
        all_rows=all_rows,
    )


def simulate_scroll_down(buffer_pos: int, base_scroll: int) -> Tuple[List[dict], bool]:
    """
    Simulate a scroll down animation and detect if seam enters border.

    Returns:
        - List of frame data (8 frames, animation offset from -16 to -2)
        - Boolean indicating if seam enters border during animation
    """
    new_buffer_pos = (buffer_pos + 1) % BUFFER_SLOTS
    seam_row = calculate_seam_row(new_buffer_pos)

    frames = []
    seam_enters_border = False

    # Animation goes from -16 to 0 (8 frames, +2 per frame)
    for frame in range(8):
        anim_offset = -16 + (frame * 2)  # -16, -14, -12, ..., -2
        analysis = analyze_seam(new_buffer_pos, base_scroll, anim_offset)

        frame_data = {
            'frame': frame,
            'anim_offset': anim_offset,
            'seam_row': seam_row,
            'seam_normalized': analysis.seam_normalized,
            'seam_in_border': analysis.seam_in_border,
        }
        frames.append(frame_data)

        if analysis.seam_in_border:
            seam_enters_border = True

    return frames, seam_enters_border


# =============================================================================
# Tests
# =============================================================================

class TestSeamCalculation:
    """Test seam row calculation."""

    def test_seam_row_at_buffer_pos_0(self):
        """No seam when buffer_pos is 0."""
        assert calculate_seam_row(0) == -1

    def test_seam_row_at_buffer_pos_1(self):
        """Seam at row 10 when buffer_pos is 1 (off-screen)."""
        assert calculate_seam_row(1) == 10  # 11 - 1 = 10

    def test_seam_row_at_buffer_pos_2(self):
        """Seam at row 9 when buffer_pos is 2."""
        assert calculate_seam_row(2) == 9  # 11 - 2 = 9

    def test_seam_row_at_buffer_pos_10(self):
        """Seam at row 1 when buffer_pos is 10."""
        assert calculate_seam_row(10) == 1  # 11 - 10 = 1

    def test_seam_visible_range(self):
        """Seam is visible (rows 0-9) when buffer_pos is 2-10."""
        for buf_pos in range(2, 11):
            seam_row = calculate_seam_row(buf_pos)
            assert 0 <= seam_row <= 9, f"buf_pos={buf_pos}, seam_row={seam_row}"


class TestVRAMSlotCalculation:
    """Test VRAM slot calculation."""

    def test_vram_slot_initial_state(self):
        """Initial state: slots 0-9 for rows 0-9."""
        for row in range(10):
            assert calculate_vram_slot(0, row) == row

    def test_vram_slot_wraps(self):
        """VRAM slot wraps at BUFFER_SLOTS."""
        # buffer_pos=5, row=7 -> (5+7)%11 = 1
        assert calculate_vram_slot(5, 7) == 1

    def test_vram_slot_at_seam(self):
        """At seam row, VRAM slot should be 0 (wrapped from 10)."""
        for buf_pos in range(1, 11):
            seam_row = calculate_seam_row(buf_pos)
            if seam_row >= 0 and seam_row < VISIBLE_ITEMS:
                # The seam row is where slot wraps to 0
                vram_slot = calculate_vram_slot(buf_pos, seam_row)
                assert vram_slot == 0, f"buf_pos={buf_pos}, seam_row={seam_row}, slot={vram_slot}"


class TestScrollValueCalculation:
    """Test scroll value calculation for HDMA entries."""

    def test_initial_state_no_offset(self):
        """Initial state with no animation offset."""
        base = 100
        for row in range(10):
            scroll = calculate_scroll_value(row, 0, base, 0)
            expected = base + (row * 16) - (row * 16)  # = base
            assert scroll == expected, f"row={row}, scroll={scroll}"

    def test_scroll_values_during_animation(self):
        """Scroll values shift by animation offset."""
        base = 100
        anim = -8
        for row in range(10):
            scroll = calculate_scroll_value(row, 0, base, anim)
            expected = base + (row * 16) - (row * 16) + anim  # = base + anim
            assert scroll == expected, f"row={row}, scroll={scroll}"

    def test_scroll_discontinuity_at_seam(self):
        """Scroll value jumps at seam due to vram_slot wrap."""
        base = 100
        buf_pos = 5
        seam_row = calculate_seam_row(buf_pos)

        if seam_row > 0:
            # Row before seam
            scroll_before = calculate_scroll_value(seam_row - 1, buf_pos, base, 0)
            rel_before = scroll_before - base

            # Seam row
            scroll_seam = calculate_scroll_value(seam_row, buf_pos, base, 0)
            rel_seam = scroll_seam - base

            # The jump should be significant (due to slot wrapping)
            jump = rel_seam - rel_before
            # Expected: vram_slot goes from 10 to 0, so offset changes by -160
            # But scanline_offset also changes by +16, so net is -176
            assert jump != 16, f"Expected discontinuity at seam, got jump={jump}"


class TestBorderZoneDetection:
    """Test border zone detection."""

    def test_item_zone_values(self):
        """Values 0-175 are in item zone."""
        for val in range(176):
            assert not is_in_border_zone(val), f"val={val} should be in item zone"

    def test_border_zone_values(self):
        """Values 176-255 are in border zone."""
        for val in range(176, 256):
            assert is_in_border_zone(val), f"val={val} should be in border zone"

    def test_negative_values_normalize(self):
        """Negative values normalize correctly."""
        # -80 normalizes to 176, which is in border
        assert is_in_border_zone(-80)
        # -16 normalizes to 240, which is in border
        assert is_in_border_zone(-16)
        # -176 normalizes to 80, which is in item zone
        assert not is_in_border_zone(-176)


class TestSeamInBorderDetection:
    """Test detecting when seam row is in border zone."""

    def test_initial_state_no_seam(self):
        """Initial state has no seam."""
        analysis = analyze_seam(0, 100, 0)
        assert analysis.seam_row == -1
        assert not analysis.seam_in_border

    def test_seam_at_buffer_pos_1(self):
        """Buffer pos 1: seam at row 10 (off-screen)."""
        analysis = analyze_seam(1, 100, 0)
        assert analysis.seam_row == 10
        # Seam is off-screen, so seam_in_border should be False
        # (row 10 is not in visible items 0-9)
        assert not analysis.seam_in_border

    @pytest.mark.parametrize("buf_pos", range(2, 11))
    def test_seam_visible_at_various_buffer_pos(self, buf_pos: int):
        """Seam is visible for buffer positions 2-10."""
        analysis = analyze_seam(buf_pos, 100, 0)
        seam_row = calculate_seam_row(buf_pos)
        assert analysis.seam_row == seam_row
        assert 0 <= seam_row <= 9


class TestScrollDownSimulation:
    """Test scroll down animation simulation."""

    def test_first_scroll_seam_off_screen(self):
        """First scroll: seam moves to row 10 (off-screen)."""
        frames, glitch = simulate_scroll_down(0, 100)
        # After first scroll, buf_pos=1, seam_row=10 (off-screen)
        assert len(frames) == 8
        assert frames[0]['seam_row'] == 10
        assert not glitch, "No glitch expected when seam is off-screen"

    def test_second_scroll_seam_at_row_9(self):
        """Second scroll: seam at row 9."""
        frames, glitch = simulate_scroll_down(1, 100)
        # After second scroll, buf_pos=2, seam_row=9
        assert frames[0]['seam_row'] == 9

    def test_animation_offset_progression(self):
        """Animation offset goes from -16 to -2."""
        frames, _ = simulate_scroll_down(0, 100)
        expected_offsets = [-16, -14, -12, -10, -8, -6, -4, -2]
        for i, frame in enumerate(frames):
            assert frame['anim_offset'] == expected_offsets[i]


class TestSeamGlitchConditions:
    """Test specific conditions that cause seam glitches."""

    def test_seam_enters_border_during_animation(self):
        """
        Test case where seam enters border during animation.

        This happens when:
        1. buffer_pos puts seam at a visible row
        2. The seam row's rel_scroll + anim_offset normalizes to [176-255]
        """
        # Find a state where glitch occurs
        base_scroll = 100

        for buf_pos in range(1, 11):
            frames, glitch = simulate_scroll_down(buf_pos, base_scroll)
            if glitch:
                # Found a glitchy scroll
                print(f"\nGlitch found at buf_pos={buf_pos} -> {(buf_pos+1)%11}")
                for f in frames:
                    status = "GLITCH" if f['seam_in_border'] else "ok"
                    print(f"  Frame {f['frame']}: anim={f['anim_offset']}, "
                          f"norm={f['seam_normalized']}, {status}")
                # Don't assert anything - we're just documenting the behavior

    def test_no_glitch_when_seam_off_screen(self):
        """No glitch when seam row is >= 10 (off-screen)."""
        frames, glitch = simulate_scroll_down(0, 100)
        # buf_pos 0 -> 1, seam_row = 10 (off-screen)
        assert not glitch

    def test_analyze_all_buffer_positions(self):
        """Analyze all buffer positions to find glitch-prone ones."""
        base_scroll = 100
        glitchy_positions = []

        for buf_pos in range(11):
            frames, glitch = simulate_scroll_down(buf_pos, base_scroll)
            new_buf_pos = (buf_pos + 1) % BUFFER_SLOTS
            seam_row = calculate_seam_row(new_buf_pos)

            if glitch:
                glitchy_positions.append({
                    'from_buf_pos': buf_pos,
                    'to_buf_pos': new_buf_pos,
                    'seam_row': seam_row,
                })

        # Log findings
        if glitchy_positions:
            print("\nGlitchy buffer position transitions:")
            for g in glitchy_positions:
                print(f"  {g['from_buf_pos']} -> {g['to_buf_pos']}: seam at row {g['seam_row']}")


class TestHDMATableStructure:
    """Test HDMA table structure and values."""

    def test_table_has_correct_entries(self):
        """Table has border + 10 item rows + below = 12 entries."""
        table = build_hdma_table(0, 100, 0)
        assert len(table) == 12

    def test_border_entry(self):
        """First entry is border (48 scanlines)."""
        table = build_hdma_table(0, 100, 0)
        assert table[0].count == 48
        assert table[0].rel == 0

    def test_item_row_entries(self):
        """Item row entries are 16 scanlines each."""
        table = build_hdma_table(0, 100, 0)
        for i in range(1, 11):
            assert table[i].count == 16

    def test_below_entry(self):
        """Last entry is below items (16 scanlines, rel=16)."""
        table = build_hdma_table(0, 100, 0)
        assert table[11].count == 16
        assert table[11].rel == 16


class TestSeamRowScrollValues:
    """Detailed tests for scroll values at the seam row."""

    def test_seam_row_rel_scroll_calculation(self):
        """
        Test the relative scroll calculation at the seam row.

        At seam row:
        - vram_slot = 0 (wrapped from 10)
        - vram_offset = 0
        - scanline_offset = seam_row * 16

        So rel_scroll = 0 - scanline_offset + anim_offset
                      = -seam_row * 16 + anim_offset

        For this to be in border zone [176-255] (mod 256):
        - If rel_scroll is negative, it wraps to 256 + rel_scroll
        - We need: 176 <= (rel_scroll % 256) <= 255
        """
        base = 100
        buf_pos = 5  # seam_row = 6

        # No animation
        analysis = analyze_seam(buf_pos, base, 0)
        seam_row = analysis.seam_row
        expected_rel = 0 - (seam_row * 16)  # = -96
        expected_norm = expected_rel % 256  # = 160

        assert analysis.seam_rel_scroll == expected_rel
        assert analysis.seam_normalized == expected_norm
        assert not analysis.seam_in_border  # 160 < 176

    def test_seam_enters_border_with_negative_animation(self):
        """
        Test when negative animation offset pushes seam into border.

        For seam_row=6: rel = -96 + anim_offset
        Normalized: (-96 + anim_offset) % 256

        For anim_offset = -16: rel = -112, norm = 144 (not in border)
        For anim_offset = 0: rel = -96, norm = 160 (not in border)

        Let's find when it enters border...
        """
        base = 100

        for buf_pos in range(2, 11):
            seam_row = calculate_seam_row(buf_pos)
            # rel = -seam_row * 16 + anim_offset
            # For border: 176 <= (-seam_row * 16 + anim_offset) % 256

            # During scroll animation, anim goes from -16 to -2
            # New buf_pos after scroll
            new_buf_pos = (buf_pos + 1) % BUFFER_SLOTS
            new_seam_row = calculate_seam_row(new_buf_pos)

            if new_seam_row < 0 or new_seam_row >= VISIBLE_ITEMS:
                continue

            # At frame 0, anim_offset = -16
            rel_at_start = 0 - (new_seam_row * 16) + (-16)
            norm_at_start = rel_at_start % 256

            # At frame 7, anim_offset = -2
            rel_at_end = 0 - (new_seam_row * 16) + (-2)
            norm_at_end = rel_at_end % 256

            print(f"\nbuf_pos {buf_pos}->{new_buf_pos}, seam_row={new_seam_row}")
            print(f"  Start: rel={rel_at_start}, norm={norm_at_start}, border={norm_at_start >= 176}")
            print(f"  End:   rel={rel_at_end}, norm={norm_at_end}, border={norm_at_end >= 176}")


# =============================================================================
# Integration Tests
# =============================================================================

class TestFullScrollSequence:
    """Test a full sequence of scrolls."""

    def test_scroll_sequence_detects_glitches(self):
        """Scroll through entire inventory and count glitch opportunities."""
        base = 100
        buf_pos = 0
        glitch_count = 0

        print("\n=== Full Scroll Sequence Analysis ===")

        for scroll_num in range(SCROLL_LIMIT):
            frames, glitch = simulate_scroll_down(buf_pos, base)
            new_buf_pos = (buf_pos + 1) % BUFFER_SLOTS
            seam_row = calculate_seam_row(new_buf_pos)

            if glitch:
                glitch_count += 1
                print(f"Scroll {scroll_num+1}: {buf_pos}->{new_buf_pos}, seam={seam_row} - GLITCH")
            else:
                print(f"Scroll {scroll_num+1}: {buf_pos}->{new_buf_pos}, seam={seam_row} - ok")

            buf_pos = new_buf_pos

        print(f"\nTotal glitches in {SCROLL_LIMIT} scrolls: {glitch_count}")

        # This test documents the behavior - adjust expectation based on findings
        # If the implementation is correct, glitch_count should be 0
        # If there's a bug, this shows where


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
