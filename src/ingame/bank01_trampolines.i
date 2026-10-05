"""Bank-$01 trampoline pool, shared by every module that places code in the reclaimed $01:EBD2 space."""
.pool bank01_trampolines {
    range 0x01ebd2 0x01ff34
    strategy order
}
