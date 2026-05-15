"""Dump full $B966 region to find actual slot stride."""
import sys
sys.path.insert(0, "tests")
import ctypes
from pathlib import Path
from kintsuki import Emu
from _ff4kintsuki import ROM

KSS = Path("/Users/manz/PyCharmProjects/ff4-modules/ff4-battle-full-party.kss")
e = Emu(load_srm_sidecar=False)
e.load_rom(str(ROM))
blob = KSS.read_bytes()
buf = (ctypes.c_uint8 * len(blob))(*blob)
from kintsuki._native import lib
lib.kintsuki_load_state(e._handle, buf, len(blob))
e.run_frames(120)

print("$B966..$B9DE (char-name region, 120 bytes), 16 bytes/line:")
for off in range(0, 0x78, 16):
    row = bytes(e.read_range(0x7EB966 + off, 16))
    print(f"  +${off:02X}: {row.hex()}")
e.close()
