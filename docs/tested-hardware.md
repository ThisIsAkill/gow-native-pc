# Tested hardware and results

Frame rates of the game itself (the in-game counter, `TOBIICHI_FPS_GOSTER=1` / launcher "FPS counter"), on the
Aegean Sea ship (first level, rain, several enemies) unless noted. The game never exceeds 60: its logic follows the
PS2's 60 Hz VBlank. **These are references, not guarantees**: drivers, power plans, background programs and other
areas of the game change the numbers. Add your own results with a pull request (same columns).

## Measured in this project

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
