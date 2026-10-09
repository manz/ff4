"""
Names baked into small-VWF tiles at build time (utils/bake_names.py): each blob holds every name's 2bpp tiles,
its table one entry per name, (offset in the blob, tile count). A blob stays inside one LoROM bank, so a name's
tiles are one DMA from ROM.
"""
; One pool per bank: a816 1.1.0rc1 checks the bus map (E0317) against a floating alloc's provisional,
; pre-link start, which falls outside the window once a two-bank pool's allocs pass the first bank (reported).
.pool baked_spells {
    range 0x2F8000 0x2FFFFF
    strategy order
}
.pool baked_items {
    range 0x308000 0x30FFFF
    strategy order
}

.alloc spell_names_vwf in baked_spells {
    .incbin "spell_names_vwf.dat"
}
.alloc spell_names_vwf_tbl in baked_spells {
"""Per spell id: word offset in spell_names_vwf, byte tile count, byte 0."""
    .incbin "spell_names_vwf.tbl"
}

.alloc item_names_vwf in baked_items {
    .incbin "item_names_vwf.dat"
}
.alloc item_names_vwf_tbl in baked_items {
"""Per item id: word offset in item_names_vwf, byte tile count, byte 0."""
    .incbin "item_names_vwf.tbl"
}
