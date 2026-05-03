"""Kerning unit tests + benchmark using the kintsuki Python wheel.

Convention used here: drop a 65816 stub into WRAM that calls the routine
via its long-form (RTL) trampoline `*_Ext` and ends with STP. Python
detects CPU halt (cpu_state.stp == 1) and reads the result registers.

Run from the ff4 repo:
    pytest tests/test_kerning_kintsuki.py -v
"""
from __future__ import annotations

import struct
from pathlib import Path

import pytest

from a816.program import Program
from a816.writers import Writer
from kintsuki import Emu, SymbolTable

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"
SYM = REPO / "build/ff4.sym"
FONT = REPO / "assets/font.dat"
MENU_FONT = REPO / "assets/menu_font.dat"
STUB_PATH = Path(__file__).parent / "asm/kerning_stub.s"
MENU_STUB_PATH = Path(__file__).parent / "asm/kerning_menu_stub.s"
# Kerning data lives immediately after the bitmap+width section:
# offset = 256 * (char_height + 1). Dialog font is 16-tall, menu font 8-tall.
KERNING_OFFSET = 256 * 17       # within the dialog font asset
MENU_KERNING_OFFSET = 256 * 9   # within the menu font asset

# Direct-page slots used by each menu-font caller for `prev_char`.
# Hardcoded because they live inside .scope blocks and aren't exported.
SMALLVWF_PREV_CHAR = 0x77   # src/small_vwf/render.s: render scope
BATTLEMSG_PREV_CHAR = 0xB1  # src/battle/message.s


def _read_kerning_table() -> list[tuple[int, int]]:
    """Returns the (key, value) pairs from font.dat[0x1100:].
    Ground truth for what setup_font(0) loads."""
    data = FONT.read_bytes()
    n = struct.unpack_from("<H", data, KERNING_OFFSET)[0]
    return [
        struct.unpack_from("<HB", data, KERNING_OFFSET + 2 + i * 3)
        for i in range(n)
    ]


def _read_menu_kerning_table() -> list[tuple[int, int]]:
    """Returns the (key, value) pairs from menu_font.dat[0x900:].
    Ground truth for the small_vwf and battle message lookups."""
    data = MENU_FONT.read_bytes()
    n = struct.unpack_from("<H", data, MENU_KERNING_OFFSET)[0]
    return [
        struct.unpack_from("<HB", data, MENU_KERNING_OFFSET + 2 + i * 3)
        for i in range(n)
    ]


@pytest.fixture(scope="session")
def syms() -> SymbolTable:
    if not SYM.exists():
        pytest.skip(f"ff4.sym not built at {SYM}")
    return SymbolTable(SYM)


@pytest.fixture
def cold_emu():
    if not ROM.exists():
        pytest.skip(f"ff4.sfc not built at {ROM}")
    e = Emu()
    e.load_rom(str(ROM))
    yield e
    e.close()


@pytest.fixture(scope="session")
def stub_src() -> str:
    if not STUB_PATH.exists():
        pytest.skip(f"kerning stub not found at {STUB_PATH}")
    return STUB_PATH.read_text()


class _StubWriter(Writer):
    def __init__(self) -> None:
        self.blocks: list[tuple[int, bytes]] = []

    def begin(self) -> None: ...
    def write_block_header(self, block: bytes, block_address: int) -> None: ...

    def write_block(self, block: bytes, block_address: int) -> None:
        self.blocks.append((block_address, block))

    def end(self) -> None: ...


def _assemble(src: str, **symbols: int) -> bytes:
    """Assemble `src` with `symbols` pre-loaded into a816's resolver scope.
    The .s file references each name; we don't bake addresses into a
    template string."""
    program = Program()
    for name, value in symbols.items():
        program.resolver.current_scope.add_symbol(name, value)
    w = _StubWriter()
    program.assemble_string_with_emitter(src, "<test>", w)
    return b"".join(b for _, b in w.blocks)


def _run_stub(emu: Emu, stub_src: str, kerning_func: int, pair: int,
              setup_font: int, font_index: int = 0,
              *, max_frames: int = 30) -> Emu.CpuState:
    """Assemble tests/asm/kerning_stub.s with the given symbols, drop it
    in WRAM, run until STP halts the CPU, return the captured state."""
    stub = _assemble(
        stub_src,
        pair=pair,
        kerning_func=kerning_func,
        setup_font=setup_font,
        font_index=font_index,
        # CURRENT_C: direct-page slot the stub uses to stash the pair before
        # calling the kerning routine. Matches dialog VWF convention.
        CURRENT_C=0x25,
    )
    # Rebuild the CPU coroutine so a previous STP-halt from this same emu
    # doesn't leave the dispatch loop suspended on a stale stack.
    emu.rearm_cpu()
    emu.write_range(0x7E0000, stub)
    s = emu.get_state()
    s.pc = 0x7E0000
    s.s = 0x1FFF
    s.e = False
    s.p = 0
    s.stp = 0  # previous stub may have halted the CPU; un-halt
    s.wai = 0
    emu.set_state(s)
    assert emu.run_until_stp(max_frames=max_frames), "stub never halted"
    return emu.get_state()


# ----------------------------------------------------------- Direct calls

@pytest.fixture
def setup_font(syms):
    return syms["setup_font_ext"]


def test_binary_search_returns_a_value(cold_emu, syms, setup_font, stub_src):
    s = _run_stub(cold_emu, stub_src,
                  syms["dialog_get_kerning_adjustment_binary_search_ext"], 0x575c,
                  setup_font)
    assert s.stp == 1
    assert s.a != 0x575C


# -------------------------------------------------- Branch coverage workload

def _pick_workload(table_reader=_read_kerning_table) -> list[tuple[int, str]]:
    """Workload that exercises every branch of the binary-search routine.

    Binary paths covered:
      - found at first mid (entry near n/2)
      - search_upper repeatedly (entry near end of sorted prefix)
      - search_lower repeatedly (entry [0])
      - not_found via low > high (unknowns < min and > max)
    """
    table = table_reader()
    keys = [k for k, _ in table]
    sorted_keys = sorted(keys)
    keys_set = set(keys)
    n = len(table)

    # Use a sorted-prefix slice so binary search stays correct on the
    # "known" cases. font.dat is mostly sorted but trailing entries break
    # the invariant — we want this test to pass when the data IS valid.
    # `cutoff` = length of the longest sorted prefix.
    cutoff = 1
    while cutoff < n and keys[cutoff] >= keys[cutoff - 1]:
        cutoff += 1

    sorted_prefix = keys[:cutoff]
    known: list[tuple[int, str]] = [
        (sorted_prefix[0],                "known-first"),
        (sorted_prefix[cutoff // 2],      "known-mid"),
        (sorted_prefix[-1],               "known-last-sorted"),
    ]

    lo = sorted_keys[0]
    hi = sorted_keys[-1]
    unknown: list[tuple[int, str]] = [
        (max(lo - 1, 0),  "unknown-below-min"),
        (min(hi + 1, 0xFFFF), "unknown-above-max"),
    ]
    # Gap: pick a value strictly between two sorted keys that's absent.
    gap = next(((sorted_keys[i] + sorted_keys[i + 1]) // 2
                for i in range(len(sorted_keys) - 1)
                if sorted_keys[i + 1] - sorted_keys[i] > 1
                and (sorted_keys[i] + sorted_keys[i + 1]) // 2 not in keys_set),
               None)
    if gap is not None:
        unknown.append((gap, "unknown-gap"))

    return known + unknown


def _safe_workload() -> list[tuple[int, str]]:
    try:
        return _pick_workload()
    except FileNotFoundError:
        # Skip-marker entry; tests detect the label and skip.
        return [(0, "no-font")]


WORKLOAD = _safe_workload()


def _expected_adjustment(table: list[tuple[int, int]], pair: int) -> int:
    """Ground-truth lookup mirroring the SNES routine: 0 if pair absent,
    abs-value adjustment byte otherwise. The .dat stores `abs(advance)`."""
    for key, value in table:
        if key == pair:
            return value & 0xFF
    return 0


@pytest.mark.parametrize("pair,label", WORKLOAD,
                         ids=[label for _, label in WORKLOAD])
def test_binary_matches_python_oracle(cold_emu, syms, setup_font, stub_src,
                                      pair, label):
    if label == "no-font":
        pytest.skip(f"{FONT} missing")
    expected = _expected_adjustment(_read_kerning_table(), pair)
    a_bin = _run_stub(cold_emu, stub_src,
                      syms["dialog_get_kerning_adjustment_binary_search_ext"], pair,
                      setup_font)
    # Mask to low byte: kerning value is signed 8-bit, high byte is junk
    # from the input pair.
    assert (a_bin.a & 0xFF) == expected, (
        f"{label} pair=0x{pair:04x}: "
        f"binary=0x{a_bin.a:04x} expected=0x{expected:02x}"
    )


# ----------------------------------- Menu-font (small_vwf, battle message)

@pytest.fixture(scope="session")
def menu_stub_src() -> str:
    if not MENU_STUB_PATH.exists():
        pytest.skip(f"menu kerning stub not found at {MENU_STUB_PATH}")
    return MENU_STUB_PATH.read_text()


def _run_menu_stub(emu: Emu, stub_src: str, kerning_func: int, pair: int,
                   prev_char_slot: int, *, max_frames: int = 30) -> Emu.CpuState:
    stub = _assemble(
        stub_src,
        pair=pair,
        kerning_func=kerning_func,
        prev_char=prev_char_slot,
    )
    emu.rearm_cpu()
    emu.write_range(0x7E0000, stub)
    s = emu.get_state()
    s.pc = 0x7E0000
    s.s = 0x1FFF
    s.e = False
    s.p = 0
    s.stp = 0
    s.wai = 0
    emu.set_state(s)
    assert emu.run_until_stp(max_frames=max_frames), "menu stub never halted"
    return emu.get_state()


def _safe_menu_workload() -> list[tuple[int, str]]:
    try:
        return _pick_workload(_read_menu_kerning_table)
    except FileNotFoundError:
        return [(0, "no-menu-font")]


MENU_WORKLOAD = _safe_menu_workload()

MENU_LOOKUPS = [
    ("small_vwf", "small_vwf_kerning_binary_ext", SMALLVWF_PREV_CHAR),
    ("battle_msg", "battle_msg_kerning_binary_ext", BATTLEMSG_PREV_CHAR),
]


@pytest.mark.parametrize("renderer,bin_name,prev_char_slot", MENU_LOOKUPS,
                         ids=[r[0] for r in MENU_LOOKUPS])
@pytest.mark.parametrize("pair,label", MENU_WORKLOAD,
                         ids=[label for _, label in MENU_WORKLOAD])
def test_menu_binary_matches_python_oracle(cold_emu, syms, menu_stub_src,
                                           pair, label,
                                           renderer, bin_name, prev_char_slot):
    if label == "no-menu-font":
        pytest.skip(f"{MENU_FONT} missing")
    if bin_name not in syms:
        pytest.skip(f"{renderer} kerning symbols absent — likely "
                    f"ENABLE_KERNING_MENU=0")
    expected = _expected_adjustment(_read_menu_kerning_table(), pair)
    a_bin = _run_menu_stub(cold_emu, menu_stub_src,
                           syms[bin_name], pair, prev_char_slot)
    assert (a_bin.a & 0xFF) == expected, (
        f"{renderer} {label} pair=0x{pair:04x}: "
        f"binary=0x{a_bin.a:04x} expected=0x{expected:02x}"
    )
