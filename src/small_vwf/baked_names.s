"""
Names baked into small-VWF tiles at build time (utils/bake_names.py): each blob holds every name's 2bpp tiles,
its table one entry per name, (offset in the blob, tile count). A blob stays inside one LoROM bank, so a name's
tiles are one DMA from ROM.
"""
.pool baked_text {
    range 0x2F8000 0x2FFFFF
    range 0x308000 0x30FFFF
    strategy pack
}

.alloc spell_names_vwf in baked_text {
    .incbin "spell_names_vwf.dat"
}
.alloc spell_names_vwf_tbl in baked_text {
"""Per spell id: word offset in spell_names_vwf, byte tile count, byte 0."""
    .incbin "spell_names_vwf.tbl"
}
