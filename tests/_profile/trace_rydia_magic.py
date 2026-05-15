"""Dump Rydia magic-list data + render with each offset to compare."""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

from pathlib import Path
KSS = Path("/Users/manz/PyCharmProjects/ff4-modules/ff4-battle-full-party.kss")
import ctypes
from kintsuki import Emu
from _ff4kintsuki import ROM
e = Emu(load_srm_sidecar=False)
e.load_rom(str(ROM))
adbg = ROM.parent / "ff4.ips.adbg"
if adbg.exists():
    e.load_adbg(str(adbg))
blob = KSS.read_bytes()
buf = (ctypes.c_uint8 * len(blob))(*blob)
from kintsuki._native import lib
assert lib.kintsuki_load_state(e._handle, buf, len(blob)) == 1
e.run_frames(180)

print("Party slots ($1f80..$1f84 = char ids):")
for i in range(5):
    print(f"  slot {i}: char_id ${e.read(0x7E1F80 + i):02X}")
print()

# dump all 5 char slots' magic data
for slot in range(5):
    base = 0x7E2C7A + slot * 0x120
    print(f"slot {slot} spell list at ${base:06X}:")
    print(f"  white  : {bytes(e.read_range(base + 0x00, 0x20)).hex()}")
    print(f"  black  : {bytes(e.read_range(base + 0x60, 0x20)).hex()}")
    print(f"  summon : {bytes(e.read_range(base + 0xC0, 0x20)).hex()}")
print()
print("  white  (offset $00..$5F):")
print("    " + bytes(e.read_range(base + 0x00, 0x60)).hex())
print("  black  (offset $60..$BF):")
print("    " + bytes(e.read_range(base + 0x60, 0x60)).hex())
print("  summon (offset $C0..$11F):")
print("    " + bytes(e.read_range(base + 0xC0, 0x60)).hex())
print()
print(f"$1822 active char = {e.read(0x7E1822):02X}")
print(f"$ef93 magic offset = {e.read(0x7EEF93):02X}")
print(f"$1823 menu update = {e.read(0x7E1823):02X}")
print(f"$4A menu flags = {e.read(0x7E004A):02X}")
e.close()
