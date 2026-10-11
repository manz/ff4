"""
Bank-$01 trampoline pool: the 400 bytes the relocated InitScrollHDMA left ($01:EBD2-$01:ED61). Past them is vanilla
battle-animation code (btlgfx_code3: SetMonsterScroll, TeleportPalAnim, special and summon animations, to $01:FF34)
that battle still `jsl`s.
"""
.pool bank01_trampolines {
    range 0x01ebd2 0x01ed61
    strategy order
}
