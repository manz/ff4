"""
Bank-$01 free space, shared by the modules that place code there: the end of the bank, and the bodies of vanilla
routines ff4 replaced, which now start with a jump out and are never reached past it (nothing else branches in).
"""
.pool bank01_slack {
    range 0x01ff35 0x01ffff
    range 0x0183B5 0x0183E2
    range 0x018401 0x018416
    range 0x01841A 0x018456
    range 0x01857D 0x01858B
    range 0x018FE8 0x019000
    range 0x01B30C 0x01B36C
    range 0x01B41D 0x01B425
    strategy order
}
