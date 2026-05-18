"""Dump WRAM tile buffer + inventory slot tilemap-buffer to text for
visual inspection. Loads battle-ext, opens inventory, snapshots."""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, "tests")
from kintsuki import Button
from _ff4kintsuki import kss_path, load_emu_from_kss, tap

OUT = Path(__file__).parent / "dumps" / "inv_sram.hex"
OUT.parent.mkdir(exist_ok=True)


def dump_region(emu, label: str, start: int, length: int) -> str:
    rows = []
    rows.append(f"=== {label}  ${start:06x}..${start+length-1:06x} ({length}B) ===")
    for off in range(0, length, 16):
        addr = start + off
        bytes_ = " ".join(f"{emu.read(addr + i):02x}" for i in range(16))
        ascii_ = "".join(
            chr(b) if 32 <= b < 127 else "."
            for b in (emu.read(addr + i) for i in range(16))
        )
        rows.append(f"{addr:06x}: {bytes_}  {ascii_}")
    return "\n".join(rows)


def main() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle.kss"), settle_frames=600)
    tap(emu, Button.DOWN, gap=20)
    tap(emu, Button.DOWN, gap=20)
    tap(emu, Button.A, gap=60)

    out = []
    # Inventory rolling-buffer tilemap entries (6 slots * 60 bytes)
    out.append(dump_region(emu, "rolling slots ($7E97A6)", 0x7E97A6, 6 * 60))
    # VWF tile CHR staging
    out.append(dump_region(emu, "vwf buffer head (msg/mon/names)", 0x703000, 0x600))
    out.append(dump_region(emu, "vwf buffer mid (cmd)", 0x703900, 0x300))
    out.append(dump_region(emu, "vwf buffer tail (inventory)", 0x703C00, 0x300))
    out.append(dump_region(emu, "vwf gate state", 0x703F00, 0x10))
    # Allocator state
    out.append(dump_region(emu, "allocator", 0x702F00, 0x10))
    # Format buffer used by inventory render
    out.append(dump_region(emu, "inv_format_buffer ($7E9E66)", 0x7E9E66, 0x40))
    # Mode flag DP $37
    out.append(dump_region(emu, "mode flag $37", 0x7E0030, 0x10))
    OUT.write_text("\n\n".join(out))
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
