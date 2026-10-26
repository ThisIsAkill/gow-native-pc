# Research notes (index)

Working documents for whoever continues the project (a person or another AI). Newest first. Each one says what was
done, how it was measured, and what is left.

| Document | Subject |
|---|---|
| [vu1-x64-jit.md](vu1-x64-jit.md) | The in-process x86-64 VU1 JIT (engine/patches/18): design, contracts with the dispatcher, tests, how to extend it, risks |
| [vu1-jit-prototype-2026-10-26.md](vu1-jit-prototype-2026-10-26.md) | VU1 code for every area: disc extraction (tools/disc/vu1_from_disc.py), background clang compiler (patch 17) |
| [handoff-2026-10-25-performance-phases.md](handoff-2026-10-25-performance-phases.md) | Performance phases 1-5 (patches 10-13), frame timeline, how to measure |
| [ps2-ports-review-2026-10-25.md](ps2-ports-review-2026-10-25.md) | Review of other PS2 ports (rac-rs, PS2Recomp, SpartanPort) that produced the phases |

Rules that hold for all of them: runtime changes are new `engine/patches/NN-*.patch` files (never edit an applied patch's
context), game data never leaves `data/`, and measurements name the machine and the settings.
