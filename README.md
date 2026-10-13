# Final Fantasy IV

## Building

Bring your own base ROM: an unheadered Final Fantasy IV (Japan) dump at
`build/ff4.sfc` (SHA-1 `eac14578b3465ffce874119005f9b244e8565a79`).
`ff4.sfc.gz.gpg` is CI's encrypted copy; its passphrase is not public.

```shell
uv sync --extra dev
make            # assembles build/ff4.ips, then runs the tests
```

`make check` verifies formatting and runs the a816 lints.

## Screenshots

These are the test goldens (`tests/goldens/`): each is pinned by a test, so they show the current build.

### Variable width fonts
<img src="tests/goldens/showcase/dialogue.png" alt="Opening dialogue" width="512">
<img src="tests/goldens/battle_messages/renamed_cain.png" alt="Battle dialogue with a renamed character" width="512">
<img src="tests/goldens/field_inventory/scroll_0.png" alt="Item list with its description" width="512">

### Menus
<img src="tests/goldens/showcase/field_menu.png" alt="Field menu" width="512">
<img src="tests/goldens/battle_status_names/statuses.png" alt="Battle status names" width="512">
<img src="tests/goldens/battle_magic/white.png" alt="Battle magic in two columns" width="512">
<img src="tests/goldens/save_confirm/saved.png" alt="Save confirmation" width="512">
<img src="tests/goldens/options/options.png" alt="Options" width="512">

### Rolling inventories
<img src="tests/goldens/field_inventory/scroll_5.png" alt="Field inventory, scrolled" width="512">
<img src="tests/goldens/battle_inventory/top.png" alt="Battle inventory" width="512">
<img src="tests/goldens/equip_inventory/open.png" alt="Equipment inventory" width="512">
<img src="tests/goldens/showcase/shop_sell.png" alt="Shop, selling" width="512">
<img src="tests/goldens/treasure/drops_full_8.png" alt="Spoils after a battle" width="512">
<img src="tests/goldens/showcase/key_item_picker.png" alt="Key-item picker" width="512">
<img src="tests/goldens/fat_chocobo/deposit.png" alt="Fat Chocobo deposit" width="512">
