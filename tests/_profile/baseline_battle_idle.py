"""Baseline cycle profile of the battle redraw chain over 60 frames idle."""
import sys
sys.path.insert(0, "tests")
from kintsuki import Button
from _ff4kintsuki import kss_path, load_emu_from_kss, tap

# Load symbol table for human-readable PC names
SYM = {}
for line in open("build/ff4.sym"):
    line = line.strip()
    if not line or ':' not in line:
        continue
    addr, _, name = line.partition(' ')
    bank, _, off = addr.partition(':')
    try:
        snes_pc = (int(bank, 16) << 16) | int(off, 16)
        SYM[snes_pc] = name
    except ValueError:
        pass

def label(pc: int) -> str:
    if pc in SYM:
        return SYM[pc]
    # nearest symbol <= pc
    nearest = max((p for p in SYM if p <= pc), default=None)
    if nearest is None:
        return ""
    delta = pc - nearest
    return f"{SYM[nearest]}+{delta:#x}" if delta else SYM[nearest]


e = load_emu_from_kss(kss_path("ff4-battle.kss"))
e.run_frames(30)
tap(e, Button.A, gap=30)  # open inventory
e.run_frames(60)           # settle

# Scope to bank $02 only (battle gfx code)
e.profile_start(lo=0x028000, hi=0x02FFFF)
cycles_pre = e.cpu_cycles
e.run_frames(60)
cycles_post = e.cpu_cycles
stats = e.profile_stop()

window_cycles = cycles_post - cycles_pre
print(f"Window: {window_cycles:,} CPU cycles over 60 frames")
print(f"Per frame: {window_cycles // 60:,} cycles  (NMI deadline ≈ ~357k @ 21.477 MHz / 60 fps)")
print(f"Functions profiled: {len(stats)}")
print()
print(f"{'PC':>10}  {'name':<46}  {'calls':>6}  {'incl':>10}  {'excl':>10}  {'avg':>8}")
print("-" * 105)
stats_sorted = sorted(stats, key=lambda s: -s.excl_cycles)
for s in stats_sorted[:25]:
    nm = s.name or label(s.pc) or "?"
    avg = s.excl_cycles // max(1, s.calls)
    print(f"${s.pc:08X}  {nm[:46]:<46}  {s.calls:>6}  {s.incl_cycles:>10}  {s.excl_cycles:>10}  {avg:>8}")

e.close()
