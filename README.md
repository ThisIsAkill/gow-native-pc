<div align="center">

# God of War — Native PC

**English** · [Português (Brasil)](README.pt-BR.md)

A native PC port of *God of War* (PS2, NTSC-U `SCUS-97399`) built by statically recompiling MIPS R5900 code to C++,
with an installer launcher, one-click build, fan-translation support and a 60 fps target.

![platform](https://img.shields.io/badge/platform-Windows%20x64-0078D6)
![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus&logoColor=white)
![build](https://img.shields.io/badge/build-CMake%20%2B%20Ninja-064F8C?logo=cmake&logoColor=white)
![based on](https://img.shields.io/badge/based%20on-PS2Recomp-8A2BE2)
![status](https://img.shields.io/badge/status-experimental-orange)
![license](https://img.shields.io/badge/license-GPL--3.0-blue)

</div>

> [!IMPORTANT]
> This repository contains **no game files**. You need your own copy of God of War. The native runtime
> (**PS2Recomp**, as extended by Waffle565, KIexster and the Tobiichi port) is **required**; the launcher downloads it,
> it is not stored here. Full attribution: [`CREDITS.md`](CREDITS.md).

## Contents

- [What is this?](#what-is-this)
- [Required: the PS2Recomp runtime](#required-the-ps2recomp-runtime)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Performance](#performance)
- [Translations and languages](#translations-and-languages)
- [God of War II](#god-of-war-ii)
- [Repository layout](#repository-layout)
- [Credits and license](#credits-and-license)

## What is this?

The game's executable (`SCUS_973.99`) is translated from MIPS to C++ by **PS2Recomp** and compiled into a Windows
program. The PS2 hardware (GS, VU1, IOP, sound, pad, memory card) is replaced by native code — it is not an emulator.
This project brings the work of several authors (see [`CREDITS.md`](CREDITS.md)) together behind a single installer:

- **Launcher with installation**: checks the requirements, **downloads the PS2Recomp runtime**, identifies your ISO,
  builds the game with a progress bar and starts it — all in one window.
- **One ISO is enough**: the original (USA) or a recognised fan translation. With several ISOs (e.g. the original and
  a translation) every language becomes playable and the launcher **asks which language you want to play in**.
- **Optimised for 60 fps**: VU1 and IOP code is compiled natively; while you play, newly met code is recorded and
  "Speed up visited areas" compiles it.

## Required: the PS2Recomp runtime

Without the runtime nothing can be recompiled or run. It is **not part of this repository**: the launcher
(**Install → Download runtime**) or `build.cmd` clones it into `engine/runtime/` as pinned in
[`engine/runtime.toml`](engine/runtime.toml) (Tobiichi-Port, which bundles ran-j's PS2Recomp with Waffle565's and
KIexster's extensions) and applies [`engine/patches`](engine/patches).

## Requirements

| | |
|---|---|
| OS | Windows 10/11 64-bit |
| CPU | x86-64 with **AVX2** (Intel 2013+, AMD 2015+); 4 cores or more |
| RAM | 8 GB (16 GB recommended while building) |
| GPU | OpenGL 4.3+ |
| Disk | ~25 GB free (extracted disc + build) |
| Tools | [Git](https://git-scm.com/download/win), [Python 3](https://www.python.org/downloads/windows/); the C++ compiler (clang, llvm-mingw) is downloaded by the first build. Visual Studio is not required; development builds of the launcher build a matching Qt from pinned sources |
| Game | Your **God of War (NTSC-U, SCUS-97399)** ISO or a recognised translation |

## Getting started

1. Get the launcher, either way:
   - **Installer (easiest):** download `gow-native-pc-setup.exe` from
     [Releases](https://github.com/Vnnc1/gow-native-pc/releases), run it, **INSTALL** (no administrator rights,
     your user only). It adds Start menu / desktop shortcuts and an entry in Windows' *Apps* to uninstall it.
   - **From the source code:** clone this repository and run, in its folder:

     ```bat
     build.cmd -Stages launcher
     ```

     The first time it downloads Qt 6 (about 1 GB). When it finishes, **`God of War Launcher.lnk`** appears in the
     repository folder: double-click it.
2. In the launcher → **Install** tab:
   1. install anything missing under **Requirements**;
   2. **Download runtime**;
   3. **Add ISO…** (one or more);
   4. **Install and build** — the first build takes about 15-30 minutes depending on the CPU (it downloads the clang
      compiler, llvm-mingw, once); with "Optimize for 60 fps" the game plays itself for 4 minutes and is compiled again
      at the end (do not touch it).
3. **PLAY**. **Other → Game text** switches the language.

From a terminal: `build.cmd -Discs "D:\God of War (USA).iso"` (examples in [`build.cmd`](build.cmd)).

Compiler: Clang ([llvm-mingw](https://github.com/mstorsjo/llvm-mingw)) is the single supported build toolchain for
the game, launcher and installer. Tools and checksums are pinned in `tools/pipeline/toolchains.json`. The legacy
`-Toolchain msvc` argument migrates to Clang; it no longer invokes Visual Studio. Existing build files are preserved.
The first **developer launcher build** compiles its compatible Qt dependencies once and can take substantially longer
than a game build; release users receive the prebuilt launcher.
For an existing installation, run `build.cmd -Stages configure,recomp,sync,build` once to create the generation
manifest before using the shorter `sync,build` maintenance path.

Unchanged EE inputs now skip code generation, unchanged generated files keep their timestamps, and a local sccache
reuses eligible C/C++ objects. Use `-ForceRecomp` to force generation and `-CompilerCache none` to disable the object
cache. `build.cmd -Stages verify` runs regression tests without a disc. JSON timings are saved in `data/<game>/logs`.
`build.cmd -Stages pgo` records a training profile and rebuilds with it; new profile contents invalidate old objects.
See the [foundation design](docs/research/build-foundation-2026-10-28.md) and
[updated roadmap](docs/research/roadmap-2026-10-27.md) for measurement gates and pending gameplay validation.

## Performance

The game is capped at 60 frames by design (its logic follows the PS2's 60 Hz VBlank). Measured and reported results on
several machines, with each code combination that was tried: [`docs/tested-hardware.md`](docs/tested-hardware.md).
The same settings may give different results on another machine — treat the table as a reference.

## Translations and languages

Fan translations are recognised by their executable (`games/gow1/game.toml`, `[[editions]]`). A translation that only
changes data (text) runs on its own or on top of the original disc: [`docs/translations.md`](docs/translations.md).

## God of War II

Planned: the architecture is per game (`games/<id>/`), but a GoW II port does not exist yet. What it needs:
[`games/gow2/README.md`](games/gow2/README.md).

## Repository layout

```
engine/     runtime.toml (which runtime to download) + numbered patches (origin and reason in each)
games/      per-game profiles: gow1 (playable), gow2 (planned)
launcher/   the Qt 6 launcher: installation + play
installer/  the release setup .exe (Win32, packs launcher + tools into one file; build.cmd -Stages installer)
tools/      disc/ (identify, extract, prepare discs), pipeline/ (build)
docs/       architecture, tested hardware, translations, adding a game
data/       (generated, git-ignored) prepared discs, saves, logs, recorded code
```

Maintainers (AI agents included): start with [`AGENTS.md`](AGENTS.md).

## Credits and license

GPL-3.0 — see [`LICENSE`](LICENSE). This project derives from PS2Recomp (ran-j), God-Of-War-Native-Port (Waffle565),
god-of-war-recomp (KIexster) and Tobiichi-Port (YYOzcan); the full list and what came from each is in
[`CREDITS.md`](CREDITS.md). God of War is a trademark of Sony Interactive Entertainment.

Repository: `https://github.com/Vnnc1/gow-native-pc`
