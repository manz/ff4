"""Trace battle init: $1822, $B966 palette bits, dirty bits over time."""
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

def slot_pal_bytes(slot):
    # Each char slot occupies 24 bytes ; ($34) mirror at slot*24+12, real names.
    # Hi byte at offsets +13, +15, +17, +19, +21, +23 = palette bits.
    base = 0x7EB966 + slot * 24 + 12
    return [e.read(base + 2*i + 1) for i in range(6)]

def snap(label):
    s1822 = e.read(0x7E1822)
    dirty = e.read(0x7EEF9A)
    region = e.read(0x703C01)
    pals = [slot_pal_bytes(s) for s in range(5)]
    print(f"[{label:>10}] $1822={s1822:02X} EF9A={dirty:02X} reg_dirty={region:02X}")
    for s, pal in enumerate(pals):
        active = "*" if s == s1822 else " "
        print(f"  {active}slot {s} pal hi bytes: {[f'{b:02X}' for b in pal]}")

snap("boot")
for step in [1, 4, 25, 30, 60]:
    e.run_frames(step)
    snap(f"+step")
snap("settled")
e.close()
