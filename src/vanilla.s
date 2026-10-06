"""Named vanilla ROM routines (`.label`): no bytes, but `ff4.sym`, xdds and the LSP symbolicate them."""

; Original ROM call sites referenced by rolling-buffer / treasure-menu patches.
; Captured here as `.label` declarations so symbol exports land in `ff4.sym`
; (xdds + tracer can pretty-print them) and so search/replace stays mechanical.

"""DrawItemName: glyph + attr render via ($1d) + ($29)."""
.label draw_item_name = 0x019060

"""_9017: shared body for DrawItemName / DrawEquipItemName."""
.label draw_item_name_inner = 0x019017

"""DrawItemSlot entry (adds +$40 then falls through)."""
.label draw_item_slot = 0x01A1DE

"""DrawItemSlot inner (skips the +$40 row offset)."""
.label draw_item_slot_inner = 0x01A1ED

"""DrawTreasureList: drops list draw (8 items at $FF28)."""
.label draw_treasure_list = 0x01A15C

"""DrawInventoryList: 48-item bottom list draw."""
.label draw_inventory_list = 0x01A172

"""SelectBG1: $29=$B600 / $35=$6000 (drops staging + VRAM)."""
.label select_bg1 = 0x0184A2

"""SelectClearBG1: ClearBG1Tiles + SelectBG1."""
.label select_clear_bg1 = 0x01849F

"""SelectBG2: $29=$A600 / $35=$6800."""
.label select_bg2 = 0x0184BA

"""SelectBG3: $29=$D600 / $35=$7000 (inventory staging + VRAM)."""
.label select_bg3 = 0x018470

"""SelectBG4: $29=$C600 / $35=$7800."""
.label select_bg4 = 0x018488

"""TfrBG1TilesVblank: $7E:B600 -> VRAM $6000."""
.label tfr_bg1_tiles_vblank = 0x01942D

"""TfrBG2TilesVblank: $7E:A600 -> VRAM $6800."""
.label tfr_bg2_tiles_vblank = 0x019420

"""TfrBG3TilesVblank: $7E:D600 -> VRAM $7000."""
.label tfr_bg3_tiles_vblank = 0x019447

"""Event command $F7: select item."""
.label event_cmd_f7 = 0x00ED97

"""Draw window."""
.label draw_window = 0x0180D9

"""Wait for vblank."""
.label wait_vblank = 0x01818A

"""Convert hex to decimal (4 digits)."""
.label hex_to_dec4 = 0x0181D6

"""Transfer sprite data to ppu."""
.label tfr_sprites = 0x01824F

"""Update controller after scrolling the inventory."""
.label update_ctrl_after_scroll = 0x0182A5

"""Update controller (w/ sound effect)."""
.label update_ctrl_menu = 0x0182C0

"""Draw menu text at the position the text block encodes."""
.label draw_menu_text = 0x0182CD

"""Draw window and text."""
.label draw_window_text = 0x0182FB

"""Draw positioned text."""
.label draw_pos_text = 0x018301

"""Clear the BG4 staging buffer, then fall through to `select_bg4`."""
.label select_clear_bg4 = 0x018485

"""Restore dialogue window graphics."""
.label restore_dlg_gfx_far = 0x01873F

"""Copy text to screen buffer."""
.label copy_text = 0x018798

"""Copy A to X (16-bit) through scratch $43."""
.label tax16 = 0x0187B4

"""Reset all sprites."""
.label reset_sprites = 0x018D6A

"""Get dakuten."""
.label get_dakuten = 0x018E32

"""TfrBG4TilesVblank: $7E:C600 -> VRAM $7800."""
.label tfr_bg4_tiles_vblank = 0x01943A

"""Draw item cursors."""
.label draw_item_cursors = 0x01A105

"""Check if character can use item."""
.label check_can_use_item = 0x01A25D

"""Hide 2nd item cursor."""
.label hide_item_cursor2 = 0x01A2D9

"""Hide 2nd item cursor."""
.label hide_cursor2 = 0x01A2DC

"""Filter the inventory into the key-item list by item id range."""
.label init_item_list = 0x01B2D3

"""Update flying monster v-scroll."""
.label update_flying_hdma = 0x0282E1

"""Multiply (8-bit)."""
.label mult8 = 0x028560

"""Convert hex to decimal."""
.label btlgfx_hex_to_dec = 0x0286BF

"""Normalize number text (5 digit number)."""
.label normalize_num = 0x028716

"""Load menu tilemap vram transfer data."""
.label load_menu_tfr_data = 0x029738

"""Draw monster and character names."""
.label draw_obj_names = 0x0299D3

"""Draw main menu text."""
.label draw_cmd_list_text = 0x0299F1

"""Load menu window data."""
.label load_menu_window_data = 0x029B59

"""Draw a battle menu window."""
.label draw_window3 = 0x029BC7

"""Update enabled inventory items."""
.label update_enabled_items = 0x029F0E

"""Draw status text."""
.label draw_status_text = 0x02A2A1

"""Draw text (any bank)."""
.label draw_text = 0x02A455

"""Draw one battle-text letter."""
.label draw_letter = 0x02A497

"""Draw attack name window."""
.label draw_attack_name_window = 0x02BCA2

"""Message type 2: attack name."""
.label show_msg_02 = 0x02CB32

"""Execute battle."""
.label exec_battle = 0x038009

"""Transfer sprite data to ppu."""
.label btlgfx_tfr_sprites = 0x03FE03

"""Execute a sound command (jsl entry)."""
.label exec_sound_ext = 0x048004

"""Play battle song."""
.label play_battle_song = 0x13FF12

"""Save dialogue window graphics (bg3)."""
.label save_dlg_gfx_ext = 0x14FD0F

"""Restore dialogue window graphics (bg3)."""
.label restore_dlg_gfx_ext = 0x14FFD6

"""Convert hex to decimal."""
.label field_hex_to_dec = 0x15C324

"""Init hardware registers."""
.label init_hw_regs = 0x15C8DF

"""Clear ram."""
.label field_clear_ram = 0x15C9AA

; --- Vanilla WRAM ($0000-$1FFF), named after ff4decomp notes/ff4j-sfc-ram-map.txt ---

"""Sprite data staging for OAM ($0300-$051F)."""
.label sprite_data = 0x0300

"""Inventory for the item select window (48 * 2 bytes)."""
.label item_select_list = 0x0712

"""Dialogue text pointer (16-bit)."""
.label dialog_text_ptr = 0x0772

"""Dialogue text buffer ($0774-$0833)."""
.label dialog_text_buffer = 0x0774

"""Dialogue pause duration (16-bit)."""
.label dialog_pause_duration = 0x08F4

"""Dialogue pause counter (16-bit)."""
.label dialog_pause_counter = 0x08F6

"""Gil amount for a treasure chest or the inn (24-bit)."""
.label gil_amount = 0x08F8

"""Item index (treasure chest, item select window)."""
.label treasure_item_index = 0x08FB

"""Event script buffer ($09D5-$0A14)."""
.label event_script = 0x09D5

"""Colour palettes (16 * 32 bytes)."""
.label color_palettes = 0x0CDB

"""Character names (14 * 6 bytes)."""
.label character_names = 0x1500

"""Button mapping."""
.label button_mapping = 0x16A9

"""Window colour (16-bit)."""
.label window_color = 0x16AA

"""World, or the high byte of the map id on sub-maps."""
.label world_id = 0x1701

"""Map id."""
.label map_id = 0x1702

"""Hex to decimal conversion digits ($180C-$1810)."""
.label hex_digits = 0x180C

"""Pending menu HDMA update."""
.label menu_hdma_pending = 0x1820

"""Selected character (battle menu)."""
.label battle_selected_char = 0x1822

"""Enable the menu tilemap transfer to VRAM."""
.label menu_tilemap_tfr_enable = 0x1824

"""Number of VRAM transfers needed."""
.label menu_tilemap_tfr_count = 0x1825

"""Shop type."""
.label shop_type = 0x1A01

"""Confirm button mapping."""
.label confirm_button = 0x1A37

"""Menu cursor position data ($1B00-$1BEB)."""
.label menu_cursor_data = 0x1B00

"""Inventory scroll position."""
.label inventory_scroll_pos = 0x1B1A

"""0: item menu, 1: equip menu."""
.label inventory_menu_mode = 0x1B1F

"""Inventory cursor 1 x position (0 or 1)."""
.label inventory_cursor1_x = 0x1B22

"""Sound interrupt."""
.label sound_interrupt = 0x1E00

"""Sound interrupt parameter 1."""
.label sound_interrupt_param = 0x1E01
