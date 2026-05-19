

"""
Key-item picker rolling buffer (single column).

Triggered from event scripts via EventCmd_f7 ($00:ED96), which routes
through ShowItemWindow ($01:B354 in the disassembly). Original renders
the filtered key-item list (`InitItemList`, $01:B2D3) as a 4x4 grid
on BG3, animated open/close via an IRQ-driven slide. We collapse
that to a single-column rolling buffer driven by the shared engine.

Item source: $7E:0712, the filtered Item-array buffer (96 bytes / 48
slots). InitItemList copies entries from $1440 whose IDs fall in
[$CE..$E6] ∪ [$EB..$FD], i.e. key items + a few specials. Realistic
player counts cap at ~10-15 distinct key items  ; the rolling buffer
is sized for 6 visible / 7 buffer slots / 16 total cap.

The picker is mutually exclusive with the field menu and the treasure
menu, so it can reuse HDMA channel 5 (the field-menu BG1 channel)
once we route it onto BG3 like the other picker profiles. Sliding
open/close is replaced by the engine's scroll state machine  ; original
IRQ handler at $01:B0CF can be NOP'd out under TREASURE_INVENTORY_ROLLING.

Wiring (TODO, separate commit):
  - Replace the 4x4 grid render in ShowItemWindow with key_item_init.
  - Port InitItemList into the engine's pre-init filter step.
  - Drop the IRQ slide animation  ; rely on the engine's scroll states.
  - Trigger entry via either a user-supplied event savestate or the
    TREASURE_DEBUG_TRIGGER_KEY_ITEM_F7 flag described in the plan.

State RAM layout (12 bytes from $1BF0, struct: RollingBufferState):
  $1BF0  top_row
  $1BF1  buffer_pos
  $1BF2  edge_row
  $1BF3  slot_index
  $1BF4  base_scroll (word)
  $1BF6  hdma_enable
  $1BF7  _pad
  $1BF8  scroll_state
  $1BF9  scroll_remaining
  $1BFA  scroll_direction
  $1BFB  transfer_pending
  $1BFC  scroll_anim_offset (word)
  $1BFE  hdma_copy_pending
"""


KEY_ITEM_VISIBLE_ITEMS := 6
KEY_ITEM_BUFFER_SLOTS := 7
KEY_ITEM_TOTAL_ITEMS := 48
KEY_ITEM_SCROLL_LIMIT := 42
KEY_ITEM_SCROLL_PIXELS_PER_FRAME := 8
KEY_ITEM_SCROLL_TOTAL_PIXELS := 16

; Key-item picker state moved out of $1B00-$1BFF to clean $7E:9C60 for
; the same reason as treasure ($9C00) + drops ($9C30) : engine path
; needs 35 bytes per instance, $1B00-$1BFF is too small and vanilla
; sprite code stomps past $1BEB.
key_item_rolling := 0x9C60
key_item_rolling_top_row := key_item_rolling + RollingBufferState.top_row
key_item_rolling_buffer_pos := key_item_rolling + RollingBufferState.buffer_pos
key_item_rolling_edge_row := key_item_rolling + RollingBufferState.edge_row
key_item_rolling_slot_index := key_item_rolling + RollingBufferState.slot_index
key_item_rolling_base_scroll := key_item_rolling + RollingBufferState.base_scroll
key_item_hdma_enable := key_item_rolling + RollingBufferState.hdma_enable
key_item_scroll_state := key_item_rolling + RollingBufferState.scroll_state
key_item_scroll_remaining := key_item_rolling + RollingBufferState.scroll_remaining
key_item_scroll_direction := key_item_rolling + RollingBufferState.scroll_direction
key_item_transfer_pending := key_item_rolling + RollingBufferState.transfer_pending
key_item_scroll_anim_offset := key_item_rolling + RollingBufferState.scroll_anim_offset
key_item_hdma_copy_pending := key_item_rolling + RollingBufferState.hdma_copy_pending

key_item_scroll_pos := 0x9C8F

KEY_ITEM_HDMA_TABLE_ADDR := 0x9900
KEY_ITEM_HDMA_TABLE := 0x7E9900
KEY_ITEM_HDMA_SHADOW_ADDR := 0x9940
KEY_ITEM_HDMA_SHADOW := 0x7E9940
KEY_ITEM_HDMA_BANK := 0x7E

KEY_ITEM_FILTER_BUFFER := 0x0712


KEY_ITEM_HDMA_CHANNEL_BIT := 0x10
KEY_ITEM_HDMA4_CTRL := 0x4340
KEY_ITEM_HDMA4_DEST := 0x4341
KEY_ITEM_HDMA4_SRC_LO := 0x4342
KEY_ITEM_HDMA4_SRC_BANK := 0x4344


key_item_ensure_hdma_initialized:
"""
Lazy-capture $9F (BG3VOFS shadow) on first call, stash in base_scroll. HDMA channel enable deferred until the
picker has its own window draw + visible loop wired — leaving ch4 enabled here corrupts the field BG3 layer
(Cecil walks on a split screen) since the engine's RTL goes back to the field via EventCmd_f7 without any
teardown.
"""
    rep #0x20
    lda.w key_item_rolling_base_scroll
    cmp.w #0xFFFF
    bne _key_item_hdma_already_init
    lda.l 0x7E019F
    sta.w key_item_rolling_base_scroll
    sep #0x20
    jsr.w _key_item_init_hdma_channel
    lda #KEY_ITEM_HDMA_CHANNEL_BIT
    sta.l 0x7E1BAE
    sta.w key_item_hdma_enable
    rts

_key_item_hdma_already_init:
    sep #0x20
    rts


_key_item_init_hdma_channel:
"""Configure HDMA ch4: DIRECT mode, dest BG3VOFS ($2112), source = picker shadow table at $7E:9900."""
    php
    sep #0x20
    jsr.w update_key_item_scroll_hdma
    lda #0x02
    sta.l KEY_ITEM_HDMA4_CTRL
    lda #0x12
    sta.l KEY_ITEM_HDMA4_DEST
    rep #0x20
    lda.w #KEY_ITEM_HDMA_TABLE_ADDR
    sta.l KEY_ITEM_HDMA4_SRC_LO
    sep #0x20
    lda #KEY_ITEM_HDMA_BANK
    sta.l KEY_ITEM_HDMA4_SRC_BANK
    plp
    rts


key_item_render_item_to_slot:
"""Render filtered item from $7E:0712 + edge_row*Item.__size into BG3 buffer at $7E:D600 + slot_index*128 + 0x44."""
    php
    phb
    lda #0x7E
    pha
    plb
    rep #0x30
    pha
    phx
    phy
    lda.b 0x5a
    pha
    lda.b 0x29
    pha
    lda.b 0x45
    pha
    lda.b 0x33
    pha
    sep #0x20
    lda.b 0x5d
    pha
    lda.b 0xDB
    pha
    rep #0x20
    lda.w #0xD600
    sta.b 0x29
    sep #0x20
    lda.w key_item_rolling_edge_row
    asl
    clc
    adc #0x12
    sta.b 0x5a
    lda #0x07
    adc #0x00
    sta.b 0x5b
    rep #0x20
    lda.b 0x5a
    tax
    sep #0x20
    lda.l 0x7E0000 + Item.id, x
    pha
    lda.l 0x7E0000 + Item.qty, x
    sta.b 0x5C
    stz.b 0x34
    pla
    jsr.l check_can_use_item_trampoline
    lda.w key_item_rolling_slot_index
    sta.b 0x5d
    rep #0x20
    lda.w key_item_rolling_slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0444
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    pla
    sta.b 0xDB
    pla
    sta.b 0x5d
    rep #0x20
    pla
    sta.b 0x33
    pla
    sta.b 0x45
    pla
    sta.b 0x29
    pla
    sta.b 0x5a
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts


key_item_render_all:
"""
Replacement for original UpdateItemText. Original just clears $0774 (text-buffer scratch) and walks $0712 to lay
out 4x4 grid into the BG3 buffer at $7E:D600. We replace with engine_init_rolling_buffer which renders 6
single-col slots from $0712 into the same buffer. Original NMI's BG3 transfer then pushes them to VRAM as part
of the existing item-window flow ($EB=$01 latched by original preamble at $00:AF53).
"""
    php
    rep #0x10
    sep #0x20
    jsr.l key_item_init_impl
    ; engine's ensure_hdma turned $1BAE bit 4 on; clear so original NMI
    ; doesn't try to drive HDMA we haven't fully wired (per-scanline
    ; bands not yet matched to the picker rows).
    lda #0x00
    sta.l 0x7E1BAE
    lda #0x00
    sta.l 0x00420C
    plp
    rtl


clear_key_item_slot:
"""Blank one tilemap row at slot_index in the BG3 buffer."""
    php
    phb
    lda #0x7E
    pha
    plb
    rep #0x30
    pha
    phx
    phy
    lda.b 0x29
    pha
    lda.w #0xD600
    sta.b 0x29
    lda.w key_item_rolling_slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    ldx.w #0x0000

_clear_key_loop:
    lda #0x00
    sta (0x29), y
    iny
    inx
    cpx.w #0x0040
    bne _clear_key_loop
    rep #0x20
    pla
    sta.b 0x29
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

key_item_init_filter:
"""
Filter $1440 -> $0712. Faithful inline port of original InitItemList ($00:B2D5 in actual ROM, off-by-2 from
ff4decomp notes). Clears the 96-byte filter buffer, walks 48 inventory items, copies (id, qty) pairs whose IDs
are key items: [$CE..$E6] u [$EB..$FD].
"""
    php
    phb
    sep #0x20
    rep #0x10
    lda #0x7E
    pha
    plb
    ldx.w #0x0000

_filter_clear:
    stz.w 0x0712, x
    inx
    cpx.w #0x0060
    bne _filter_clear
    ldx.w #0x0000
    ldy.w #0x0000

_filter_walk:
    lda.w 0x1440, x
    cmp #0xCE
    bcc _filter_next
    cmp #0xE7
    bcc _filter_accept
    cmp #0xEB
    bcc _filter_next
    cmp #0xFE
    bcs _filter_next

_filter_accept:
    sta.w 0x0712, y
    lda.w 0x1441, x
    sta.w 0x0713, y
    iny
    iny

_filter_next:
    inx
    inx
    cpx.w #0x0060
    bne _filter_walk
    plb
    plp
    rts

update_key_item_scroll_hdma:
"""Build the key-item HDMA shadow table via the shared engine."""
    engine_update_scroll_hdma(key_item_rolling, KEY_ITEM_HDMA_SHADOW, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_VISIBLE_ITEMS, _key_item_hdma_header, _key_item_hdma_footer, _key_item_hdma_signal)  ; noqa: E501

_key_item_hdma_header:
"""Picker HDMA header — 112 lines at BASE (top half = field map preserved)."""
    sep #0x20
    lda #112
    sta.l KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w key_item_rolling_base_scroll
    sta.l KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_footer:
"""Picker HDMA footer — 16 lines at BASE+16 to hide prefetch slot."""
    sep #0x20
    lda #16
    sta.l KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w key_item_rolling_base_scroll
    clc
    adc.w #16
    sta.l KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_signal:
"""NMI shadow-copy signal — set both picker copy_pending + shared $1BB6 mirror."""
    sep #0x20
    lda #0x01
    sta.w key_item_hdma_copy_pending
    rts


key_item_init_impl:
"""
Init key-item picker (filter $1440 -> $0712 then engine init). State
+ hook far-ptrs live at $7E:9C60 (relocated out of $1B00-$1BFF).
"""
    jsr.w key_item_init_filter
    php
    rep #0x30
    sep #0x20
    lda.b #KEY_ITEM_BUFFER_SLOTS
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.visible_rows
    lda.b #0x02
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.slot_height_tiles
    ; item_list_ptr = $7E:0712 (filtered key-item array)
    lda.b #0x12
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.item_list_ptr
    lda.b #0x07
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.item_list_ptr + 2
    lda.b #KEY_ITEM_TOTAL_ITEMS
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.item_count
    lda.b #0x04
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.hdma_channel
    lda.b #0x80
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.vwf_cfg_ptr + 2
    lda.b #key_item_fn_render_slot_trampoline & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_render_slot
    lda.b #( key_item_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( key_item_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_render_slot + 2
    lda.b #key_item_fn_update_hdma_trampoline & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_update_hdma
    lda.b #( key_item_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( key_item_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_update_hdma + 2
    lda.b #key_item_fn_draw_window_trampoline & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_draw_window
    lda.b #( key_item_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( key_item_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + key_item_rolling + RollingBufferState.fn_draw_window + 2
    plp
    php
    rep #0x10
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

key_item_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `key_item_render_item_to_slot`."""
    php
    jsr.w key_item_render_item_to_slot
    plp
    rtl

key_item_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `key_item_ensure_hdma_initialized`."""
    php
    jsr.w key_item_ensure_hdma_initialized
    plp
    rtl

key_item_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_key_item_draw_window`."""
    php
    jsr.w _key_item_draw_window
    plp
    rtl


_key_item_draw_window:
"""
Picker is invoked from inside original ShowItemWindow which already drew the
picker frame via its IRQ slide. No-op.
"""
    rts

key_item_scroll_down_prepare:
"""Picker scroll-down pre-render."""
    engine_scroll_down_prepare(key_item_rolling, key_item_scroll_pos, KEY_ITEM_SCROLL_LIMIT, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)  ; noqa: E501

key_item_scroll_up_prepare:
"""Picker scroll-up pre-render."""
    engine_scroll_up_prepare(key_item_rolling, key_item_scroll_pos, KEY_ITEM_BUFFER_SLOTS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)  ; noqa: E501

key_item_start_scroll_down_impl:
"""Picker: kick scroll-down state machine."""
    engine_start_scroll_down(key_item_rolling, key_item_scroll_pos, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_SCROLL_TOTAL_PIXELS, KEY_ITEM_SCROLL_PIXELS_PER_FRAME, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)  ; noqa: E501

key_item_start_scroll_up_impl:
"""Picker: kick scroll-up state machine."""
    engine_start_scroll_up(key_item_rolling, key_item_scroll_pos, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_SCROLL_TOTAL_PIXELS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)  ; noqa: E501

key_item_update_scroll_frame_impl:
"""Picker: per-frame scroll animation tick."""
    engine_update_scroll_frame(key_item_rolling, KEY_ITEM_SCROLL_PIXELS_PER_FRAME, update_key_item_scroll_hdma)

key_item_finish_scroll_impl:
"""Picker: end-of-animation pre-render + cleanup."""
    engine_finish_scroll(key_item_rolling, key_item_scroll_pos, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_TOTAL_ITEMS, key_item_render_item_to_slot, update_key_item_scroll_hdma)  ; noqa: E501

key_item_refresh_slots_impl:
"""Picker: re-render all slots via the bank-20 engine."""
    php
    sep #0x20
    rep #0x10
    lda.l 0x7E0000 + key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl
