# VU1 x86-64 JIT (engine/patches/18) — design, contracts, tests, how to change it

Windows real-game validation and follow-up patches 19-23 are recorded in
[jit-delivery-2026-10-26.md](jit-delivery-2026-10-26.md). The original results below describe patch 18's initial delivery.

This is the reference for anyone, a person or an AI, who changes, extends or debugs the in-process VU1 JIT. It assumes
`AGENTS.md` (project layout and rules) and, for background, `docs/research/vu1-jit-prototype-2026-10-26.md` (why the
JIT exists, the disc extraction and the clang background compiler).

## 1. What it does

The game uploads VU1 microcode at run time. The build compiles the microcode it knows ahead of time (`vu1n_gen.py` → C++
→ the game executable): the first-play recording, "Speed up visited areas", the disc extraction. Code the build did not
see runs in the **exact engine** (a cycle-accurate interpreter), about 10-20x slower. That is the ~26 fps after the ship.

With `GOW_VU1N_X64=1`, a block without native code is translated **at its first dispatch-slot setup** into x86-64
machine code. This takes ~10-65 µs per block, needs no compiler or files, and works on any toolchain build (MSVC or
clang). The block is registered in the same registry as the build's blocks, so it runs through the same dispatcher
(`runNative`), with the same flag, timing and chaining machinery.

Launcher: Performance tab → "Compile new areas while playing (experimental)" sets `GOW_VU1N_X64=1`
(`launcher/src/lanzador.cpp`).

## 2. Where the code is

All in the runtime, patch `engine/patches/18-vu1-x64-jit.patch`:

| File (engine/runtime/…) | Role |
|---|---|
| `PS2Recomp/ps2xRuntime/src/lib/vu/ps2_vu1_x64.inl` | the JIT: decode, translator, helpers, inline tier, emitter, code arena, compile + register |
| `PS2Recomp/ps2xRuntime/src/lib/vu/ps2_vu1_native.inl` | includes it; `slotFor` calls `vu1x::compile` on a miss; `[vu1x]` line in `GOW_VU1N_DIAG` |
| `PS2Recomp/ps2xRuntime/include/runtime/ps2_vu1_native.h` | `VU1NativeAccess::chainFn` (the block-to-block tail jump), `NativeState::jitHash` |
| `PS2Recomp/ps2xRuntime/src/lib/vu/ps2_vu1_jit.inl` | patch 17's clang background compiler; patch 18 passes missed entries as `--heads` |
| `tests/vu1_jit_test.cpp` | procedural micro memory; mode `x64` must print the compiled-in digest |
| `tests/vu1_x64_fuzz_test.cpp` | random VU programs; JIT vs JIT-without-inline vs clang-built generator code vs exact engine |
| `tools/ci/pruebas_vu1.cmake` | CMake targets of those tests (include it in a runtime build to get them) |

The translator mirrors `tools/vu1/vu1n_gen.py` (runtime repo, patched by 10, 13, 17). **Rule: a change to the
semantics in `vu1n_gen.py` (`gen_block`, `emit_upper`, `emit_lower`, `lower_info`, `classify`, flag model) must be
ported to `vu1x::translate` and its helpers in the same change.** The fuzz test catches a missed port, as long as its
generator covers the instruction (§6).

## 3. Architecture

### 3.1 Translation (`vu1x::translate`, port of `gen_block`)

Input: the block's words as `slotFor` reads them (`nativeExtent`: up to 64 pairs, ending at a branch + delay slot, an E
pair + its delay pair, or a D/T pair). Output: a `Block`, made of a list of `Stmt` (helper function + `Imm` operands +
optional inline kind) plus end-of-block data. The block summary holds:
- `ebit` and `endPc`;
- `readsEntry` (bit 16 of the registered pair count: the block reads flags written before it, so `runNative` gives it
  exact entry timing);
- `VU1TailDesc`;
- `VU1NativeLanes`.

It follows `gen_block` step by step:
1. **Structural checks.** These are the same `None` cases as the generator: a branch anywhere but the second-to-last
   pair, a branch in a delay slot, a branch with E/D/T, CLIP and FCSET in one pair, and the h1 + (h2 | h3) read/write
   hazard between the lower and upper op. Unsupported blocks stay in the exact engine and are remembered
   (`State::failed`).
2. **Flag writers.** MAC writers are ADD/SUB/MADD/MSUB/MUL with DEST ≠ 0 (`macW`). Clip writers are CLIP or FCSET
   (`clipW`).
3. **Per pair:**
   - the VI backup (`hBackup`) for a branch in the next pair;
   - the branch decision (`hBranch`, conditional reads go through the backup);
   - the upper op, then the lower op. When the upper writes what the lower reads, the lower runs first; with the I bit,
     the upper runs and then `s.i = qnorm(imm)`;
   - the D/T exit (`hHalt`), with flush lists ported from `flush()`.
4. **Block end** (`flush_final`): tail stores (`hTailQ` / `hTailC`), the newest MAC writer pushed with
   `pushMacRaw(…, tail)`, the newest clip writer with `pushClipTail(…, tail)`. Then either `return kVu1nEnded | end`
   (E bit) or `hNext` (taken ? target : end) followed by the chain.
5. **Flag reads** (FCEQ/FCAND/FCOR/FCGET/FMEQ/FMAND/FMOR) take a `FlagSrc`: the writers 1-3 pairs before (visible when
   `n.cyc[i] - n.cyc[j] >= 4`, newest first), then the newest writer 4+ pairs before, then the entry value
   (`macAt` / `clipAt`). This is `visible()` in the generator, unrolled.
6. **Clean operands.** For each operand, `ld` (raw) is used when the lanes are known clean inside the block, otherwise
   `ldn` (Inf/NaN → ±FLT_MAX). The entry assumption is **vf00 only**, so `laneReq` is always 0 and the dispatcher never
   checks entry lanes for a JIT block. The build's blocks may assume more on entry (proved over the micro memory's
   control flow); `ld` and `ldn` only differ on dirty lanes, so the results are the same.

### 3.2 Statements and helpers

Each `Stmt` corresponds to exactly one line `vu1n_gen.py` would write. Its helper (`hFmac`, `hLQ`, `hSpecial`,
`hFlagOp`, …) runs that line with the same `vu1n::` functions from `ps2_vu1_native.h` that the generated C++ uses.
Runtime DEST masks go through dispatch tables of the template instantiations (`stfRt`, `itofDispatch`, …), so the code
is the same as in the build, by construction.

Temporaries live in the block's `Frame` on the stack (`q[64]` unclamped FMAC results, `m[64]` MAC values, `c[64]` clip
values, `vib[64]` VI backups, `taken`, `target`).

### 3.3 Inline tier (`emitInline`, default on, `GOW_VU1X_INLINE=0` turns it off)

SSE code for the hot statements: FMAC (all ADD/SUB/MUL/MAX/MINI/MADD/MSUB forms; broadcast, Q, I and vector operands;
`nrm` normalisation; clamp; DEST-masked store), MOVE, LQ/SQ/LQI/SQI, IADDIU/ISUBIU/IADDI/IADD/ISUB/IAND/IOR, and the
I-bit store (constant-folded).

Every inline sequence copies the helper instruction for instruction: same operand order, same constants, same masks.
The rules that keep it exact:
- **MADD / MSUB:** compute `p = a*b` and `r = acc ± p`. If any lane of `|p|` or `|r|` is above `0x7F7FFFFE`, the
  inline code jumps to `hFmac`, which redoes the whole statement from the unchanged state, including the wide
  evaluation.
- **MAC value `m{i}`:** computed (by `hMacVal`) only when a flag op of the block reads it (`Imm::macM`). `q{i}` is
  always stored.

### 3.4 Emitter, ABI, memory

- **Prologue.** Pushes rbx, r12, r13, r14, r15 (5 pushes keep rsp 16-aligned), then reserves 32 bytes of shadow space
  plus the `Frame`. Registers: rbx = `VU1NativeCtx *`, r12 = frame, r13 = next pc, r14 = `VU1State *`, r15 = VU data.
- **Helper calls.** `helper(n, frame, imm)`, with arguments in rdi/rsi/rdx (System V) or rcx/rdx/r8 (Windows x64).
  Only xmm0-xmm5 are used, so the callee-saved xmm6-15 on Windows are never touched.
- **Halt exit.** A statement with `exitIfNonZero` (D/T halt) returns its value from the block when it is non-zero.
- **End.** `hNext` → `VU1NativeAccess::chainFn(n, next)` (chain()'s bookkeeping, then the next block's function) →
  when it returns non-null, the epilogue runs and the code does a tail jump to that function with `n` in the first
  argument register; when null, the block returns `next | kVu1nDone`.
- **Code memory.** 1 MB read-write-execute chunks (`VirtualAlloc` / `mmap`), never freed; `FlushInstructionCache` on
  Windows. Blocks and their `Imm` data are never freed either, the same lifetime as the build's code.
- **Threading.** Compilation runs on the VU1 thread, under a mutex. The registry is only touched by the VU1 thread (one
  VU1 thread in this runtime).

## 4. Environment variables

| Variable | Effect |
|---|---|
| `GOW_VU1N_X64=1` | turns the JIT on (the launcher's "Compile new areas while playing") |
| `GOW_VU1X_INLINE=0` | helpers only (A/B checks, bisecting a wrong image) |
| `GOW_VU1N_DIAG=1` | every 5 s: `[vu1n]` counters plus `[vu1x] compiled=… unsupported=… codeKB=… avgCompileUs=…` |
| `GOW_VU1N_VERIFY=<n>` | compares native runs (JIT blocks included) with the exact engine, as for the build's blocks |
| `GOW_VU1_NATIVE_OFF=1` | no native blocks at all (exact engine only) |

## 5. Results (2026-10-26, clang 18 on Linux; Windows through MinGW + Wine)

| Check | Result |
|---|---|
| `vu1_jit_test x64 2000` | digest `7c9d4a139489ff09` = the same blocks compiled in by the build (4000 cases) |
| Fuzz, inline vs calls | equal digests, seeds 1-12 (4 images × 6 trials) |
| Fuzz, JIT vs clang-built generator code (every entry a head) | equal digests and equal native block counts, run by run: seeds 1, 4, 5, 7, 11 |
| Soak | 20 images × 10 trials: 4,800 runs, 1.55 M native blocks, 1,323 blocks compiled (1.1 MB code), no failure |
| Windows x64 ABI (MinGW-w64 GCC build under Wine) | `7c9d4a139489ff09`; fuzz seeds 1 and 4 equal to Linux; inline = calls for seed 7 |
| Speed, transform loop (8 vertices) | exact engine 17.3 µs; JIT 1.27 µs (inline) / 1.48 µs (calls); build's code 0.82 µs |

The seed 7 difference between Linux and Windows-GCC exists in the **exact engine alone** (`fuzz exact`): it is a
GCC-vs-clang difference in existing runtime code, not the JIT. The game's Windows builds use clang or MSVC.

**Not tested yet: the real game.** Watch the `[vu1x]` line, the frame rate after the ship, `GOW_VU1N_VERIFY=2000` with
the JIT on, and picture glitches. If something looks wrong, try `GOW_VU1X_INLINE=0` first: if that fixes it, the bug is
in an inline sequence; if not, it is in the translator or a helper.

## 6. How to test after a change

Build the runtime with the tests (Linux shown; Windows the same with the project's toolchain):

```sh
# in a runtime checkout with engine/patches applied
cmake -S PS2Recomp -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_CXX_FLAGS="-fno-strict-aliasing -fwrapv" -DPS2X_RELEASE_LTCG=OFF -DPS2X_BUILD_STUDIO=OFF \
      -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_RECOMP=OFF \
      -DCMAKE_PROJECT_PS2RetroX_INCLUDE=$PWD/tools/ci/pruebas_vu1.cmake
ninja -C build gow_vu1_jit_test gow_vu1_jit_aot_test gow_vu1_x64_fuzz_test
build/gow_vu1_jit_aot_test - 2000      # prints the reference digest (7c9d4a139489ff09 for the current test)
build/gow_vu1_jit_test x64 2000        # must print the same digest
for s in 1 2 3 4 5 6; do GOW_FUZZ_SEED=$s build/gow_vu1_x64_fuzz_test x64 4 6; GOW_FUZZ_SEED=$s build/gow_vu1_x64_fuzz_test x64-calls 4 6; done
FLAGS="-O3 -DNDEBUG -std=gnu++20 -march=native -ffp-contract=off -fno-strict-aliasing -fwrapv -I$PWD/PS2Recomp/ps2xRuntime/include"
GOW_FUZZ_SEED=4 build/gow_vu1_x64_fuzz_test module /tmp/fuzzmod tools/vu1/vu1n_gen.py python3 clang++ "$FLAGS" 4 6
```

- Equal `digest` lines = pass. When they differ, set `GOW_FUZZ_DUMP=<file>` on both runs and diff the files: they
  have one line per run (image, trial, pc, digest, native blocks).
  - A different **native block count** means the two sides cover different blocks: coverage, not semantics. Check the
    heads, and the unsupported shapes in `translate` vs `gen_block`.
  - A different **digest** with the same count is a semantic difference in some statement.
- Keep test sizes small (4-6 images, ≤10 trials). The module oracle compiles each image in ~10 s with every entry as a
  head.
- **New instruction or form:** add it to `Gen::lower()` / `Gen::upper()` in the fuzz test, or the comparison never
  exercises it.

## 7. How to extend

- **Supporting a statement inline:**
  1. give the `Stmt` an `InlineKind` in `translate`;
  2. write the SSE sequence in `emitInline`, mirroring the helper exactly;
  3. run the fuzz in `x64` vs `x64-calls` on several seeds.

  Legacy SSE memory operands need 16-byte alignment: use the `kConst` table for constants and `movups` for VU
  registers and VU memory.
- **Faster code (ideas, in order of gain per effort):**
  1. Keep VF registers in xmm registers across consecutive inline statements (today every statement loads and stores
     `VU1State`).
  2. Inline the flag reads and `hNext` (pure frame arithmetic).
  3. Inline `macValRt` (it needs a 16-entry table).
  4. Use AVX (VEX) encodings when the CPU has them: no alignment rules, three-operand forms.
  5. Cross-block entry assumptions, as `vu1n_gen.py` does, to drop `ldn` where it is provably unneeded. That requires
     registering `laneReq` correctly.
- **Other platforms:** the JIT is x86-64 only (`VU1X_SUPPORTED`). On other CPUs the include compiles to nothing and the
  background clang compiler (patch 17) or the build's blocks remain.

## 8. Known limits and risks

- **No unwind tables.** The JIT code registers none with the OS, so an exception that unwinds through a JIT frame would
  terminate the game. The helpers and the VU call-outs do not throw in this runtime; keep it that way, or add
  `RtlAddFunctionTable` (Windows) / `__register_frame` (Linux).
- **Executable memory is RWX.** Some security software or Windows "Arbitrary Code Guard" policies refuse it: the
  allocation then fails and blocks stay in the exact engine (no crash).
- **Windows macros.** `windows.h` defines `near` and `far`, so do not use them as identifiers (`FlagSrc::farJ`). The
  file is syntax-checked with MinGW: `x86_64-w64-mingw32-g++ -fsyntax-only` on `ps2_vu1_core.cpp`.
- **Status register.** The `status` register's sticky bits are not modelled by native blocks, the same as the build's.
  `GOW_VU1N_VERIFY` and the tests leave it out.
- **Every vu1n_gen.py change must be ported** (§2). The fuzz oracle (`module`) uses the Python generator, so it shows
  any drift.
