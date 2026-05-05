

"""
Key-item picker rolling buffer (single column).

Triggered from event scripts via EventCmd_f7 ($00:ED96), which routes
through ShowItemWindow ($01:B354 in the disassembly). Vanilla renders
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
open/close is replaced by the engine's scroll state machine  ; vanilla
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

key_item_rolling := 0x1BF0
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

key_item_scroll_pos := 0x1BFF

KEY_ITEM_HDMA_TABLE_ADDR := 0x9900
KEY_ITEM_HDMA_TABLE := 0x7E9900
KEY_ITEM_HDMA_SHADOW_ADDR := 0x9940
KEY_ITEM_HDMA_SHADOW := 0x7E9940
KEY_ITEM_HDMA_BANK := 0x7E

KEY_ITEM_FILTER_BUFFER := 0x0712


key_item_ensure_hdma_initialized:
"""Capture $9F + configure HDMA channel for key-item picker. STUB."""
    rts

key_item_render_item_to_slot:
"""Render filtered item from $7E:0712 + edge_row * Item.__size into BG3 tilemap. STUB."""
    rts

ClearKeyItemSlot:
"""Blank a single key-item tilemap slot. STUB."""
    rts

key_item_init_filter:
"""Filter $1440 -> $0712 via vanilla InitItemList ($01:B2D3): clears 96-byte filter buffer, walks 48 inventory items, copies (id, qty) pairs whose IDs fall in [$CE..$E6] u [$EB..$FD]."""
    jsr.l InitItemList_Trampoline
    rts

update_key_item_scroll_hdma:
"""Build the key-item HDMA shadow table via the shared engine."""
    engine_update_scroll_hdma(key_item_rolling, KEY_ITEM_HDMA_SHADOW, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_VISIBLE_ITEMS, _key_item_hdma_header, _key_item_hdma_footer, _key_item_hdma_signal)

_key_item_hdma_header:
"""Picker HDMA header band — dialog frame at BASE scroll. STUB."""
    rts

_key_item_hdma_footer:
"""Picker HDMA footer — locks scanlines past prefetch slot. STUB."""
    rts

_key_item_hdma_signal:
"""NMI shadow-copy signal for picker channel. STUB."""
    rts


key_item_init_impl:
"""Init key-item picker (filter $1440 -> $0712, then engine init)."""
    jsr.w key_item_init_filter
    engine_init_rolling_buffer(key_item_rolling, KEY_ITEM_BUFFER_SLOTS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot)

key_item_scroll_down_prepare:
"""Picker scroll-down pre-render."""
    engine_scroll_down_prepare(key_item_rolling, key_item_scroll_pos, KEY_ITEM_SCROLL_LIMIT, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)

key_item_scroll_up_prepare:
"""Picker scroll-up pre-render."""
    engine_scroll_up_prepare(key_item_rolling, key_item_scroll_pos, KEY_ITEM_BUFFER_SLOTS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)

key_item_start_scroll_down_impl:
"""Picker: kick scroll-down state machine."""
    engine_start_scroll_down(key_item_rolling, key_item_scroll_pos, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_SCROLL_TOTAL_PIXELS, KEY_ITEM_SCROLL_PIXELS_PER_FRAME, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)

key_item_start_scroll_up_impl:
"""Picker: kick scroll-up state machine."""
    engine_start_scroll_up(key_item_rolling, key_item_scroll_pos, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_SCROLL_TOTAL_PIXELS, key_item_ensure_hdma_initialized, key_item_render_item_to_slot, update_key_item_scroll_hdma)

key_item_update_scroll_frame_impl:
"""Picker: per-frame scroll animation tick."""
    engine_update_scroll_frame(key_item_rolling, KEY_ITEM_SCROLL_PIXELS_PER_FRAME, update_key_item_scroll_hdma)

key_item_finish_scroll_impl:
"""Picker: end-of-animation pre-render + cleanup."""
    engine_finish_scroll(key_item_rolling, key_item_scroll_pos, KEY_ITEM_VISIBLE_ITEMS, KEY_ITEM_BUFFER_SLOTS, KEY_ITEM_TOTAL_ITEMS, key_item_render_item_to_slot, update_key_item_scroll_hdma)

key_item_refresh_slots_impl:
"""Picker: re-render all slots."""
    engine_refresh_slots(key_item_rolling, key_item_scroll_pos, KEY_ITEM_BUFFER_SLOTS, key_item_render_item_to_slot)
