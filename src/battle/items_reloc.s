; ============================================================================
; Battle Inventory Buffer Layout
; ============================================================================
;
; Defines buffer sizes and addresses for the expanded 12-byte item names.
; Original FF4 uses 9-byte item names; we expand to 12 for translations.
;
; ============================================================================

; ============================================================================
; TEXT BUFFER ($8EA6) - RING BUFFER
; ============================================================================
;
; The text buffer holds formatted tile data for inventory items.
; With the circular/ring buffer, we only need 6 slots (5 visible + 1 pre-render).
;
; Original layout: 48 items × 48 bytes = 2304 bytes ($8EA6-$97A5)
; Ring buffer layout: 6 slots × 60 bytes = 360 bytes ($8EA6-$900D)
;

; Per-slot layout (60 bytes = 30 tiles × 2 bytes per tile):
;   Bytes  0-29: Tilemap row 1 (dakuten/attribute row)
;   Bytes 30-59: Tilemap row 2 (main character row)
;

; Tile layout per row (15 tiles):
;   [symbol:1][name:11][colon:1][tens:1][ones:1] = 15 tiles

item_buffer_base := 0x97A6  ; Ring buffer in freed spell list buffer 1
item_buffer_stride := 60  ; Bytes per slot (was 48)
item_buffer_slots := 6  ; Ring buffer slots (5 visible + 1 pre-render)
item_buffer_size := 360  ; Total buffer size (6 × 60)
item_line2_offset := 30  ; Offset to second tilemap row within slot

; ============================================================================
; TILEMAP BUFFER ($C4E6)
; ============================================================================
;
; The tilemap buffer is the staging area before VRAM transfer.
; Each inventory row uses 2 tilemap rows (128 bytes total).
;

; Layout:
;   $C4E6: Start of inventory tilemap buffer
;   $C52A: Left column content ($C4E6 + $44 = row 1, column 2)
;   $C546: Right column content ($C4E6 + $60 = row 1, column 16)
;
; Tilemap row = 64 bytes (32 tiles × 2 bytes)
; Inventory row = 128 bytes (2 tilemap rows)

;tilemap_buffer_base     := 0xC4E6   ; Tilemap buffer base
tilemap_row_stride := 128  ; Bytes per inventory row ($80)
tilemap_left_start := 0xC52A  ; Left column start (original base)
tilemap_right_start := 0xC546  ; Right column start

; ============================================================================
; EQUIPPED ITEMS BUFFER ($9A00)
; ============================================================================
;
; Relocated from $BC86 to freed magic buffer space.
; Expanded to hold 15-tile item names.
;

; Layout per character (120 bytes):
;   Bytes  0-59:  Equipped item 1 (left hand)
;   Bytes 60-119: Equipped item 2 (right hand)

equip_buffer_base := 0x9A00  ; Equipped items buffer base
equip_buffer_stride := 0x78  ; 120 bytes per character
equip_item_stride := 0x3C  ; 60 bytes per item

; ============================================================================
; VRAM LAYOUT
; ============================================================================
;

; The inventory tilemap is transferred to VRAM in 3 chunks:
;
; Entry 3: $C4E6 → VRAM $7400, $0400 bytes (16 tilemap rows = 8 inv rows)
; Entry 4: $C8E6 → VRAM $7600, $0400 bytes (16 tilemap rows = 8 inv rows)
; Entry 5: $CCE6 → VRAM $7C00, $0440 bytes (17 tilemap rows = 8.5 inv rows)
;
; Note: VRAM regions overlap because entries cover different scroll ranges.
; HDMA scrolling reveals different portions of the 24-row inventory.
