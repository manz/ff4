"""
Names baked into small-VWF tiles at build time (utils/bake_names.py): each blob holds every name's 2bpp tiles,
its table one entry per name, (offset in the blob, tile count). A blob stays inside one LoROM bank, so a name's
tiles are one DMA from ROM.
"""
.pool baked_names {
    range 0x2F8000 0x30FFFF
    strategy order
}

.alloc spell_names_vwf in baked_names {
    .incbin "spell_names_vwf.dat"
}
.alloc spell_names_vwf_tbl in baked_names {
"""Per spell id: word offset in spell_names_vwf, byte tile count, byte 0."""
    .incbin "spell_names_vwf.tbl"
}

.alloc item_names_vwf in baked_names {
    .incbin "item_names_vwf.dat"
}
.alloc item_names_vwf_tbl in baked_names {
"""Per item id: word offset in item_names_vwf, byte tile count, byte 0."""
    .incbin "item_names_vwf.tbl"
}

.alloc monster_names_vwf in baked_names {
    .incbin "monster_names_vwf.dat"
}
.alloc monster_names_vwf_tbl in baked_names {
"""Per monster id: word offset in monster_names_vwf, byte tile count, byte 0."""
    .incbin "monster_names_vwf.tbl"
}

.alloc command_names_vwf in baked_names {
    .incbin "command_names_vwf.dat"
}
.alloc command_names_vwf_tbl in baked_names {
"""Per battle command id: word offset in command_names_vwf, byte tile count, byte 0."""
    .incbin "command_names_vwf.tbl"
}
