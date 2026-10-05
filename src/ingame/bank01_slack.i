"""Bank-$01 slack pool ($01:FF35-$01:FFFF), shared by the modules that place code there."""
.pool bank01_slack {
    range 0x01ff35 0x01ffff
    strategy order
}
