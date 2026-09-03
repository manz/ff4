"""Trace CPU until STP to find where it drifts."""
import sys
sys.path.insert(0, "tests")
import ctypes
from kintsuki import Emu
from _ff4kintsuki import ROM, kss_path

KSS = kss_path("ff4-battle.kss")
e = Emu(load_srm_sidecar=False)
e.load_rom(str(ROM))
blob = KSS.read_bytes()
buf = (ctypes.c_uint8 * len(blob))(*blob)
from kintsuki._native import lib
lib.kintsuki_load_state(e._handle, buf, len(blob))

# Run until STP or 600 frames, then dump tail of trace.
e.tracer_start(0x000000, 0xFFFFFF, ring_capacity=65536)
stopped = e.run_until_stp(max_frames=300)
trace = e.tracer_drain()
print(f"STP hit: {stopped}")
# Find first BRK in trace, print 40 lines around it
lines = trace.splitlines()
brk_idx = None
for i, l in enumerate(lines):
    if "brk #$" in l and "$20:b03" in l.lower():
        brk_idx = i
        break
if brk_idx:
    start = max(0, brk_idx - 30)
    print(f"==== First BRK at line {brk_idx} ; context: ====")
    print("\n".join(lines[start:brk_idx + 5]))
else:
    print("No BRK found. Last 40 lines:")
    print("\n".join(lines[-40:]))
e.close()
