# Adding a game (e.g. God of War II)

The pipeline, disc tools and launcher are game-agnostic: they read `games/<id>/game.toml`. What makes a game run is
game-specific work that does not exist yet for anything but God of War:

1. **Identify the disc**: `python -I tools/disc/identify.py <iso>` prints the boot ELF, CRC and (once the profile has
   it) compatibility. Fill `[executable]` (name, serial, crc, text_sha1 — compute the SHA-1 of `.text` with
   `discfs.text_sha1`).
2. **Function map**: a CSV of function starts for the recompiler (God of War's came from analysis + Ghidra + manual
   fixes; PS2Recomp ships `ps2_analyzer` and Waffle565's `find_functions.py` approach). Without it the recompiler
   misses functions (runtime: "No exact recompiled function").
3. **Recompiler config**: `recomp.template.toml` with stubs (syscalls, libraries replaced by the runtime), MMIO tables
   and patches — see God of War's in the runtime (`config/recomp.template.toml`).
4. **Overrides**: C++ replacing parts of the game that touch hardware or rely on timing the runtime does not model
   (God of War: `src/gow_overrides.cpp`, ~2,000 lines: IPU/MPEG, pad, memory card, VBlank waits, widescreen data).
   They are registered for the ELF name (`PS2_REGISTER_GAME_OVERRIDE`).
5. **Runtime fixes**: each game finds new gaps (VU1 microcode paths, GS features, IOP modules). Add them as
   `engine/patches/NN-*.patch` — or, if they break the other game, a per-game patch set (extend `game.toml` with a
   patch list; not needed yet).
6. **Disc layout**: `[disc]` — TOC/PAK names if the game uses an archive, IOP module folder, text files (for language
   detection), movie extensions.
7. **Optimize script**: `[optimize] pad_script` (timed button presses reaching gameplay) for the VU1/IOP recording run.
8. Set `status = "playable"` only when a scripted run reaches gameplay (`[gow-pad2:test] levelReady=1` or the game's
   equivalent) and the image is right on AMD and NVIDIA.

## God of War II status

`games/gow2/game.toml` exists with `status = "planned"`; the pipeline refuses it. Nothing of steps 2-5 exists. The
GoW II engine is an evolution of GoW I's, so the GoW I overrides and runtime fixes are the best starting point, but
addresses, data layouts and microcode differ: expect weeks of work, starting with step 2.
