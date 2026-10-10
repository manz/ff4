

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


.import "preamble"
.import "vwf_ram"
.import "items"

; Labels borrowed from neighbouring modules. As an include these resolved
; because ff4.s composed one translation unit; a module names what it uses.
.import "ingame/vanilla_trampolines"
.import "libmz"
.import "lib/rolling_inventory_engine"
.import "small_vwf/init"


; Four rows on screen, matching the window vanilla draws ; the engine
; adds the prefetch slot itself, and it stays inside the staging page
; without being pushed.
_KEY_ITEM_VISIBLE_ITEMS := 4
_KEY_ITEM_BUFFER_SLOTS := 5
_KEY_ITEM_TOTAL_ITEMS := 48
_KEY_ITEM_SCROLL_LIMIT := 42
_KEY_ITEM_SCROLL_PIXELS_PER_FRAME := 8
_KEY_ITEM_SCROLL_TOTAL_PIXELS := 16

; Key-item picker state moved out of $1B00-$1BFF to clean $7E:9C60 for
; the same reason as treasure ($9C00) + drops ($9C30) : engine path
; needs 35 bytes per instance, $1B00-$1BFF is too small and vanilla
; sprite code stomps past $1BEB.


_KEY_ITEM_SLIDE_OPEN_DONE := 0x08


_KEY_ITEM_SCROLL_FRAMES := 8
_KEY_ITEM_SCROLL_STEP_PX := 2
_KEY_ITEM_ROW_HEIGHT_PX := 16

; NMITIMEN while the picker is up: vanilla's InitItemWindowIRQ arms
; $A1 = NMI + V-IRQ + auto-joypad, and the V-IRQ is what draws the
; window. Rendering drops NMI and keeps the IRQ.
; Direct page the picker renders on, off the field's own $0600.
_KEY_ITEM_RENDER_DP := 0x1D00
_KEY_ITEM_NMITIMEN_PICKER := 0xA1
_KEY_ITEM_NMITIMEN_RENDER := 0x21

_KEY_ITEM_HDMA_TABLE_ADDR := 0x9900
_KEY_ITEM_HDMA_TABLE := 0x7E9900
_KEY_ITEM_HDMA_SHADOW_ADDR := 0x9940
_KEY_ITEM_HDMA_SHADOW := 0x7E9940
_KEY_ITEM_HDMA_BANK := 0x7E
; Header + 6 rows + footer + terminator, rounded up to a word count.
_KEY_ITEM_HDMA_TABLE_SIZE := 40

_KEY_ITEM_FILTER_BUFFER := 0x0712

; BG3 staging page for the picker's window body. The rendered page is
; DMA'd to BG3 plane 1 at VRAM word $2C00, where vanilla draws the
; picker's item rows (text on plane rows 1/3/5/7, cursor in column 2).
; 16 rows x 32 entries x 2 bytes covers the whole visible window.
_KEY_ITEM_STAGING_ADDR := 0xD600
; Eight rows: the four rows the window shows, at two rows each.
;
; BG3 plane 1 is the map's own tilemap, and vanilla only saves and
; restores the rows its window covers - anything we write past them is
; map content that never gets put back, which showed up as blocks of
; scrambled map after paging through the list. The engine's fifth
; (prefetch) slot stays in the staging page and is not pushed.
; The whole ring: _KEY_ITEM_BUFFER_SLOTS slots of two 32-cell tilemap
; rows at 2 bytes a cell. This was 0x200 - four slots - so the fifth,
; the one a scroll rotates into view, never reached VRAM.
_KEY_ITEM_STAGING_SIZE := _KEY_ITEM_BUFFER_SLOTS * 0x80
; Vanilla's item-window IRQ points BG3 at the right screen (plane 1) for
; the window's scanlines and sets BG3VOFS from $BB, which rests at $70.
; The band starts around screen line 144, so it shows BG line 144 + 112
; = 256, which wraps to plane row 0: the ring belongs at the top of the
; plane, and each $10 of $BB steps it one item further in.
_KEY_ITEM_TILEMAP_VRAM_WORD := 0x2C00
; Attribute byte vanilla writes for every cell of this window: palette
; 0 with the priority bit, so the body draws above the map.
_KEY_ITEM_TILEMAP_ATTR := 0x20
; Blank cell the menu windows are filled with (see any drawn window in
; the BG3 buffer: every empty cell reads $FF).
_KEY_ITEM_BLANK_TILE := 0xFF
; Every row of vanilla's window in BG3 plane 1: $00 outside the box in
; columns 0-1 and 30-31, the side borders $19 / $1A in columns 2 and 29,
; blank body between.
_KEY_ITEM_OUTSIDE_TILE := 0x00
_KEY_ITEM_BORDER_LEFT_TILE := 0x19
_KEY_ITEM_BORDER_RIGHT_TILE := 0x1A
_KEY_ITEM_BORDER_LEFT_COL := 2
_KEY_ITEM_BORDER_RIGHT_COL := 29

_KEY_ITEM_HDMA_CHANNEL_BIT := 0x10

.include "src/rolling_state.i"

.include "../bank20.i"
.import "vanilla"
.include "config.i"

.if TREASURE_INVENTORY_ROLLING {
    .alloc _key_item_picker_block in bank20_reloc {
_key_item_ensure_hdma_initialized:
"""
    Lazy-capture $9F (BG3VOFS shadow) on first call, stash in base_scroll. HDMA channel enable deferred until the
    picker has its own window draw + visible loop wired - leaving ch4 enabled here corrupts the field BG3 layer
    (Cecil walks on a split screen) since the engine's RTL goes back to the field via EventCmd_f7 without any
    teardown.
"""


    rep #0x20
    lda.l key_item_rolling.base_scroll
    cmp.w #0xFFFF
    bne _key_item_hdma_already_init
    lda.l 0x7E019F
    sta.l key_item_rolling.base_scroll
    sep #0x20
; Build the scroll table so the shadow is ready, but do NOT arm the
; channel yet. Driving BG3VOFS here overrides the scroll vanilla uses to
; place this window and leaves the register parked at our value after
; the picker closes ; arming lands with the scroll wiring, once the
; bands are matched to the window's real position on screen.
    jsr.w update_key_item_scroll_hdma
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
    sta.l dma_ch4.DMAP
    lda #PPU.BG3VOFS
    sta.l dma_ch4.BBAD
    rep #0x20
    lda.w #_KEY_ITEM_HDMA_TABLE_ADDR
    sta.l dma_ch4.A1TL
    sep #0x20
    lda #_KEY_ITEM_HDMA_BANK
    sta.l dma_ch4.A1B
    plp
    rts

_key_item_blank_slot_rows:
"""
Fill this slot's two tilemap rows with the window's blank cell.

The renderer only writes the cells it draws - the name, the colon and
the two quantity digits - so every other cell in the row keeps whatever
the field left in the BG3 tilemap underneath. On a dark room that
passed for a window body  ; on a bright one the map's own tiles show
straight through the list, including the gap between a short name and
its quantity. Wipe the whole 2-row slot first and let the draw fill it
back in.

Entry: 16-bit A/X/Y, DB = $7E. X and Y are caller-saved already.
"""


    rep #0x30
    lda.l key_item_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * 128 : two 32-tile rows, 2 bytes per cell
    clc
    adc.w #0xD600
    tax
    ldy.w #0x0040  ; 64 cells = 2 tilemap rows

_blank_cell:
    jsr.w _key_item_window_cell
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _blank_cell
    rts

_key_item_window_cell:
"""
Blank window cell for the staging byte at X: outside tile, side border
or body, by column. The staging page is row-aligned, so X's low six
bits are the byte offset within its row.

Entry/exit: 16-bit A/X. Returns the cell word (attr << 8 | tile) in A.
"""


    txa
    and.w #0x003F
    lsr
    cmp.w #_KEY_ITEM_BORDER_LEFT_COL
    bcc _cell_outside
    beq _cell_left
    cmp.w #_KEY_ITEM_BORDER_RIGHT_COL
    bcc _cell_body
    beq _cell_right

_cell_outside:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_OUTSIDE_TILE
    rts

_cell_left:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BORDER_LEFT_TILE
    rts

_cell_right:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BORDER_RIGHT_TILE
    rts

_cell_body:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BLANK_TILE
    rts

key_item_cursor_slot_impl:
"""
Give vanilla's cursor draw a ring slot instead of an absolute row.

`DrawItemSelectCursor` ($00:B11A) computes the cursor's VRAM address
from `$BA + $8C` - scroll position plus cursor row - because vanilla
drew the whole filtered list as one tall strip and scrolled the window
over it, so an item's address grew without bound as the list scrolled.
Our ring re-renders in place and wraps $BB instead, so past the first
screenful that address walked off the end of the window and drew the
hand into unrelated tilemap rows.

Fold it into the ring: the item at cursor row r lives in slot
(top_row + r) mod _KEY_ITEM_BUFFER_SLOTS, which is what the rest of the
routine wants in $4B.

Replaces `lda $ba / clc / adc $8c / sta $4b` at $00:B13D  ; vanilla picks
up again at $00:B144 with `stz $4a`.
"""


    php
    sep #0x20
    lda.b 0xBA
    clc
    adc.b menu_dp.bg2_vscroll

_cursor_slot_mod:
    cmp.b #_KEY_ITEM_BUFFER_SLOTS
    bcc _cursor_slot_done
    sec
    sbc.b #_KEY_ITEM_BUFFER_SLOTS
    bra _cursor_slot_mod

_cursor_slot_done:
    sta.b 0x4B
    plp
    rtl

_key_item_render_item_to_slot:
"""Render filtered item from $7E:0712 + edge_row*sizeof(Item) into BG3 buffer at $7E:D600 + slot_index*128 + 0x44."""
    php
    phb
    lda #0x7E
    pha
    plb
    rep #0x30
    pha
    phx
    phy
    lda.b menu_dp.item_ptr
    pha
    lda.b menu_dp.tilemap_offset
    pha
    lda.b 0x45
    pha
    lda.b menu_dp.window_top_only
    pha
    sep #0x20
    lda.b menu_dp.item_slot
    pha
    lda.b menu_dp.item_usable
    pha
    rep #0x20
    lda.w #0xD600
    sta.b menu_dp.tilemap_offset
    jsr.w _key_item_blank_slot_rows
    sep #0x20
    lda.l key_item_rolling.edge_row
    asl
    clc
    adc #0x12
    sta.b menu_dp.item_ptr
    lda #0x07
    adc #0x00
    sta.b menu_dp.item_ptr + 1
    rep #0x20
    lda.b menu_dp.item_ptr
    tax
    sep #0x20
    lda.l item_x.id, x
    pha
    lda.l item_x.qty, x
    sta.b 0x5C
    stz.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline
    lda.l key_item_rolling.slot_index
    sta.b menu_dp.item_slot
; Attribute byte for the fixed cells the renderer writes (symbol,
; colon, quantity): palette 0 + priority, matching the window body.
    lda #_KEY_ITEM_TILEMAP_ATTR
    sta.b menu_dp.item_usable
    stz.b menu_dp.window_attr
; Route this render's CHR flush at the picker's window (BG3 $6800) via
; the secondary descriptor: the field map is live underneath, so the
; primary window ($2800) is the BG3 tilemap here, not spare CHR.
    lda #VWF_CTX_KEY_ITEM
    sta.l vwf_engine.caller_ctx
    rep #0x20
    lda.l key_item_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
; Y = slot * 128 + 6 : two staging rows (2 * 64 bytes) per slot, six
; bytes in so the symbol lands in column 3 and the name from column 4,
; where vanilla puts them - column 2 belongs to the cursor.
; draw_field_item_name blanks the row at Y and writes glyphs at Y + $40,
; so slot N's name lands on staging row 2N+1: rows 1/3/5/7.
    clc
    adc.w #0x0006
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    lda #VWF_CTX_PRIMARY
    sta.l vwf_engine.caller_ctx
    pla
    sta.b menu_dp.item_usable
    pla
    sta.b menu_dp.item_slot
    rep #0x20
    pla
    sta.b menu_dp.window_top_only
    pla
    sta.b 0x45
    pla
    sta.b menu_dp.tilemap_offset
    pla
    sta.b menu_dp.item_ptr
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

_key_item_render_all:
"""
    Replacement for original UpdateItemText. Original just clears $0774 (text-buffer scratch) and walks $0712 to lay
    out 4x4 grid into the BG3 buffer at $7E:D600. We replace with engine_init_rolling_buffer which renders 6
    single-col slots from $0712 into the same buffer. Original NMI's BG3 transfer then pushes them to VRAM as part
    of the existing item-window flow ($EB=$01 latched by original preamble at $00:AF53).
"""


    php
    rep #0x10
    sep #0x20
    jsr.l _key_item_init_impl
; engine's ensure_hdma turned $1BAE bit 4 on; clear so original NMI
; doesn't try to drive HDMA we haven't fully wired (per-scanline
; bands not yet matched to the picker rows).
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    lda #0x00
    sta.l cpu_regs.HDMAEN
    plp
    rtl

_clear_key_item_slot:
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
    lda.b menu_dp.tilemap_offset
    pha
    lda.w #0xD600
    sta.b menu_dp.tilemap_offset
    lda.l key_item_rolling.slot_index
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
    sta.b (menu_dp.tilemap_offset), y
    iny
    inx
    cpx.w #0x0040
    bne _clear_key_loop
    rep #0x20
    pla
    sta.b menu_dp.tilemap_offset
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

_key_item_init_filter:
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
    stz.w item_select_list, x
    inx
    cpx.w #0x0060
    bne _filter_clear
    ldx.w #0x0000
    ldy.w #0x0000

_filter_walk:
    lda.w field_inventory.id, x
    cmp #0xCE
    bcc _filter_next
    cmp #0xE7
    bcc _filter_accept
    cmp #0xEB
    bcc _filter_next
    cmp #0xFE
    bcs _filter_next

_filter_accept:
    sta.w item_select_list, y
    lda.w field_inventory.qty, x
    sta.w item_select_list + 1, y
    iny
    iny

_filter_next:
    inx
    inx
    cpx.w #0x0060
    bne _filter_walk
; Y advanced by two per accepted item, so it ends at twice the count.
; Everything downstream - the ring's item_count and the scroll ceiling -
; needs that number, and this is the only place that knows it.
    tya
    lsr
    sta.l key_item_count
    plb
    plp
    rts

update_key_item_scroll_hdma:
"""Build the key-item HDMA shadow table via the shared engine."""
; Build key-item picker HDMA scroll table. Inlined from the former
; engine_update_scroll_hdma macro for the same reason as treasure.
    {
    php
    rep #0x30
    pha
    phx
    phy
    lda.b 0x40
    pha
    lda.b 0x42
    pha
    ldx.w #0x0000
    jsr.w _key_item_hdma_header
    stz.b 0x42

_row_loop:
    lda.l key_item_rolling.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_mod_loop:
    cmp.w #_KEY_ITEM_BUFFER_SLOTS
    bcc _mod_done
    sec
    sbc.w #_KEY_ITEM_BUFFER_SLOTS
    bra _mod_loop

_mod_done:
    asl
    asl
    asl
    asl
    sta.b 0x40
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl
    eor.w #0xFFFF
    inc
    clc
    adc.b 0x40
    clc
    adc.l key_item_rolling.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #_KEY_ITEM_VISIBLE_ITEMS
    bcs _row_loop_done
    jmp.w _row_loop

_row_loop_done:
    jsr.w _key_item_hdma_footer
    sep #0x20
    lda #0x00
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    jsr.w _key_item_hdma_signal
    rep #0x20
    pla
    sta.b 0x42
    pla
    sta.b 0x40
    ply
    plx
    pla
    plp
    rts
    }

_key_item_hdma_header:
"""Picker HDMA header - 112 lines at BASE (top half = field map preserved)."""
    sep #0x20
    lda #112
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.l key_item_rolling.base_scroll
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_footer:
"""Picker HDMA footer - 16 lines at BASE+16 to hide prefetch slot."""
    sep #0x20
    lda #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.l key_item_rolling.base_scroll
    clc
    adc.w #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_signal:
"""NMI shadow-copy signal - set both picker copy_pending + shared $1BB6 mirror."""
    sep #0x20
    lda #0x01
    sta.l key_item_rolling.hdma_copy_pending
    rts

_key_item_init_impl:
"""
    Init key-item picker (filter $1440 -> $0712 then engine init). State
    + hook far-ptrs live at $7E:9C60 (relocated out of $1B00-$1BFF).
"""


    jsr.w _key_item_init_filter
    php
    rep #0x30
    sep #0x20
; VISIBLE rows, not buffer slots - the engine adds the prefetch slot
; itself (`buffer_slots = visible_rows + 1`).
    lda.b #_KEY_ITEM_VISIBLE_ITEMS
    sta.l key_item_rolling.visible_rows
    lda.b #0x02
    sta.l key_item_rolling.slot_height_tiles
; item_list_ptr = $7E:0712 (filtered key-item array)
    lda.b #0x12
    sta.l key_item_rolling.item_list_ptr
    lda.b #0x07
    sta.l key_item_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l key_item_rolling.item_list_ptr + 2
    lda.l key_item_count
    sta.l key_item_rolling.item_count
    lda.b #0x04
    sta.l key_item_rolling.hdma_channel
    lda.b #0x80
    sta.l key_item_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l key_item_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l key_item_rolling.vwf_cfg_ptr + 2
    lda.b #_key_item_fn_render_slot_trampoline & 0xFF
    sta.l key_item_rolling.fn_render_slot
    lda.b #( _key_item_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_render_slot + 1
    lda.b #( _key_item_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_render_slot + 2
    lda.b #_key_item_fn_update_hdma_trampoline & 0xFF
    sta.l key_item_rolling.fn_update_hdma
    lda.b #( _key_item_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_update_hdma + 1
    lda.b #( _key_item_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_update_hdma + 2
    lda.b #_key_item_fn_draw_window_trampoline & 0xFF
    sta.l key_item_rolling.fn_draw_window
    lda.b #( _key_item_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_draw_window + 1
    lda.b #( _key_item_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_KEY_ITEM
    sta.l key_item_rolling.menu_id
    plp
    php
    rep #0x10
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

key_item_after_open_impl:
"""
Keep the picker's list drawn, once per frame.

Hooked over `lda #$01  ; sta $7D` at $00:AF7E, just past the top of the
picker's input loop. Vanilla's own `jsr $912F` right before it is left
alone: standing in for that wait cost the loop its frame pacing and the
picker never drew. Every cursor branch jumps back to the loop top, so
this runs once per frame and must stay cheap - it renders on two edges
only:

  - vanilla's slide counter $DA reaching its fully-open value, i.e. the
    window has just finished opening, so build config and render  ;
  - vanilla's scroll position $BA changing, i.e. the list scrolled
    under the cursor, so re-render the slots at the new position.

Vanilla owns the scroll and the cursor  ; the engine owns the row
contents.
"""


    php
    sep #0x20
    rep #0x10
    lda #0x01
    sta.b 0x7D  ; the store this hook displaced
    lda.b 0xDA  ; DP-relative: the caller's direct page, whatever it is
    cmp.l key_item_open_slide_seen
    beq _check_scroll
    sta.l key_item_open_slide_seen
    cmp.b #_KEY_ITEM_SLIDE_OPEN_DONE
    bne _after_open_done
    lda.b 0xBA
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
    jsr.w _key_item_save_vram
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_init_impl
    bra _finish_render

_check_scroll:
    lda.b 0xBA
    cmp.l key_item_last_scroll
    beq _after_open_done
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
; Only refresh against a struct this profile actually armed. The slide
; marker lives in WRAM and survives the picker closing, so a later open
; can reach the scroll edge without the open edge having run init -
; refreshing then dispatches whatever far-pointers happen to be in the
; struct, and the engine's hook call lands in the middle of unrelated
; code. menu_id is the cheapest proof that init has run.
    lda.l key_item_rolling.menu_id
    cmp.b #ROLLING_MENU_ID_KEY_ITEM
    bne _render_from_scratch
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_refresh_slots_impl
    bra _finish_render

_render_from_scratch:
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_init_impl

_finish_render:
    sep #0x20
    rep #0x10
    jsr.w _key_item_push_window
    jsr.w _key_item_leave_render

_after_open_done:
    plp
    rtl

_key_item_enter_render:
"""
Make the field safe for a menu-context render: NMI off, and the render
moved onto a direct page of its own.

The menu VWF renderer scratches a wide set of direct-page bytes - $1D,
$29/$2A, $33, $34, $43, $5A-$5D, $DB and its own $63-$79 block - which
is free real estate in the menus but live field state here: the field
engine writes those same bytes every frame. Snapshotting the field page
and putting it back does not fix that: the window V-IRQ keeps running
across the render (it is what draws the window at all), so a restore
also rewinds whatever the IRQ advanced meanwhile, and the frame it
misses drags the window's band across the map.

So the render gets its own page instead. $1D00 is free - the decomp RAM
map has $1BEC-$1DFF unassigned, and no read or write lands there in any
of our savestates. The live field page is copied in first, so anything
the render reads still sees the caller's values  ; anything it writes
lands in the copy and is dropped. Both interrupt handlers load their own
D ($00:9480 and $00:92A5 both do `ldx #$0600 / phx / pld`), so they are
unaffected by ours. NMI stays off across the render the way vanilla
brackets its own unsafe field work (field.asm InitMapRAM).
"""


    sep #0x20
; Drop NMI only. The picker's window is drawn BY the V-IRQ
; (InitItemWindowIRQ arms $A1 = NMI + V-IRQ + auto-joypad), so clearing
; the whole register blanked the window for the frames we render in:
; it looked like the window closed and reopened on every scroll, and the
; cursor lost its per-frame draw with it.
    lda #_KEY_ITEM_NMITIMEN_RENDER
    sta.l cpu_regs.NMITIMEN
    jsr.w _key_item_save_dma
    rep #0x30
    tdc
    sta.l key_item_dp_prev
    tax
    ldy.w #_KEY_ITEM_RENDER_DP
    lda.w #0x00FF
; MVN leaves DB on its destination bank; the caller's is not ours to
; change.
    phb
    mvn 0x7E, 0x7E
    plb
    lda.w #_KEY_ITEM_RENDER_DP
    tcd
    rts

_key_item_leave_render:
"""Hand the caller its own direct page back and re-enable NMI."""
    rep #0x20
    lda.l key_item_dp_prev
    tcd
    sep #0x20
    rep #0x10
    jsr.w _key_item_restore_dma
    sep #0x20
    lda #_KEY_ITEM_NMITIMEN_PICKER
    sta.l cpu_regs.NMITIMEN
    rts

key_item_scroll_limit_impl:
"""
Stop the list where it actually ends, not where vanilla's did.

Replaces `lda $ba / cmp #$11` at $00:B00D. Vanilla drew the whole
filtered list and let the window slide over it, so a fixed ceiling of 17
matched the longest list it could build. Ours is built per save: with 16
key items held, that ceiling let the window scroll five rows past the
last item into blanks before it refused to move at all.

Returns with Z set when the window is already at the bottom, which is
what the `bne $B016` right after this site tests. Vanilla left $BA in A
here  ; nothing reads it, since $B075 loads its own A first.

Entered with an 8-bit accumulator and the caller's direct page, so $BA
stays a direct-page read.
"""


    lda.l key_item_count
    sec
    sbc.b #_KEY_ITEM_VISIBLE_ITEMS
    bcs _limit_ready
; Fewer items than the window shows: there is nothing to scroll.
    lda.b #0x00

_limit_ready:
    cmp.b 0xBA
    rtl

key_item_scroll_down_impl:
"""
Scroll the picker's window down one item, over the engine's ring.

Replaces vanilla ScrollItemListDown ($00:B09E), which animated $BB by 2
per frame for 8 frames and relied on the WHOLE list being present in the
tilemap. The engine keeps five slots, so after the animation $BB comes
back by one item's worth and the ring is re-rendered at the new scroll
position: the window walks the list while the tilemap stays put.
"""


    php
    sep #0x20
    rep #0x10
    lda #_KEY_ITEM_SCROLL_FRAMES
    sta.l key_item_scroll_frames

_scroll_down_loop:
    jsr.l wait_for_vblank_long
    sep #0x20
    lda.b 0xBB
    clc
    adc.b #_KEY_ITEM_SCROLL_STEP_PX
    sta.b 0xBB
    lda.l key_item_scroll_frames
    dec
    sta.l key_item_scroll_frames
    bne _scroll_down_loop
; Back onto the ring, then redraw it where the list now sits.
    lda.b 0xBB
    sec
    sbc.b #_KEY_ITEM_ROW_HEIGHT_PX
    sta.b 0xBB
    jsr.w _key_item_rerender
    plp
    rtl

key_item_scroll_up_impl:
"""Scroll the window up one item  ; mirror of the down path."""
    php
    sep #0x20
    rep #0x10
    lda #_KEY_ITEM_SCROLL_FRAMES
    sta.l key_item_scroll_frames

_scroll_up_loop:
    jsr.l wait_for_vblank_long
    sep #0x20
    lda.b 0xBB
    sec
    sbc.b #_KEY_ITEM_SCROLL_STEP_PX
    sta.b 0xBB
    lda.l key_item_scroll_frames
    dec
    sta.l key_item_scroll_frames
    bne _scroll_up_loop
    lda.b 0xBB
    clc
    adc.b #_KEY_ITEM_ROW_HEIGHT_PX
    sta.b 0xBB
    jsr.w _key_item_rerender
    plp
    rtl

_key_item_save_dma:
"""
Stash DMA channel 3's registers.

Every transfer the picker runs - tilemap push, CHR flush, the VRAM
save/restore - reprograms channel 3, which steals it from any HDMA the
map has armed there. A mosaic/pixelate effect loses its table mid
animation and never gets it back, so put the registers where they were.
"""


    php
    sep #0x20
    rep #0x10
    ldx.w #0x0000

_save_dma_loop:
    lda.l dma_ch3.DMAP, x
    sta.l key_item_dma_save, x
    inx
    cpx.w #0x000B
    bne _save_dma_loop
    plp
    rts

_key_item_restore_dma:
"""Put channel 3's registers back."""
    php
    sep #0x20
    rep #0x10
    ldx.w #0x0000

_restore_dma_loop:
    lda.l key_item_dma_save, x
    sta.l dma_ch3.DMAP, x
    inx
    cpx.w #0x000B
    bne _restore_dma_loop
    plp
    rts

_key_item_vram_to_sram:
"""
Copy one VRAM slice into SRAM. A = VRAM word address (16-bit), X = SRAM
address low+mid, Y = byte count  ; bank of the destination is fixed to
the reservation's.

Must run inside vblank: VRAM reads outside blanking return garbage.
"""


    php
    rep #0x20
    sta.l ppu.VMADDL  ; VMADD
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN  ; VMAIN: increment after the high byte
    lda.l ppu.VMDATALREAD  ; prime the read latch (discarded)
    lda #0x81  ; DMAP: PPU -> CPU, two registers
    sta.l dma_ch3.DMAP
    lda #PPU.VMDATALREAD
    sta.l dma_ch3.BBAD
    rep #0x20
    txa
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #key_item_chr_save >> 16
    sta.l dma_ch3.A1B
    rep #0x20
    tya
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN  ; MDMAEN ch3
    plp
    rts

_key_item_sram_to_vram:
"""Write one saved slice back. Same register contract as the save."""
    php
    rep #0x20
    sta.l ppu.VMADDL
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN
    lda #0x01  ; DMAP: CPU -> PPU, two registers
    sta.l dma_ch3.DMAP
    lda #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    txa
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #key_item_chr_save >> 16
    sta.l dma_ch3.A1B
    rep #0x20
    tya
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN
    plp
    rts

_key_item_save_vram:
"""Stash the two slices the picker is about to overwrite."""
    php
    jsr.w _key_item_save_dma
    sep #0x20
    rep #0x10
; Only the glyph CHR: the window band of the tilemap belongs to vanilla,
; which draws its window there during the slide-open - before this hook
; ever runs - and puts the map back itself on close. Snapshotting it
; here would capture the window, not the map, and restoring that would
; be worse than leaving it alone.
    jsr.l wait_for_vblank_long
    rep #0x20
    lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
    ldx.w #key_item_chr_save & 0xFFFF
    ldy.w #KEY_ITEM_VWF_BYTE_COUNT
    jsr.w _key_item_vram_to_sram
    jsr.w _key_item_restore_dma
    plp
    rts

key_item_close_impl:
"""
Give the map its VRAM back as the picker closes.

Hooked over `lda #$01  ; sta $ec` at the tail of vanilla's close
animation ($00:B05D block), the last thing that runs before
ShowItemWindow returns.
"""


    php
    jsr.w _key_item_save_dma
    sep #0x20
    rep #0x10
    jsr.l wait_for_vblank_long
    rep #0x20
    lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
    ldx.w #key_item_chr_save & 0xFFFF
    ldy.w #KEY_ITEM_VWF_BYTE_COUNT
    jsr.w _key_item_sram_to_vram
    jsr.w _key_item_restore_dma
    sep #0x20
    lda #0x01
    sta.b 0xEC  ; the store this hook displaced
    plp
    rtl

_key_item_rerender:
"""Redraw the ring at vanilla's current scroll position ($BA)."""
    sep #0x20
    rep #0x10
    lda.b 0xBA
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_refresh_slots_impl
    sep #0x20
    rep #0x10
    jsr.w _key_item_push_window
    jsr.w _key_item_leave_render
    rts

_key_item_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_key_item_render_item_to_slot`."""
    php
    jsr.w _key_item_render_item_to_slot
    plp
    rtl

_key_item_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `_key_item_ensure_hdma_initialized`."""
    php
    jsr.w _key_item_ensure_hdma_initialized
    plp
    rtl

_key_item_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_key_item_draw_window`."""
    php
    jsr.w _key_item_draw_window
    plp
    rtl

_key_item_draw_window:
"""
Prime the BG3 staging buffer with the picker's blank window body.

Vanilla draws the picker's box on BG1 and writes only item text, the
side borders and blank fill into BG3 plane 1, so the body is cheap to
rebuild (see `_key_item_window_cell`). The engine then renders item
names over it and the whole page is pushed to VRAM in one DMA, which
keeps us off VRAM reads entirely.
"""


    php
    phb
    rep #0x30
    lda.w #0x7E7E
    pha
    plb
    plb
    ldx.w #0x0000

_draw_window_loop:
    jsr.w _key_item_window_cell
    sta.w _KEY_ITEM_STAGING_ADDR, x
    inx
    inx
    cpx.w #_KEY_ITEM_STAGING_SIZE
    bne _draw_window_loop
    sep #0x20
    plb
    plp
    rts

_key_item_push_window:
"""
DMA the staging page to the picker's BG3 tilemap slice ($2C00).

The picker overlays a live map, so unlike the menus there is no vanilla
BG3 push to piggyback on: drain `transfer_pending` through here.
"""


    php
    sep #0x20
    rep #0x10
    lda.l key_item_rolling.transfer_pending
    beq _push_window_done
    lda #0x00
    sta.l key_item_rolling.transfer_pending
    jsr.l wait_for_vblank_long
; No vanilla NMI hook runs the VWF flush in field the way the menus do,
; so push the picker's glyph CHR here, in the same vblank as the
; tilemap it belongs to.
    jsr.w render.flush_chr_to_vram  ; RTS-ending, same bank-20 region
    rep #0x20
    lda.w #_KEY_ITEM_TILEMAP_VRAM_WORD
    sta.l ppu.VMADDL  ; VMADD
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN  ; VMAIN: word access, +1 word per write
    lda #0x01
    sta.l dma_ch3.DMAP  ; DMAP: word transfer
    lda #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    lda.w #_KEY_ITEM_STAGING_ADDR
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #0x7E
    sta.l dma_ch3.A1B
    rep #0x20
    lda.w #_KEY_ITEM_STAGING_SIZE
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN  ; MDMAEN ch3

; Publish the scroll table. The menus let the field NMI hook copy
; shadow -> active, but that hook only runs while a menu owns the
; screen, so the picker copies in the same vblank as its tilemap. The
; channel itself stays disarmed until the scroll wiring lands.
    rep #0x30
    ldx.w #0x0000

_push_hdma_copy:
    lda.l _KEY_ITEM_HDMA_SHADOW, x
    sta.l _KEY_ITEM_HDMA_TABLE, x
    inx
    inx
    cpx.w #_KEY_ITEM_HDMA_TABLE_SIZE
    bcc _push_hdma_copy
    sep #0x20

_push_window_done:
    plp
    rts

_key_item_start_scroll_down_impl:
"""Picker: kick scroll-down state machine via the engine."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

_key_item_start_scroll_up_impl:
"""Picker: kick scroll-up state machine via the engine."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

_key_item_update_scroll_frame_impl:
"""Picker: per-frame scroll animation tick."""
    php
    rep #0x10
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

_key_item_finish_scroll_impl:
"""Picker: end-of-animation cleanup via the bank-20 engine."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

_key_item_refresh_slots_impl:
"""Picker: re-render all slots via the bank-20 engine."""
    php
    sep #0x20
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl
    }
}
