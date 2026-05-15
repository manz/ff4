"""Bench NMI cost by aggregating known-callee inclusive cycles.

NMI is interrupt-driven so a single profile_start on the handler PC
won't catch it. Instead sum the inclusive cycles of each function
the NMI body invokes ; result = upper bound on NMI cycle cost per
60-frame window. Divide by 60 for per-NMI average.
"""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

# NMI callees in order from BattleNMI body @8365 onwards
NMI_CALLEES = {
    0x209920: "messages_vwf.dma_transfer (incl TfrSprites tail)",
    0x03FEBE: "TfrPal",
    0x02831B: "TfrShadowGfx",
    0x029286: "TfrAnimGfx",
    0x029433: "TfrMenuTilesUpdate",
    0x028302: "SetFlyingHDMA (added NMI hook)",
}

e = load_emu_from_kss(kss_path("ff4-battle-ext.kss"))
e.run_frames(60)

e.profile_start(lo=0x000000, hi=0xFFFFFF)
e.run_frames(60)
stats = e.profile_stop()
e.close()

print(f"{'Callee':<48} {'calls':>6} {'incl':>10} {'avg/NMI':>10}")
print("-" * 80)
total = 0
for s in sorted(stats, key=lambda x: -x.incl_cycles):
    if s.pc in NMI_CALLEES:
        avg = s.incl_cycles // max(1, s.calls)
        print(f"{NMI_CALLEES[s.pc]:<48} {s.calls:>6} {s.incl_cycles:>10} {avg:>10}")
        total += s.incl_cycles

print("-" * 80)
print(f"{'TOTAL NMI work (60 frames)':<48} {'':>6} {total:>10} {total//60:>10}")
print()
print("vblank window ~1900 CPU cycles ; 1 frame ~357K")
print(f"per-NMI avg : {total // 60:,} CPU cycles")
print(f"per-frame % : {(total // 60) * 100 / 357000:.1f}% of 1-frame budget")
