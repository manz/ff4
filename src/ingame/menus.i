.include "src/ingame/main.s"
.include "src/ingame/items.s"
.if INVENTORY_ROLLING_BUFFER {
    .include "src/ingame/inventory_single_column.s"
    .include "src/ingame/inventory_rolling_patches.s"
}
.include "src/ingame/options.s"
.include "src/ingame/status.s"
.include "src/ingame/magic.s"
.include "src/ingame/shop.s"
.include "src/ingame/equip.s"
.include "src/ingame/free_space.s"
.include "src/ingame/windows.s"
