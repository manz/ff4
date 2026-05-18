"""Trace char-name palette patch on slot rotation."""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

e = load_emu_from_kss(kss_path("ff4-battle.kss"), settle_frames=0)
e.run_frames(120)

def dump_b966():
    print("  WRAM $B966 (each slot 24 bytes = 12 entries):")
    for slot in range(5):
        row = bytes(e.read_range(0x7EB966 + slot * 0x40, 24))
        print(f"    slot {slot}: {row.hex()}")
    print("  WRAM $BEA6 (TfrMainMenu src, 12 entries x 10 rows):")
    for row in range(5):
        rdata = bytes(e.read_range(0x7EBEA6 + row * 0x40, 24))
        print(f"    row {row}: {rdata.hex()}")
    # VRAM word $7020 = byte $E040; main menu tilemap dest
    print("  VRAM $E040 (main menu tilemap, 24 bytes):")
    print(f"    {bytes(e.vram_read_range(0xE040, 48)).hex()}")
    print(f"  $1822 = {e.read(0x7E1822):02X}")

print("== settled ==")
dump_b966()

# Force a slot rotation by calling the writer site directly via WRAM poke
print("\n== rotate to slot 2 ==")
e.write(0x7E1822, 0x02)
e.write(0x7E00D0, 0x02)
# Fire writer manually: just trigger one of the call paths
# Simpler: trigger writer via $03:A482 path — push a value and let the
# next ATB-queue event fire. For now, just write $1822 + flag dirty,
# the writer hook would normally do the palette walk.
# Run a few frames so any deferred render fires:
e.run_frames(3)
dump_b966()

e.close()
