"""Trace UpdateFlyingHDMA preconditions at kss boot."""
import sys
sys.path.insert(0, "tests")
from _ff4kintsuki import kss_path, load_emu_from_kss

e = load_emu_from_kss(kss_path("ff4-battle.kss"), settle_frames=0)

def snap(label):
    ed4e = e.read(0x7EED4E)
    f353 = e.read(0x7EF353)
    f1813 = e.read(0x7E1813)
    sa1 = bytes(e.read_range(0x7E7614, 8)).hex()
    sa2 = bytes(e.read_range(0x7E76A0, 8)).hex()
    print(f"[{label:>8}] $ED4E={ed4e:02X} (bit6={(ed4e&0x40)!=0}) $F353={f353:02X} $1813={f1813:02X}")
    print(f"            HDMA $7614: {sa1} | $76A0: {sa2}")

snap("boot")
e.run_frames(1)
snap("+1f")
e.run_frames(10)
snap("+11f")
e.run_frames(60)
snap("+71f")
e.close()
