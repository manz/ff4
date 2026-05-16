"""Profile the battle VWF blit path with all redraw gates forced dirty.

Loads ff4-battle-ext.kss at the Battle_ext seed point, pokes every
redraw-gate dirty bit so DrawCharNames + DrawMonsterNames + DrawCmd
fire on every profiled frame, then runs `profile_start` scoped to the
display_char neighbourhood in bank $20 and reports per-function call
counts + inclusive / exclusive cycles.

Use as the A/B baseline before/after VWF optimisations:

    python3 tests/_profile/profile_battle_vwf.py > /tmp/vwf.before
    # ... apply change, rebuild ...
    python3 tests/_profile/profile_battle_vwf.py > /tmp/vwf.after
    diff /tmp/vwf.before /tmp/vwf.after
"""
import sys

sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

PROFILE_FRAMES = 60
WARMUP_FRAMES = 30

# Pull display_char neighbourhood from build/ff4.sym so the bench
# follows allocator address shifts.
SYM = {}
for line in open("build/ff4.sym"):
    parts = line.strip().split(" ", 1)
    if len(parts) != 2:
        continue
    bank, _, off = parts[0].partition(":")
    try:
        SYM[parts[1]] = (int(bank, 16) << 16) | int(off, 16)
    except ValueError:
        pass


def label(pc: int) -> str:
    near = max((p for p in SYM.values() if p <= pc), default=None)
    if near is None:
        return f"0x{pc:06x}"
    name = next(n for n, p in SYM.items() if p == near)
    return name if pc == near else f"{name}+0x{pc - near:x}"


display_char = SYM["battle_render.display_char"]

# Scope: 4 KB around display_char captures the whole blit + kerning
# tail without dragging in unrelated bank-20 callers.
lo = display_char & ~0xFFF
hi = lo + 0x1000


def force_redraw(emu):
    emu.write(0x7EEF9A, 0xFF)  # battle_menu_dirty: chars + cmd + status
    emu.write(0x7EEF9B, 0xFF)  # battle_monster_dirty: all monster slots
    emu.write(0x703C01, 0xFF)  # region_dirty_bits: slice-2 queue


def run():
    emu = load_emu_from_kss(kss_path("ff4-battle-ext.kss"), settle_frames=0)
    force_redraw(emu)
    emu.run_frames(WARMUP_FRAMES)
    force_redraw(emu)
    emu.profile_start(lo=lo, hi=hi)
    for _ in range(PROFILE_FRAMES):
        emu.run_frames(1)
        force_redraw(emu)
    stats = emu.profile_stop()
    emu.close()
    return stats


def main():
    stats = run()
    incl_total = sum(s.incl_cycles for s in stats)
    excl_total = sum(s.excl_cycles for s in stats)
    print(f"Scope: 0x{lo:06x}..0x{hi:06x}")
    print(f"Frames profiled: {PROFILE_FRAMES}  (warmup: {WARMUP_FRAMES})")
    print(f"Functions captured: {len(stats)}")
    print(f"Total inclusive cycles: {incl_total:,}")
    print(f"Total exclusive cycles: {excl_total:,}")
    print()
    print(f"{'function':<48} {'calls':>8} {'incl':>12} {'excl':>12} {'avg/call':>10}")
    print("-" * 96)
    for s in sorted(stats, key=lambda x: -x.excl_cycles)[:20]:
        avg = s.excl_cycles // max(1, s.calls)
        print(f"{label(s.pc):<48} {s.calls:>8} {s.incl_cycles:>12} {s.excl_cycles:>12} {avg:>10}")


if __name__ == "__main__":
    main()
