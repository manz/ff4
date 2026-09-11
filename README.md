# Final Fantasy IV

## Building

The base ROM is not in the repository; decrypt the copy that is:

```shell
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
gpg --decrypt ff4.sfc.gz.gpg | gunzip > build/ff4.sfc
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
