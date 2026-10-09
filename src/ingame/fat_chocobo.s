"""Fat Chocobo's screen ($01:CD69 InitFatChocoboMenu, ChooseFatChocoCommand) in French, in the small VWF."""
.include "src/menus/system_menus_macros.i"
.import "menus/system_menus_text"
.import "menus/in_game_text"

.alloc at 0x01CD80 {
    load_system_menu_text_pointer(fat_chocobo.choice_window)
}

.alloc at 0x01CD96 {
    load_system_menu_text_pointer(fat_chocobo.whistle)
}

.alloc at 0x01CD9B {
    load_system_menu_text_pointer(fat_chocobo.greens)
}

.alloc at 0x01CE84 {
    load_system_menu_text_pointer(fat_chocobo.give)
}

.alloc at 0x01D06B {
    load_system_menu_text_pointer(fat_chocobo.take)
}

.alloc at 0x01CFF1 {
    load_system_menu_text_pointer(fat_chocobo.full)
}

.alloc at 0x01D036 {
    load_system_menu_text_pointer(fat_chocobo.bag_full)
}
