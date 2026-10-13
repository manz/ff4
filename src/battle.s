"""
The battle: patches over the vanilla battle code (VWF messages, menus, inventory, magic, the NMI-safe multipliers),
plus the relocated blocks nothing else pulls in. Every other battle module comes in through these.
"""
.import "battle/items_reloc"
.import "battle/math_reloc"
.import "battle/math_patches"
.import "battle/monster_ai_patches"
.import "battle/graphics_patches"
.import "battle/magic/patches"
.import "battle/message_patches"
.import "battle/monsters_patches"
.import "battle/items_patches"
.import "battle/debug_always_drop"
