"""Vanilla ff4.sfc profile baseline (boot + title screen NMI cost).

Run with `build/ff4.ips` temporarily moved aside to suppress auto-patch.
Kss savestates are tied to the patched ROM and won't load against
vanilla; this boots fresh and profiles 60 frames during title intro.
"""
import sys
sys.path.insert(0, "tests")
import ctypes
from pathlib import Path
from kintsuki import Emu

REPO = Path(__file__).resolve().parents[1].parents[0]
ROM = REPO / "build/ff4j.sfc"  # vanilla JP ROM dropped by user

e = Emu(load_srm_sidecar=False)
e.load_rom(str(ROM))
# Vanilla-side breaked-at-$03:8000 kss
KSS = Path("/Users/manz/PyCharmProjects/ff4-modules/ff4j-battle-ext.kss")
blob = KSS.read_bytes()
buf = (ctypes.c_uint8 * len(blob))(*blob)
from kintsuki._native import lib
assert lib.kintsuki_load_state(e._handle, buf, len(blob)) == 1
e.run_frames(120)  # let battle settle

e.profile_start(lo=0x000000, hi=0xFFFFFF)
e.run_frames(60)
stats = e.profile_stop()
for s in sorted(stats, key=lambda x: -x.excl_cycles)[:20]:
    print(f"${s.pc:08X} calls={s.calls:5} incl={s.incl_cycles:10} excl={s.excl_cycles:10}")
e.close()
