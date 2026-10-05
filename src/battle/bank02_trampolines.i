"""
Bank-$02 trampoline pool ($98FF-$9982, freed by the rolling inventory list), shared by the modules that
place code there.
"""
.pool bank02_trampolines {
    range 0x0298ff 0x029982
    strategy order
}
