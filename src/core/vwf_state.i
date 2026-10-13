"""
Shared VWF state addresses: the CHR buffer and the VRAM save window.

The battle message renderer and the menu small-VWF renderer both build glyph CHR in the $70:3000 buffer; they never
run at the same time. vwf_cfg and vwf_engine are reserved in vwf_ram.s.
"""


VWF_CHR_BUFFER := 0x703000
; Field items: 11 slots * K=10 from $100 end at $16D, drops at $1A9.
VWF_CHR_BUFFER_SIZE := 0x1F00  ; tiles $000..$1EF; BATTLE_FLAGS follows

; Battle render gate bytes must stay outside VWF_CHR_BUFFER: battle inventory slot CHR runs from $70:3C00 + N * 160,
; and glyph pixels over those flags stop the names / monsters regions from ever flushing again. They live at
; $70:7100 (battle/render_state.s).

; Primary flush source: field items start at tile $100, $1000 bytes into the buffer.
VWF_CHR_FLUSH_OFFSET := 0x100 * 0x10

; VRAM saved before a dialog and restored on close: word $2800..$37FF = byte $5000..$6FFF (8 KB), covering the
; field-menu CHR ($5000..$5FFF) with room to spare.
VRAM_SAVE_BASE_WORD := 0x2800
VRAM_SAVE_BYTE_COUNT := 0x2000
VRAM_SAVE_SRAM_BASE := 0x705000
