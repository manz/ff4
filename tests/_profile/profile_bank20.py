"""Profile bank-20 reloc module to inspect dma_transfer fire rate."""
import sys
sys.path.insert(0, "tests")
from kintsuki import Button
from _ff4kintsuki import kss_path, load_emu_from_kss, tap

e = load_emu_from_kss(kss_path("ff4-battle.kss"))
e.run_frames(30)
tap(e, Button.A, gap=30)
e.run_frames(60)

e.profile_start(lo=0x209900, hi=0x20A000)
e.run_frames(60)
stats = e.profile_stop()
for s in sorted(stats, key=lambda x: -x.calls)[:15]:
    print(f"${s.pc:08X} calls={s.calls:5} incl={s.incl_cycles:10} excl={s.excl_cycles:10}")
e.close()
