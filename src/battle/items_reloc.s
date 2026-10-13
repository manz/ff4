"""
Battle inventory buffer layout: relocated buffer base + size constants for the expanded 12-byte item names
(9 bytes in vanilla).
"""
.import "core/wram_layout"
; Text ring buffer: 6 slots (5 visible + 1 pre-render) x 60 bytes, vanilla 48 items x 48 bytes.
; Slot = 30 tiles x 2 bytes: bytes 0-29 dakuten/attribute row, 30-59 main row.
; Row of 15 tiles: [symbol:1][name:11][colon:1][tens:1][ones:1]

item_buffer_base := 0x97A6  ; Ring buffer in freed spell list buffer 1
item_buffer_stride := 60  ; Bytes per slot (vanilla 48)
item_buffer_slots := 6  ; Ring buffer slots (5 visible + 1 pre-render)
item_buffer_size := sizeof(battle_item_text_ring)
item_line2_offset := 30  ; Offset to second tilemap row within slot

; Tilemap staging buffer at $C4E6: tilemap row 64 bytes, inventory row 128 bytes (2 tilemap rows)
tilemap_row_stride := 128  ; Bytes per inventory row ($80)
tilemap_left_start := 0xC52A  ; Left column start (original base)
tilemap_right_start := 0xC546  ; Right column start

; Equipped items buffer, relocated from $BC86 to freed magic buffer space for 15-tile names.
; Per character (120 bytes): bytes 0-59 left hand, 60-119 right hand.

equip_buffer_base := 0x9A00  ; Equipped items buffer base
equip_buffer_stride := 0x78  ; 120 bytes per character
equip_item_stride := 0x3C  ; 60 bytes per item

; VRAM transfer entries (overlapping; HDMA scroll picks the visible part):
; 3: $C4E6 -> VRAM $7400, $0400 bytes; 4: $C8E6 -> $7600, $0400; 5: $CCE6 -> $7C00, $0440
