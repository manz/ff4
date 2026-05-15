"""Trace cmd-window DMA path: dirty bits, pending mask, $1822, VRAM."""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

e = load_emu_from_kss(kss_path("ff4-battle-ext.kss"), settle_frames=0)

def snap(label):
    cmd_dirty = e.read(0x7EEF9A)
    tile_pending = e.read(0x703C00)
    map_pending = e.read(0x703C03)
    char_slot = e.read(0x7E1822)
    flag1824 = e.read(0x7E1824)
    vram_chunk = bytes(e.vram_read_range(0x71C0 * 2, 16))
    cmd_buf = bytes(e.read_range(0x7E9DA7, 60))      # bank-20 inner output (5 rows x 12)
    r0 = bytes(e.read_range(0x7EC1F2, 12))
    r1 = bytes(e.read_range(0x7EC1F2 + 0x40, 12))
    r2 = bytes(e.read_range(0x7EC1F2 + 0x80, 12))
    wram_chunk = r0 + b"|" + r1 + b"|" + r2
    tile_data = bytes(e.vram_read_range(0xB000, 32)) # VWF tiles
    print(f"[{label:>14}] "
          f"$EF9A={cmd_dirty:02X} "
          f"$3C00={tile_pending:02X} $3C03={map_pending:02X} "
          f"$1822={char_slot:02X}")
    print(f"  VRAM tilemap $E380: {vram_chunk.hex()}")
    print(f"  WRAM $9DA7 (inner): {cmd_buf.hex()}")
    print(f"  WRAM $C1F2 (final): {wram_chunk.hex()}")
    print(f"  VRAM tiles $B000:   {tile_data.hex()}")

snap("init")
# Run many frames to settle into battle main loop.
for i in [10, 60, 120, 240]:
    e.run_frames(i)
    snap(f"+{i}f")
# Force dirty + run more.
e.write(0x7EEF9A, 0xFF)
snap("forced")
e.run_frames(2)
snap("post2")

e.close()
