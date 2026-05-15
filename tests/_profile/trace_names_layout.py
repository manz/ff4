"""Dump char-name tilemap buffer $BEC2 to discover per-slot byte layout."""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

e = load_emu_from_kss(kss_path("ff4-battle-ext.kss"), settle_frames=0)
e.run_frames(120)

# $74FD = text buffer (input to VWF), built by UpdateCharNames
# $BEC2 = tilemap dest (output, copied to BG layer by DrawMainMenuText)
# width = $0C (12) bytes per row, height = $0A (10) rows
print("== text buffer $74FD (input) ==")
text = bytes(e.read_range(0x7E74FD, 80))
print("  hex:", text.hex())
print()
print("== tilemap $BEC2 (output, 12-wide x 10-tall) ==")
for row in range(10):
    rdata = bytes(e.read_range(0x7EBEC2 + row * 0x40, 12))
    print(f"  row {row}: {rdata.hex()}")
print()
print("== active char $1822 ==", hex(e.read(0x7E1822)))

# Rotate to slot 1, see what changes
e.write(0x7E1822, 0x01)
e.write(0x7E00D0, 0x01)
e.write(0x7EEF9A, 0xFF)  # force re-render
e.run_frames(2)
print()
print("== after $1822 := 1, +2 frames ==")
for row in range(10):
    rdata = bytes(e.read_range(0x7EBEC2 + row * 0x40, 12))
    print(f"  row {row}: {rdata.hex()}")

e.close()
