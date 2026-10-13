"""
Shared battle_render bit constants, included inside `.scope battle_render { ... }` so message.s, redraw_gates.s and
the writer-site shims all see `battle_render.<name>`. Constants don't link: `.include`, not `.extern`.
"""


; Per-region dirty bits (1 = dirty): writers set them on state change, the gated inits clear them.
REGION_DIRTY_MESSAGES = RegionDirtyBits.messages.mask
REGION_DIRTY_MONSTERS = RegionDirtyBits.monsters.mask
REGION_DIRTY_NAMES = RegionDirtyBits.names.mask
REGION_DIRTY_COMMANDS = RegionDirtyBits.commands.mask

; Per-region tilemap DMA, set on the render paths, fired by dma_transfer in the NMI.
TILEMAP_PENDING_COMMANDS = TilemapPendingBits.commands.mask
TILEMAP_PENDING_MAIN = TilemapPendingBits.main.mask

; Spell list VWF: names render into the items window's tiles ($C0..$FB), never the command window's (the two slide
; past each other). Only on-screen rows hold glyphs: a ring of SPELL_RING_ROWS slots, list row r in slot
; r % SPELL_RING_ROWS. Five rows show, a sixth while a scroll slides it in.
CHR_REGION_SPELLS = ChrTransferBits.spells.mask
SPELL_TILE_BASE = 0xC0
SPELL_RING_ROWS = countof(BattleRenderState.spell_ring_rows)
SPELL_NAME_TILES = 5
SPELL_ROW_TILES = SPELL_NAME_TILES * 2
SPELL_RING_TILES = SPELL_ROW_TILES * SPELL_RING_ROWS
SPELL_LIST_ROWS = 12
SPELL_VISIBLE_ROWS = 5
SPELL_NAME_LENGTH = 9
