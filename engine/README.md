# engine/

- `runtime.toml` — which runtime to download (repository + pinned commit). **Required**: PS2Recomp (ran-j) and the
  native runtime built on it (Waffle565, KIexster, Tobiichi-Port). Stage `fetch` (or the launcher's "Download
  runtime") clones it into `engine/runtime/` (git-ignored).
- `patches/NN-*.patch` — this project's changes to the runtime, applied in name order. Each starts with a few lines
  saying what it changes, why, and where it came from; `git apply` skips those lines.

| Patch | What | Origin |
|---|---|---|
| 01-release-ltcg-option | `PS2X_RELEASE_LTCG` option, Release built without LTCG | this project |
| 02-vu1-capture-with-native | VU1 microcode recording with the native VU1 active | KIexster |
| 03-fullscreen-windows-crash | fullscreen / F11 crash on Windows | this project |
| 04-cpu-backports-from-waffle | EE / VIF1 / VU1 / DMA speed-ups (42-45 → 59-60 fps on the reference machine) | Waffle565 |
| 05-gow2-runtime-fixes | GS upscaling fixes (bloom ghost, CLAMP edges, point-sampled scaled targets, sprite edges, Z clears, channel shuffles), anisotropic filtering (`GOW_ANISO`), runtime RPC/TLS pools out of the game heap, scratchpad DMA interleave, MPEG audio stream type, memory card file kept open, IOP `strtok`/`GetSystemTimeLow` | God of War II port (cxldsakeb, DaniSBR1: fork DaniSBR1/PS2Recomp, branch `godofwar2`) |
| 06-recompiler-movn-movz-64bit | MOVZ/MOVN write only the low 64 bits of rd, as on the R5900 (needs a recompile) | God of War II port (`ddcc548`), redone here |
| 07-vu1-heads-sound-batch-pdb | Native VU1: records block entries without native code (`vu1n_heads_seen.txt`); SPU2 mixer: one output lock per batch instead of per sample; `PS2X_RELEASE_PDB` (Release with debug information) | this project |
