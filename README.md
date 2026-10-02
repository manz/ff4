# Final Fantasy IV

## Building

Bring your own base ROM: an unheadered Final Fantasy IV (Japan) dump at
`build/ff4.sfc` (SHA-1 `eac14578b3465ffce874119005f9b244e8565a79`).
`ff4.sfc.gz.gpg` is CI's encrypted copy; its passphrase is not public.

```shell
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
make            # assembles build/ff4.ips, then runs the tests
```

`make check` verifies formatting and runs the a816 lints.

## Screenshots

### Variable width fonts
![battle-messages-vwf.png](screenshots/battle-messages-vwf.png)
![dialog-vwf.png](screenshots/dialog-vwf.png)
![menu-description-vwf.png](screenshots/menu-description-vwf.png)
### Menus
![battle-menu.png](screenshots/battle-menu.png)
![load-save-menu.png](screenshots/load-save-menu.png)
![main-menu.png](screenshots/main-menu.png)
![two-columns-magic.png](screenshots/two-columns-magic.png)
