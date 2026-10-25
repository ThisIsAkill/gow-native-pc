# Handoff: performance phases 1-5 (state on 2026-10-25)

Context for whoever continues this work (a person or another AI). It covers what the five performance phases are, what
was done and measured, what is left, how to build and measure, and the traps already hit. Everything below refers to
the repository `gow-native-pc` (GitHub `Vnnc1/gow-native-pc`, local `C:\Users\dzvini\Documents\gow\gow-native-pc`).

## 1. The project in one page

- **What it is:** a native PC port of God of War (PS2, NTSC-U `SCUS_973.99`) built by **static recompilation**. The MIPS
  R5900 code of the game (EE) is translated to C++ once and compiled into a Windows executable. The PS2's other
  processors are emulated or translated by the runtime: IOP and sound in C++, VU1 (vector unit) through native C++
  generated from the microcode the game uploads, and GS (graphics) through an OpenGL renderer.
- **Runtime:** not stored in the repo. `engine/runtime.toml` pins **YYOzcan/Tobiichi-Port @ 471c831**, which is
  ran-j/PS2Recomp plus Waffle565's and KIexster's work. The pipeline clones it into `engine/runtime/` and applies
  `engine/patches/NN-*.patch` in order. **All changes to the runtime are made as new patches**, never committed inside
  `engine/runtime`.
- **Pipeline:** `tools/pipeline/build.ps1` (or `build.cmd`, or the launcher's Install tab). The stages are fetch,
  discs, configure, recomp, sync, build, pgo, optimize, native, launcher, package and installer; the header of
  `build.ps1` documents each one.
- **Launcher:** Qt 6 / QML in `launcher/`. It starts `ps2EntryRunner.exe` with environment variables that match the
  user's settings. Its defaults are full screen, 16:9, FXAA, 2x internal resolution with dynamic scaling, sound on and
  continuous VU1 capture.
- **Test machine ("machine A"):** Xeon E5-2666 v3 (Haswell, 10C/20T), 16 GB RAM, Radeon RX 580 on OpenGL with the AMD
  driver, Windows 10 22H2.

### Rules the owner set (keep them)

1. **Commit and push only when the owner asks.** Work is batched, then committed on request.
2. **Never publish game data.** This covers disc files, recompiled C++ (`data/<game>/recomp`), VU1 captures, IOP module
   dumps, disassembly of the game and PGO profiles (they contain the generated code's function names and counts).
   Everything under `data/` is local only.
3. **Test the way a user plays:** full screen with the launcher's default options. If a default setting is too heavy,
   report it so it can be changed in the launcher.
4. Do not run downloaded binaries without the owner's approval. llvm-mingw in `data/_tools` is approved.

## 2. Where the time goes (why the phases exist)

On the first level (ship, rain, 3-4 enemies) the game is capped at 60 fps by design: its logic follows the 60 Hz VBlank.
A frame's critical path is the **VU1 worker job (~13 ms) plus about 3 ms of EE work in series**. With enemies on
screen the VU1 worker (skinning, particles, lighting microprograms) is the limit; the EE (game code) has headroom since
patch 08. Measuring tools:

- `GOW_PERF_DIAG=1` with `GOW_PERF_FRAME_PC=0x1837B8` prints `[gow-perf]` every 5 s. It reports, per 5 s, the busy
  time of the EE, VU1, GS and IOP threads, `guest_flip_hz` (the game's frame rate) and `host_hz` (window presents).
- `GOW_VU1N_DIAG=1`: `[vu1n]` counts (native pairs and blocks, interpreter fallbacks, clean-operand checks).
- `GOW_GS_HW_STATS=1`: `[gs-hw]` draws, batches, shuffles and texture cache hits/decodes per 5 s.
- `tools/profile/sampler.cpp`: a sampling profiler. It needs a build with symbols: `build.cmd -Pdb` for MSVC, or
  `-gline-tables-only -gcodeview -Wl,--pdb=` for clang. `SAMPLER_LINES=<text>` gives per-line samples;
  `SAMPLER_STACKS=<n>` (added today) gives inclusive callers, which is how the clang present stall was found.
- The scripted benchmark plays the profile's `[optimize]` pad script (`games/gow1/game.toml`) with the launcher's
  defaults and takes screenshots with `GOW_PAD_CAPTURAS=70,110`. Combat runs from about t=70 s to t=145 s. The script
  used today (`bench.ps1`, kept outside the repo) sets:
  - `PS2X_GS_WORKER=1`, `GOW_GS_FINISH_ASINCRONO=1`, `GOW_AUDIO_DEVICE=default`, `GOW_SKIP_FMV=1`;
  - `TOBIICHI_PANTALLA=completa` at the monitor's size, `TOBIICHI_PANORAMICO=16:9`, `TOBIICHI_FXAA=1`;
  - `PS2X_GS_ESCALA=2`, `PS2X_GS_HW_SCALE=2`, `PS2X_GS_ESCALA_DINAMICA=1`, `PS2X_GS_HW=1`;
  - `GOW_VU1_CAPTURA=data\gow1\vu1_capture`, `TOBIICHI_VENTANA_FPS=120`;
  - `GOW_PAD_TEST=1`, `GOW_PAD_GUION=<pad_script>`, plus the diagnostics above.

  A tool that wants a clean exit (PGO) closes the window with `CloseMainWindow()` instead of killing the process.

## 3. The five phases: status

Origin: a review of rac-rs (AsobiCodes), ran-j/PS2Recomp and SpartanPort (the PS3 version) produced five phases. The
review is in `docs/research/ps2-ports-review-2026-10-25.md`.

| # | Phase | Status | Where |
|---|---|---|---|
| 1 | VU1 clean-operand analysis (rac-rs `vuclean` idea) | **done, verified** | `engine/patches/10` |
| 2 | Sound mixer in batches, COP0 Count from the EE clock, IOP heap first fit | **done, verified** | `engine/patches/11` |
| 3 | VU1 static timing (rac-rs `vu1gen`-style) | **not started** | design notes below |
| 4 | Portable toolchain (llvm-mingw / clang) + PGO | **done** (pipeline option); launcher integration partial | `engine/patches/12`, `tools/pipeline/build.ps1` |
| 5 | Skinning / hot self-loop fast path in VU1 | **not started** | design notes below |

Overall: 3 of 5 phases done (about 60 % of the planned work by count; phases 3 and 5 are the largest).

### Phase 1: clean operands (patch 10)

- **What it does:** the native VU1 generator (`tools/vu1/vu1n_gen.py` inside the runtime) analyses, per microcode image,
  which vector-register lanes are guaranteed "clean" (not Inf/NaN). This uses 128-bit lane masks (bit = reg*4+lane),
  per-pair gen/kill effects, block summaries and a fixpoint whose meet is AND. Clean operands skip the PS2 float
  normalisation: normalised loads fell from 9,833 to 6,273, and 301 blocks rely on clean inputs at entry.
- **Safety:** each block registers `VU1NativeLanes {req, gen, keep}`. At run time `runNative` tracks the known-clean
  lanes and checks the required ones (`lanesClean`). On failure it falls back to the exact engine.
- **Verified:** `GOW_VU1N_VERIFY=20000` gave 0 mismatches; 11.8 M lane checks gave 0 failures.

### Phase 2: sound / Count / IOP heap (patch 11)

- **SPU2 mixer:** `mixBatch` computes up to 64-frame batches voice by voice. Every LIBSD API call flushes what is due
  first. `GOW_SND_VERIFY=1` compares against the old per-frame `step()`: 5.9 M frames, 0 differences. Cost fell from
  ~14 % to ~4 % of the game thread. `GOW_SND_PERFRAME=1` restores the old path.
- **COP0 Count:** `mfc0`/`mtc0 Count` now follow the EE cycle clock (the function at `0x185A20` budgets per-frame work
  with it). `GOW_EE_COUNT_FROZEN=1` reverts. This needs the recomp stage.
- **IOP heap:** first fit from the heap base, so freed memory is reused. `PS2X_IOP_HEAP_REUSE=0` reverts.

### Phase 4: clang + PGO (patch 12 + pipeline)

- **Patch 12 (runtime):**
  - **GS draw state compared field by field.** `operator==` was defaulted on all the `GSDrawState` register structs,
    replacing two raw `memcmp`. The structs have padding; MSVC happened to keep it equal and clang does not. With clang
    every primitive became its own batch, giving ~2 fps in 3D.
  - **Shadow-volume counting batches drawn per colour run.** These are COLCLAMP=0, ALPHA 0x68, flat `G += 255` then
    `G += 1`. With the correct compare they merge into one batch and lose the one-colour fixed-function fast path,
    falling back to per-triangle drawing with a texture barrier between each. SwapBuffers then blocked ~1 s per frame
    in fights.
  - Portability: `<cstdlib>` in `VUops.cpp`; `std::extent_v` in a `static_assert`.
  - An instrumented build writes its PGO profile when the window closes (weak `__llvm_profile_write_file`), because the
    shutdown can hang on worker threads before the profile runtime's exit hook.
- **Pipeline (`build.ps1`):**
  - `-Toolchain clang` downloads llvm-mingw 20261020 ucrt once into `data/_tools`, checked against a pinned SHA-256.
  - CMake and Ninja come from PATH, then from the VS Build Tools, then from pip.
  - Compile flags: `-fno-strict-aliasing -fwrapv`; link flag: `-static`. The root CMake adds `-march=native
    -ffp-contract=off` for non-MSVC.
  - The build folder is `<build root>-clang`; the choice is remembered in `data/toolchain.txt`.
  - The `pgo` stage builds an instrumented copy in `<build root>-clang-pgogen`. It plays the `[optimize]` pad script
    for 240 s with the hardware renderer and sound, closes the window, merges the profile into
    `data/<game>/pgo/gow.profdata` with `llvm-profdata`, then rebuilds. Every later clang build uses the profile while
    the file exists.
- **Launcher:** `InstallerBackend::runnerPath()` appends `-clang` to the build root when `data/toolchain.txt` says
  `clang`. The launcher has not been rebuilt with this change yet, and there is no toolchain choice in the UI yet.

## 4. Measurements (machine A, launcher defaults, combat t=70-145 s)

| Build | FPS average | FPS minimum | EE / VU1 / GS busy per 5 s |
|---|---|---|---|
| Patches 01-08 (before patch 09) | 47.6 | ~44 | |
| + 09 | 57.6 | ~53 | |
| 01-09 (same day as 10-11) | 56.5 | 51.4 | |
| + 10-11 (phases 1-2), MSVC | 58.8 / 58.0 (two runs) | 56.0 / 53.1 | 2.13 / 3.00 / 1.82 s |
| + 12, MSVC | 57.2 | 47.6 (one 5 s window) | 2.07 / 2.75 / 1.80 s |
| + 12, clang, no PGO | 55.6 | 50.4 | 1.71 / 3.62 / 2.03 s |
| **+ 12, clang + PGO** (manual build, profile trained with the launcher's defaults) | **59.4** | **57.9** | **1.56 / 3.24 / 1.44 s** |
| + 12, clang + PGO **built by the repo pipeline** (`-Toolchain clang` then `-Stages pgo`; its training run is windowed, no FXAA) | 58.4 | 54.6 | 1.57 / 3.49 / 1.43 s |

- **Build time** (full, machine A): MSVC 45-60 min; clang ~5 min configure + ~10 min compile; PGO adds an
  instrumented build (~12 min), a 4 min run and the final build.
- **Caveats:**
  1. The PGO profile was trained on the same ship run it was measured on. Other levels are not measured yet.
  2. Run-to-run noise is about ±1 fps in the average and several fps in the minimum (one bad 5 s window).
  3. MSVC + 12 needs a repeat run to tell noise from a regression in the minimum. Its batches went 150k -> 40k per 5 s
     because MSVC had been splitting on padding.
  4. The pipeline's PGO build came out ~1 fps below the manual one. Its training run uses fewer launcher settings
     (window instead of full screen, no FXAA / 16:9 / dynamic scale), so the profile covers less of the present path.
     Making the `pgo` stage use exactly the launcher's defaults is a cheap next step.
  5. clang's VU1 worker is 8-15 % slower than MSVC even with PGO. VU1 is the limit, so phases 3/5 matter more than
     compiler work.
- **Verified:** VU1 verify clean, lane checks clean and sound verify identical (phases 1-2). The image matches between
  clang and MSVC: same intro frame, combat screenshots OK.

## 5. Known problem found today (not caused by these phases)

**Intermittent wrong colour tint in gameplay:** sometimes the whole scene goes purple (Kratos's tattoo blue, HUD orb
purple, sky lavender) or green. It happens in **MSVC builds too**, so it predates patches 10-12. The tinted shots seem to
coincide with a short red/orange health bar, so it may be the game's damage/low-health colour effect rendered with the
wrong channels. Suspects are the GS hardware backend's channel-shuffle / CLUT / reinterpret paths in
`gs_hw_backend.cpp` (`tryShuffle`, `LoadClut`, palette sampling) and `gs_texture_store.cpp`. Debug env vars:
`GOW_GS_HW_DUMP*`, `GOW_GS_HW_SKIPTBP=<hex>` (skip draws textured from a block, to bisect post passes), `GOW_GS_TEXSRC`,
`GOW_GS_HW_PALDUMP`. The fix should go in a new `engine/patches/13-*.patch`.

## 6. What is left, in suggested order

### A. Finish phase 4 (small)

1. Rebuild the launcher (`build.cmd -Stages launcher`; Qt and MSVC) and confirm it starts the clang exe from
   `<build root>-clang`.
2. Add a toolchain choice to the launcher's Install tab: "Compiler: Visual Studio / clang (faster build)", which passes
   `-Toolchain`. Also offer the `pgo` stage after "Optimize for 60 fps".
   - Files: `launcher/qml/Main.qml`, `PaginaGrafico.qml` / the install page, `launcher/src/installer_backend.cpp`
     (builds the `build.ps1` argument list), `launcher/qml/Textos.js` (EN / PT-BR / ES texts).
   - Note: another session had uncommitted edits in these files and in `tools/disc/prepare.py` on 2026-10-25. Check
     `git status` first and do not overwrite them.
3. Measure PGO on other areas (e.g. the desert or the Pandora temple via another pad script). Consider a longer training
   run covering more areas; one profile per game version is fine.
4. Optional: let the release ship without Visual Studio. The launcher still needs MSVC Qt; a mingw Qt build
   (`win64_llvm_mingw`) would remove the last VS dependency.

### Result of the phase 3 / 5 attempt (2026-10-25, later the same day): small gain, not the lever

- **What was built.** Done in the test tree `C:\gow-src-locals`; not a patch yet. Exact equality was checked with the
  replay workbench below and with `GOW_VU1N_VERIFY` (2000 runs, 0 mismatches).
  1. **Lane masks inside the dispatch slot.** No pointer to a separate table any more.
  2. **Block chaining.** Each generated block ends with `VU1NativeAccess::chain(n, next)`, which does `runNative`'s
     exit and entry bookkeeping. The block then jumps to the next one with a guaranteed tail call
     (`[[clang::musttail]]`). Self-loops jump to themselves. Without musttail the jump is a nested call and was 13 %
     slower, so chaining is off on MSVC. `GOW_VU1N_CHAIN=0/1` switches it.
- **Measured (replay median of 4 runs, ±3 % noise):** original 1256 ms, lanes 1279 ms, chaining 1231 ms (−2 %).
  In-game combat VU1 worker: 3627 → 3593 ms busy per 5 s (−1 %).
- **Why so little.** The sampling profiler showed ~40 % of VU1 time in the dispatch loop. That was an artefact of
  thread-suspension sampling, which piles samples up around calls and returns. Removing the dispatch loop did not remove
  that time.
  - The real cost is the generated arithmetic: about 20 instructions per VU pair, already tight.
  - It runs as serial dependency chains (MADDA/MADD accumulating in ACC, then clamp), which are serial on the PS2 too.
  - Self-loops are 11 % of block executions and 28 % of pairs (diag counters `selfBlocks` / `selfPairs`). Jumping to
    themselves did not make them faster for the same reason.
- **Workbench.** Use it for any future VU1 change:
  - `GOW_VU1N_RECORD=<file> GOW_VU1N_RECORD_N=4000 GOW_VU1N_RECORD_STRIDE=101 GOW_VU1N_RECORD_SKIP=3000000` records
    combat VU1 programs. The file is local only: it is game data.
  - `GOW_VU1N_REPLAY=<file> GOW_VU1N_REPLAY_REPS=31` replays them, checks bit-exactness and times the warm runs (the
    warm repeats skip the result hash).
  - Always compare medians of several alternating runs, on an idle machine.
- **Where the next real gains probably are** (not measured yet):
  - **Run independent VU1 work in parallel.** Today one worker runs all programs in order; the hardware ran VU1 while
    the EE prepared the next packet. Overlapping the per-frame EE work (~3 ms) with the VU1 job (~13 ms) attacks the
    frame's critical path directly.
  - **Cut non-block VU1 worker costs.** Profile the in-game VU1 thread: VIF unpack, XGKICK/GS packet path, locks.
  - **Cheaper FMAC exactness checks** in the generated code: the `madd` slow-path test on every pair.

### Parallel VU1: what the frame looks like (measured 2026-10-25, MSVC build, ship combat)

- **The timeline.** `PS2X_GS_WORKER_TRACE=<s>` prints kick/job-start/job-done/gs-irq of the GS/VU1 worker, plus
  entry/return of `vid::Flip` 0x1837B8, `vid::WaitForDMAComplete` 0x183878 and 0x13F730.
  - The trace only sees indirect dispatches; direct calls between recompiled functions are not traced.
  - The test tree also marks `ee-wait` / `ee-pace` / `ee-run` (EeScheduler::waitForEvent / pacing).
  - Read it on an MSVC build: on the llvm-mingw build every stderr write takes milliseconds and distorts it. Normal
    play writes almost nothing, so this is not a play-time cost.
- **One frame (~17.5 ms, ~57 fps):**
  1. The worker runs one large VIF1 job (~1.6 MB: unpack + VU1 programs + XGKICK into the GS stage) in **~14 ms**.
     It ends with GS FINISH, which raises gs-irq 2.
  2. The EE runs the game logic during that job (already overlapped), then waits for the FINISH interrupt.
  3. Then it does 0x13F730 → a small 1272-byte job → WaitForDMAComplete → Flip → 0x13F730 → kicks the next large job.
     The worker is idle for that **~3.5 ms**.
  4. The EE waits on worker sync points almost never (`PS2X_GS_WORKER_DIAG=1`: 1 wait in 1483 syncs).
- **Splitting the VU1 job across threads does not fit.** Each VU1 program starts from the state the previous one left
  (VF/VI registers, constants in VU memory).
- **The lever is the ~3.5 ms serial gap.** Let the game start frame N+1 while the worker finishes frame N. Two
  coordinated changes, both opt-in until proven:
  1. **Order the display writes.** GS privileged display writes from the EE (DISPFB1/2, DISPLAY1/2, PMODE in Flip) go
     through the worker queue in order with the GIF stream. Then the host's presentation request
     (`GS::latchHostPresentationFrame`, built from `m_privRegs` at each host vsync) never points at a buffer whose draws
     are not queued yet. Today only the game's FINISH wait guarantees that.
  2. **Early FINISH.** Signal FINISH for the frame's large job when it is queued, not when the GS stream reaches it,
     and suppress the real one at the end of that job so the game does not see it twice.
  - **Risks:** half-drawn frames if step 1 misses a path; the game's interrupt bookkeeping (it may count FINISH or
    check SIGNAL/LABEL); readbacks (the EE reading GS/VU memory still being written: `needsGsWorkerSync` sites cover
    MMIO reads).
  - **Expected gain:** up to ~3.5 ms per VU1-bound frame, which is ship combat 55 → 60 fps on machine A.

### B. Phase 3: VU1 static timing (large; see the result above before starting)

- **Today:**
  - The native VU1 backend (`vu1n_gen.py`, runtime `ps2_vu1_native.inl`, `ps2_vu1_native.h`) runs straight-line blocks
    with "immediate semantics", then reproduces exact pipeline timing at run time.
  - That work is the hist ring, `blockTiming` / `finishBlockTiming` and the MAC/clip/status flag rings.
  - The profile showed `finishBlockTiming` alone at ~5 % of the VU1 thread plus ~4 % for lane tracking. Per-block
    overhead in `runNative` (slot lookup, timing finish, flag ring maintenance) is the cost.
- **Idea (rac-rs `vu1gen`):** compute the timing statically in the generator. Most blocks have a fixed
  stall/latency pattern given their entry state. Steps:
  1. **Classify state at block entry.** Find which pipeline state (pending FMAC writes, Q/P latency, flag ring depth)
     can reach each block. For most blocks, entry state is "drained" or one of a few patterns.
  2. **Emit specialised code.** For each (block, entry pattern), emit code with stalls, Q/P availability and flag
     ring writes resolved at generation time, and an exit summary. Keep the existing dynamic path as fallback when the
     entry state does not match a known pattern, the same way the clean-operand fallback works.
  3. **Verify** with `GOW_VU1N_VERIFY=<n>` (compares native runs with the exact interpreter) and `GOW_VU1N_DIAG`. Add
     counters for "static hit / dynamic fallback".
- **Start by reading:**
  - rac-rs `tools/vu/vu1gen*` (AsobiCodes/rac-rs on GitHub);
  - the runtime's `src/lib/vu/ps2_vu1_native.inl` (`runNative`, `blockTiming`), `include/runtime/ps2_vu1_native.h`;
  - the generator `tools/vu1/vu1n_gen.py` (`gen_block`, `block_summary`, `pair_effect`).
- **Expected gain:** a large share of the VU1 worker's ~3.2-3.6 s per 5 s in combat is per-block overhead. Even
  -20 % VU1 would put combat at a steady 60 on machine A and help weaker CPUs a lot.

### C. Phase 5: hot self-loop / skinning fast path (large, builds on 3)

- 198 blocks are self-loops (the block branches to itself). The hottest are variants at microcode addresses
  `0x2840`, `0x2b90` and `0x2ee0`, which are likely skinning or vertex-transform loops.
- **Idea:** for a self-loop whose body has no XGKICK and a fixed iteration count register:
  1. generate a C++ loop that runs N iterations with timing and flags computed once per iteration pattern (from
     phase 3);
  2. keep registers in SSE locals across iterations;
  3. write back to `VU1State` only at loop exit.
- **Fallback:** the existing per-block path when the iteration count is unknown or the loop body touches the GIF.
- **Verify:** `GOW_VU1N_VERIFY` and image comparisons at several points of the ship and the desert.

### D. Other items (smaller, from earlier notes)

- `/fp:fast` vs `/fp:precise` A/B for the MSVC build. The VU code already forces precise.
- Move IOP/sound to their own thread, off the game thread.
- Fix the colour tint (section 5).
- Commit patches 10-12 and the pipeline/launcher changes once the owner approves.

## 7. How to build and test

```bat
rem MSVC (default)
build.cmd -Stages fetch,configure,recomp,sync,build
rem clang (llvm-mingw), remembered in data\toolchain.txt
build.cmd -Toolchain clang -Stages fetch,configure,recomp,sync,build
rem profile-guided rebuild (clang): instrumented build, 240 s self-play, final build
build.cmd -Stages pgo
rem record new VU1 microcode / IOP modules and compile them in
build.cmd -Stages optimize
rem back to MSVC (its build folder is kept)
build.cmd -Toolchain msvc -Stages build
```

- The game exe is at `<build root>\ps2xRuntime\ps2EntryRunner.exe`, or `<build root>-clang\...` for clang. The build
  root is in `data\build-root.txt`, usually `C:\gow-build`.
- A runtime change goes into a new `engine/patches/NN-name.patch`, with a header explaining what, why and the
  measurements; see patches 10-12 for the style.
- Generate a patch against 01..(N-1):
  1. clone the runtime commit and apply the previous patches;
  2. copy the changed files over;
  3. run `git diff`;
  4. check it with `git apply --check`.
- The fetch stage checks the patch chain by tree comparison and applies only the missing ones.
- `.gitattributes` has `*.patch -text`. Patches must keep their exact bytes; CRLF conversion broke them once.
- Verification env vars: `GOW_VU1N_VERIFY=<n>`, `GOW_SND_VERIFY=1`, `GOW_VU1N_DIAG=1`, `GOW_GS_HW_STATS=1`,
  `GOW_PERF_DIAG=1` with `GOW_PERF_FRAME_PC=0x1837B8`, and `GOW_HOST_SHOT=<host frame>` (writes `host_shot.png`).

## 8. Traps already hit (save time)

- **Raw `memcmp` of structs.** Padding is unspecified, so with clang caches never hit. Compare fields; patch 12 does
  this for the GS draw state.
- **More batching can be slower.** Merged batches can leave a fixed-function fast path, as with the shadow-volume
  passes. Check `[gs-hw]` batches and `host_hz` together.
- **`host_hz` vs `guest_flip_hz`.** The game can run at 60 while the window presents at 1 Hz when the GPU queue is
  saturated. The present thread then sits in `SwapBuffers` → driver `WaitForMultipleObjects`.
- **Wrong-tint screenshots are not proof of a regression.** The tint also appears with MSVC (section 5). Compare the
  same moment, e.g. a host shot in the intro, which is deterministic enough.
- **The pure VU1 interpreter runs at ~4 fps** (`GOW_VU1_NATIVE_OFF=1 GOW_VU1_SIN_COMPILAR=1`), too slow to reach gameplay
  for comparisons.
- **The game process may hang on shutdown.** Kill it after the window closes. The PGO write-out happens before that.
- **Line endings.** Generating C strings from Python, `\n` once became a real newline. Bash heredocs with quotes failed
  in this environment; write helper scripts to files.
- **Waffle's GS draw-batching commits** (00bda7f 09ea6cb 91ac954 c558c21) saturate the GPU queue on the RX 580: window
  0.2-2 Hz. Keep them out.
- **GoW II port commit 5b1a25a** (SetupThread argv) breaks GoW1 boot. Keep it out.
- **LTCG / `/GL`** linking took more than 2.5 h with MSVC. The pipeline builds without it.

## 9. Files touched today (uncommitted on 2026-10-25)

- `engine/patches/10-vu1-clean-operands.patch`, `11-sound-batch-ee-count-iop-heap.patch`,
  `12-clang-build-gs-state-compare.patch`, plus the `engine/README.md` table.
- `tools/pipeline/build.ps1`: `-Toolchain`, the `pgo` stage, `Use-Clang`; `Configure` and `Build-Game` take a folder.
- `launcher/src/installer_backend.cpp`: `runnerPath()` follows `data/toolchain.txt`.
- `tools/profile/sampler.cpp`: `SAMPLER_STACKS`.
- `README.md` and `build.cmd`: the clang/PGO usage.
- `docs/tested-hardware.md`: rows for 10-12, clang and PGO.
- `docs/research/handoff-2026-10-25-performance-phases.md`: this file.
- Not ours: uncommitted edits by another session in `launcher/qml/*`, `launcher/src/installer_backend.cpp` (Python
  detection) and `tools/disc/prepare.py`.
