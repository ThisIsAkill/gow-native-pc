# God of War II — planned

Not playable and not buildable yet (`status = "planned"` in `game.toml`). What a port needs, in order, is in
[`docs/adding-a-game.md`](../../docs/adding-a-game.md): disc identification (CRC, `.text` SHA-1), a function map, a
recompiler configuration, game overrides, runtime fixes, the disc layout and an optimize script.

To help: run `python -I tools/disc/identify.py "<your GoW II iso>"` and put the printed ELF name and CRC in
`game.toml`; then start on the function map.
