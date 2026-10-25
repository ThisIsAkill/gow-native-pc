# Architecture

```
            ISO(s) ──► tools/disc/identify.py ──► tools/disc/prepare.py ──► data/<id>/discs/*, languages.json, mc0
                                                                                    │
engine/runtime.toml ──► fetch: engine/runtime (PS2Recomp + game overrides) + engine/patches
                                                                                    │
games/<id>/game.toml ─► configure (CMake/Ninja, C:\gow-build) ─► recomp (ELF → C++) ─► sync ─► build ─► ps2EntryRunner.exe
                                                                                    │
                        optimize: scripted run records VU1 microcode + IOP modules ─► native: compiled into the game
                                                                                    │
launcher (Qt): Install tab drives all of the above (installer_backend → build.ps1); Play starts ps2EntryRunner with
the chosen language's ELF and the settings as environment variables; while playing, new VU1 microcode is recorded.
```

## Runtime layers (inside engine/runtime, from the projects in CREDITS.md)

| PS2 part | Native replacement |
|---|---|
| EE (game code) | statically recompiled C++ (~6,400 functions) |
| VU1 | microcode compiled ahead of time from recorded micro-memories; interpreter for unrecorded code |
| GS | OpenGL renderer with GPU render targets, internal resolution 1×-8× |
| IOP | the game's IRX modules compiled ahead of time; HLE kernel |
| SPU2, pad, memory card, MPEG movies | native services |

## Data flow per run

`ps2EntryRunner.exe <disc folder>/SCUS_973.99`: the ELF's folder is the CD root (`.disc_layout` lists every file by
sector; files past the disc's end are allowed), `mc0/` there is the memory card, overrides are matched by ELF name.

## Why some choices

- Short build folder: MAX_PATH in the dependencies' git checkouts.
- Release without LTCG: hours-long link on MSVC.
- Disc folders per language instead of runtime language switches: no runtime change, and the original movies stay
  when the original disc is available.
- Continuous VU1 recording: areas not covered by the scripted run otherwise fall back to the slow interpreter.
