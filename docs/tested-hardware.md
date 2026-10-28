# Tested hardware and results

## Build foundation validation (2026-10-28, i5-8265U laptop)

Windows, Intel Core i5-8265U, 24 GB RAM, Intel UHD 620 / Radeon 520; pinned llvm-mingw 20261020 (Clang 23.1.4).
This is a different machine from the Xeon/RX 580 gameplay measurements below. The supplied PT-BR standalone
translation (ELF CRC `D95720D3`) was identified as compatible and prepared successfully.
The owner confirms that this laptop is less powerful than the earlier RX 580 desktop. Keep hardware baselines
separate: lower absolute FPS here does not establish a regression, and elapsed build times cannot be transferred
to the desktop. Compare changes on the same machine, driver, power plan, scene and settings.

- Eleven behavioral pipeline tests pass, plus PowerShell checks for configure reuse, PGO-content invalidation,
  profile paths with spaces, cache opt-out and recording environment restoration on success/failure.
- Real generation from a synthetic MIPS ELF passes in locals/classic modes; repeated inputs skip generation,
  forced identical output preserves timestamps and synchronization makes no unnecessary copies.
  The actual supplied ELF generated 6,418 C++/header files in 134.703 s (generation/publication timer).
- `build.cmd -Stages verify` builds and passes ten isolated guest-call scenarios and all 68 codegen cases.
  The pinned general memory suite still needs an independent repair of stale API references before patch 30.
- A real one-object cache fixture measured 5.302 s cold / 0.402 s warm (cold includes daemon startup), with an
  identical object hash and one cache hit. This is **not** a full-game compile-time or FPS measurement.
  A second fixture confirms same-path PGO replacement misses the cache; output matches an uncached control after
  normalizing COFF timestamps (two hits, three misses in the combined test, no unsupported/failed compilations).
- Clang-built installer: synthetic package round-trip verifies two files, one LZMS block, 357 unpacked bytes;
  imports are Windows system/UCRT DLLs, with no Visual C++ or libc++ runtime DLL requirement.
- Invalid stage and concurrent pipeline invocations return exit code 1 through `build.cmd`; PowerShell syntax
  parsing passes.
- Final `fetch,verify,launcher` validation passes with the complete 01–29b patch chain. The Clang Qt 6.8.3 SDK
  passes 24 sequence-sort compatibility cases. The deployed launcher starts and exits 0 with compiler/SDK paths
  removed from `PATH`, displays the prepared PT-BR disc and reports the game ready; stderr is empty.
  Fixed installation-time estimates were removed because duration depends on hardware and cached artifacts.
- The first real pipeline (`fetch,discs,configure,recomp,sync,build`) completed in 2,005.895 s; the game build/link
  stage took 1,625.804 s. After cleaning the runner target's 956 build outputs with Ninja, the same build/link
  stage completed in 31.344 s with the populated local object cache (98.1% less elapsed time). This compares a
  cold and warm object cache on the same Clang code/configuration, not Clang versus MSVC or a compiler speedup.
- A stable `recomp,sync,build` invocation with unchanged inputs completed in 9.369 s: 2.721 s recompiler stage,
  5.955 s synchronization, 0.272 s game build; no generated source was copied. The first cache-hit generation
  validation itself took 2.090 s versus 134.703 s for generation/publication. Fetch/disc preparation are excluded.
  Raw reports: `data/gow1/logs/foundation-{cold,stable-noop,cache-rebuild}-pipeline.json`.
- First-install gameplay smoke: 100 s, PT-BR disc, Intel UHD 620 / OpenGL 3.3 driver 27.20.100.9664, hidden
  1280x720 window, 2x dynamic resolution, audio off, no previously recorded AOT/IOP code. Gameplay reached;
  2,000 VU1 comparisons passed, 623 JIT blocks compiled with zero unsupported, process exited 0 without forced
  termination. The 80 s capture shows the ship, characters, textures and HUD. Eight diagnostic windows at
  t >= 60 s measured 11.91–20.79 guest FPS (median 15.49). This instrumented JIT-first smoke is not a controlled
  FPS comparison with prepared native code. Evidence: `data/gow1/logs/jit-hybrid-20261028-144139/`.

After recording 109 VU1 images and eight IOP modules, the same Release executable was measured with lean/full
call dispatch (`GOW_DISPATCH_FULL=0/1`). Settings: Intel UHD 620, fixed 1x internal scale, 1280x720 hidden window,
16:9, FXAA off, audio off, hardware GS worker, async FINISH, VU1 recording/background compilation off, frames-only
diagnostics, a GS screenshot at 80 s and the profile's pad script. Each run used a fresh private memory card; order was lean/full,
full/lean, lean/full. All six 120 s runs reached gameplay and exited 0. Eleven five-second windows per run start
after the 60 s warm-up. No compiler build ran during these measurements; the existing power plan was unchanged.

| Round | Lean mean guest FPS | Full mean guest FPS |
|---|---:|---:|
| 1 | 42.64 | 42.19 |
| 2 | 44.23 | 42.53 |
| 3 | 41.84 | 40.05 |
| Mean of runs | **42.90** | **41.59** |

The observed difference is +3.2%, with overlapping ranges and visible run-to-run variation. This is a narrow
same-binary comparison of call routing, **not main versus this branch**, not a statistically established general
speedup, and not a per-frame p95/p99 measurement. Real-time scripted input does not guarantee identical guest frames
at capture times, so screenshot equality is not asserted. Prepared native coverage shows zero misses/lane failures;
the inspected lean and full captures show the ship, characters, textures and HUD. Later levels, heavy combat outside
this scene, audio, AMD/NVIDIA and an actual main-branch build still require separate coverage.

Evidence: `data/gow1/logs/perf-20261028-145147/{summary,statistics}.json` and the six run folders. The report records
the runner SHA-256, settings, CPU, memory and power-plan identity; raw logs retain the graphics-driver information.

Standalone follow-up: a 100 s no-argument launch with diagnostics supplied only by the boot file reaches gameplay,
reports guest frames, verifies 2,000 VU1 runs with zero mismatches and exits 0. The test restores the original boot
file and uses a private card. This functional test ran while Qt was building; no performance result is inferred.
Evidence: `data/gow1/logs/standalone-20261028-150433/summary.json`.

Final delivery: `launcher,package,installer` exits 0. The updated launcher capture has no fixed installation-time
estimate and starts with only Windows system directories on `PATH` (exit 0, empty stderr). The generated setup's
1,456 files / six LZMS blocks / 96,256,472 unpacked bytes independently decompress and match the staging directory.
Setup SHA-256: `9e6acf2bb8328b1f928171c3b0c7e95718e5729aba578dc47ceddfa0f4d32cfe`.
Evidence: `data/gow1/logs/foundation-delivery.log`, `launcher-clang-install-final.png` and
`python -I tools/test/verify_setup.py data/_package/gow-native-pc-setup.exe data/_package/gow-native-pc`.
This verifies the payload, not Windows registration or uninstallation. This final verification record postdates
the documentation snapshot embedded in that package.

Implementation and remaining acceptance gates: [build foundation](research/build-foundation-2026-10-28.md).

## Gameplay measurements

Frame rates of the game itself (the in-game counter, `TOBIICHI_FPS_GOSTER=1` / launcher "FPS counter"), on the
Aegean Sea ship (first level, rain, several enemies) unless noted. The game never exceeds 60: its logic follows the
PS2's 60 Hz VBlank. **These are references, not guarantees**: drivers, power plans, background programs and other
areas of the game change the numbers. Add your own results with a pull request (same columns).

## Measured in this project

### Call-path review (2026-10-28, no gameplay measurement)

Intel Core i5-8265U, 24 GB RAM, Windows, llvm-mingw clang 23.1.4 Release, LTCG off. Patches 01–29 apply cleanly.
New regressions reproduce late diagnostic-setting and worker-trace-window failures; follow-up 29a fixes both.
Final call suite: ten isolated scenarios, 162 C++ checks plus trace-window assertion, all passing. Isolated upstream
CodeGenerator suite: 68/68 after 29b updates two stale DMA/timer expectations. Pipeline verifies the complete patch chain.
The full upstream test executable still cannot build because its memory tests reference removed APIs. No ISO/prepared
disc was available, so gameplay, frame hashes and FPS gains are unverified. See [review](research/patches-28-29-review.md)
for reproduction, local evidence and acceptance work before patch 30.

### Earlier gameplay measurements

**Machine A** — Intel Xeon E5-2666 v3 (10 cores / 20 threads, 2.9-3.5 GHz, Haswell), 16 GB RAM, AMD Radeon RX 580
2048SP (driver 26.1.1, OpenGL), Windows 10 Pro 22H2 (19045), power plan "Maximum Performance", 1280×720 window,
internal resolution 2× (dynamic), hardware renderer on.

| Code combination | Result | Notes |
|---|---|---|
| Waffle565 runtime, `runtime` + `switch` branches (2026-10-18) | **unplayable** | Title, menus and 3D black: textures sample black on this AMD OpenGL driver (`GOW_GPU_BISECT`: draws happen, "no texture" phase grey). Logic ran at 60 presents/s. |
| Tobiichi runtime (2026-10-16), Release without LTCG | 34 fps (1×, combat) – 42-45 fps (2×) | Image correct. CPU-bound (1× was not faster). |
| + IOP and VU1 native code (optimize stage, 856 micro-memories) | 42-45 fps | |
| + Waffle CPU speed-ups (`engine/patches/04`) | **59-60 fps**, window 120 Hz | EE thread ~3.1 s and VU1 ~3.5 s busy per 5 s: ~30 % headroom; scenes with more enemies dip (below). |
| same, scripted ship combat (3-4 enemies on screen, `optimize` pad script, t=75-125 s) | 44-50 fps | VU1 worker 3.8 s busy per 5 s: the limit. 28 VU1 block entries had no native code (`vu1n_heads.txt` not passed to the generator), ~1.2 M interpreter fallbacks per 5 s. |
| + `engine/patches/05`-`07` and the VU1 heads in the pipeline (2026-10-24) | **55-60 fps** in the same combat | Current configuration. 0 VU1 fallbacks; image checked against the previous build. |
| + `engine/patches/08` with `-Codegen locals` (now the pipeline's default, 2026-10-25) | 55-60 fps in the same combat | EE thread 3.0-3.4 -> 2.3-2.6 s busy per 5 s (about -22 %); the VU1 worker stays the limit, so the frame rate is the same here; more headroom on slower CPUs. Scripted run only (ship): boot, gameplay, image as before. |
| Launcher defaults (full screen 1920x1080, 16:9, FXAA, 2x dynamic, sound, continuous VU1 capture), 01-08 + locals | 44-52 fps in combat (average 47.6) | The continuous capture cost ~15 % of the VU1 worker (the frame's critical path: VU1 job ~13 ms + ~3 ms of EE work in series per frame). |
| + `engine/patches/09` (2026-10-25) | **53-60 fps** in combat (average 57.6) | 4:3 instead of 16:9: +1 fps; capture off: no difference. No launcher default needs changing. |
| + `engine/patches/10`-`11` (2026-10-25) | **56-60 fps** in combat (average 58.8, minimum 56.0, against 56.5 / 51.4 measured the same day without them) | VU1 worker 3.58 -> 3.46 s busy per 5 s; sound mixing ~14 % -> ~4 % of the game thread. Verified: GOW_VU1N_VERIFY 20,000 runs 0 mismatches, 11.8 M clean-operand checks 0 failures, GOW_SND_VERIFY 5.9 M frames identical. The frame's critical path is now the VU1 worker (job ~13 ms + ~3 ms of EE work in series). |
| + `engine/patches/12`, built with llvm-mingw 20261020 (clang, static, 2026-10-25) | 50-60 fps in combat (average 55.6) | Without patch 12 the clang build ran at ~2 fps in 3D (GS states never compared equal). EE thread faster than MSVC, VU1 worker slower. Full build ~15 min instead of 45-60. |
| same + PGO (profile from the scripted ship run) | **58-60 fps** in combat (average 59.4, minimum 57.9, against MSVC 58.0 / 53.1 the same day) | EE thread -27 %, GS -21 %, VU1 worker +8 % against MSVC. The profile comes from the same scene it was measured on; other areas not measured yet. |
| + Waffle GS draw-batching commits (00bda7f 09ea6cb 91ac954 c558c21) | game 62 fps, **window 0.2-2 Hz** | The GPU queue saturated on the RX 580 (SwapBuffers blocking); left out of patch 04. |
| Release **with** LTCG (`/GL /LTCG`) | link > 2.5 h, cancelled | MSVC 14.44; the pipeline builds without LTCG by default. |

Discs on machine A with the current configuration (clean build of this repository with `build.cmd`, 2026-10-24):

| Disc (`data/gow1/discs/`) | Result |
|---|---|
| USA + a PT-BR fan translation (full) | Portuguese menus and texts, 58-60 fps, window 120 Hz |
| PT-BR fan translation ISO only (standalone) | Portuguese title menu, gameplay reached, image correct |

Other findings on machine A: fullscreen start crashed (0xC0000005) until `engine/patches/03`; without `IOP_MOD/` the
game waited on the legal screen forever (handled by `tools/disc/prepare.py`).

## Local Windows JIT validation (2026-10-26)

Branch `prototipo-claude`, commit `30b007f` (same commit as `origin/claude/keen-dirac-42wd1y`), runtime patches 01-18.
Built on machine A with llvm-mingw clang 23.1.4, Release, existing PGO profile, LTCG off, and 9,501 captured VU1 images.
Executable: `C:\gow-build-44a8e3b6-clang\ps2xRuntime\ps2EntryRunner.exe`.

- Full game build and the three documented JIT test targets completed successfully on Windows.
- `gow_vu1_jit_aot_test - 2000` and `gow_vu1_jit_test x64 2000`: both exited 0; 4,000 cases, 22,000 native blocks,
  identical digest `7c9d4a139489ff09`. Both had the same 284 known edge-input differences from the exact engine.
- Transform microbenchmark: exact engine 18.448 us, JIT 1.838 us per run (10.0x); AOT 1.135 us in its separate run.
  These are synthetic timings, not a game frame-rate improvement.
- Fuzz: seeds 1-6, 4 images x 6 trials each, `x64` versus `x64-calls`: all exited 0 with matching digest and compiled
  block count per seed (242-262 compiled blocks). Inline compile time averaged 13.7-15.0 us per block.
- Game smoke test: 100 seconds, prepared USA disc, hardware renderer, hidden 1280x720 window, audio off,
  `GOW_VU1N_X64=1`, `GOW_VU1N_VERIFY=2000`, fast boot and scripted Start/X input. Gameplay reached
  (`state=11 levelReady=1`); 2,000 native checks, 0 mismatches; gameplay diagnostics showed `missBlocks=0` and
  `laneFails=0`. Host presentation rate at t=50-95 s was 59.72-59.92 Hz. The 80-second capture showed the ship,
  Kratos, enemies, textures and HUD. The process ended after WM_CLOSE without forced termination; the PowerShell
  process wrapper did not report an exit code, so no exit-code assertion is made for this run.
- **Coverage limit:** `[vu1x] compiled=0` throughout the game smoke test: existing AOT captures covered the scene.
  Actual JIT execution was validated by the synthetic tests; newly encountered game areas beyond the ship remain
  untested. This does not establish correctness or performance throughout the game.

Local evidence (generated, not committed): `data/gow1/logs/jit-smoke-20261026-164716/`, `jit-aot-test.log`,
`jit-x64-test.log`, `jit-fuzz-<seed>-<mode>.log`, `jit-test-build.log` and `build.log` in `data/gow1/logs/`.

## Incremental build and JIT delivery (2026-10-26)

Machine A, runtime patches 01-23, clang Release with existing PGO and LTCG off; rebuilt game and Qt 6.8.3 launcher.
v2.0.0 is already an ancestor of the working branch. Full details and reproduction commands:
[JIT delivery report](research/jit-delivery-2026-10-26.md).

- Disc scan: 956 files, 6 usable images, 470 blocks; 112.088 s cold, 0.420 s cached. This is partial disc coverage.
- Native analysis: 9,480 images; 143.103 s cold, 15.154 s cached, six generated C++ files and timestamps unchanged.
- Final x64/AOT digest and six inline/helper fuzz seeds matched. The 284 documented synthetic edge-input differences
  from the exact engine remain; the new patches do not change arithmetic.
- Two 100 s real-game checks (JIT-only and normal hybrid): gameplay reached, 2,000 comparisons with zero mismatches,
  exit code 0, no forced termination. JIT-only compiled 619 blocks with zero unsupported, 16.4 us average compilation.
  Guest FPS at t=40-95 s: JIT-only 15.40-33.35, median 28.40; hybrid 32.95-59.58, median 56.55. Different simulation
  progress prevents a controlled same-frame comparison. The host's ~120 Hz is not the game frame rate.
- The ship capture showed characters, textures and HUD. Later levels and NVIDIA were not tested in this delivery.
- Final setup: 61,673,468 bytes; all 1,417 files matched staging after independent LZMS decompression (8 blocks,
  128,323,300 unpacked bytes). Setup preview exited 0 with empty stderr; launcher binaries in development and staging
  have identical SHA-256. This validates packaging/startup, not Windows install/uninstall registration end to end.
  Installer SHA-256: `95f951e5bb25ecda4db3551d33807e495f017435be3ff9d39a38a4602fdb3632`.
  This artifact checksum was recorded after packaging; the copy of this document inside that artifact predates it.

## Audio/direct-launch follow-up (2026-10-26)

Same local RX 580 machine and clang build, 2x OpenGL. Patch 24's deterministic multi-voice mixer regression fails
before the correction and passes in batch/per-frame/verification modes afterward. Original and PT-BR translated
disc runs, 100 seconds each with audio, reach opening combat and verify 2,000 VU1 runs with zero mismatches.
Both exit normally; after startup, 17 five-second windows each have zero missing/dropped output samples.
The hatch and sailor scene have not been reproduced; this is not an all-audio-bugs-fixed claim.
See [audio investigation and compatibility plan](research/audio-standalone-mods-2026-10-26.md).

## Reported by the projects this builds on (not re-tested here)

| Machine | Code | Reported result | Source |
|---|---|---|---|
| NVIDIA RTX 4050 Laptop (Linux) | Tobiichi | 2× 60 fps (GPU 49 %), 3× 47-57 fps, 1× 60 fps (ship deck) | Tobiichi-Port docs/ESTADO.md |
| AMD Radeon 680M (integrated, Linux, Mesa) | Tobiichi | 1×-2×; ship combat at 1×: 50-60 fps with the performance power profile, lower on battery | Tobiichi-Port README |
| AMD Radeon RX 5700 XT | Tobiichi (GPU renderer) | OpenGL 4.6 renderer verified (no frame rate given) | Tobiichi-Port docs/ESTADO.md |
| Dedicated NVIDIA/AMD (general) | Tobiichi | 2×-3× at 60 fps "typical" | Tobiichi-Port README |
| Waffle565's PC | Waffle runtime + switch | zones 0-4 at 60 fps | God-Of-War-Native-Port docs/status.md |
| Nintendo Switch (Cortex-A57) | Waffle `switch` branch | title menu 25 fps, gameplay 9-12 fps | God-Of-War-Native-Port docs/status.md |
| Ship, KIexster's stack | KIexster | median ~53-56 game frames/s with the camera still (in progress) | god-of-war-recomp README |

## What usually limits the frame rate

- **CPU (most machines)**: the game thread (EE) and the vector unit (VU1) — single-thread speed matters most. The
  optimize stage and "Speed up visited areas" turn recorded VU1/IOP code native; areas never visited still run the
  VU1 interpreter (slower) until their code is recorded and compiled.
- **GPU**: internal resolution (each step costs its square); dynamic resolution lowers it when the GPU falls behind.
- **Power plan / laptops**: "power saver" or battery lowers the CPU clock and the frame rate.

### Follow-up artifact validation

The updated setup is 61,683,346 bytes, SHA-256
`7300d6ffd55c5bfbd8275839c6025ceae63b765980d23eae46b234d9bbcd69f1`.
Independent decompression verified all 1,421 staged files, 8 LZMS blocks, 128,355,429 unpacked bytes.
No installation/uninstallation registration test was performed on the player's existing install.
Standalone no-argument boot reached gameplay in a 100-second test with 2,000 VU1 checks / zero mismatches and exit 0.
The 300-second empty load screen had zero missing/dropped samples after startup, 54.17-58.99 guest FPS after 20 s;
this does not validate a populated save list. The final artifact checksum and standalone result were recorded after
packaging; the embedded documentation predates those final result lines.

## Cutscene audio investigation (2026-10-26, RX 580)

Same installed clang runner and private card copies, 180 seconds per disc, new game then ATHN01D warp. A01MP02
plays in both runs, graceful exit 0, no guest branch errors. PT-BR reproduces periodic PCM channel-block corruption
before output resampling; original control matches the identical source audio at gain 0.999764 and residual RMS
1.17 (source second 4). PT-BR residual is 2244.99, with 16,813 of 46,822 distinct-channel samples matching the wrong
channel. No runtime fix is claimed. The player's card remains byte-identical to its backup.
See [reproduction evidence and correction plan](research/cutscene-audio-2026-10-26.md).
