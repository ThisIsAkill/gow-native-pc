# Translations and languages

## How a disc is recognised

`tools/disc/identify.py` reads `SYSTEM.CNF` (boot ELF name → game profile), the ELF's PCSX2 CRC (→ a known
`[[editions]]` entry) and the SHA-1 of the ELF's `.text`. The recompiled program depends only on `.text`, so any disc
whose code equals the profile's `text_sha1` runs on the same build — the original or a fan translation that changes
only data. Unknown discs with the right code are accepted; their language is guessed from words in the text files
(`[language_hints]`).

## Running a translation

| ISOs given | Result (`data/<id>/discs/`) | Quality |
|---|---|---|
| translation only | `<edition>/`: the translated disc, normalised (see below) | **standalone**: everything translated; movies as on that disc |
| original only | `usa/` | original |
| original + translation | `usa/` and `<edition>-full/`: the original disc with the translation's text files placed past the end of the disc (TOC repointed) and the original executable with the translation's data changes | **full**: translated text, original movies (16:9) |

Normalisation of a standalone disc (`prepare.py normalise`): the IRX modules copied to `IOP_MOD/`; a single-layer
repack without `PART2.PAK` gets its TOC part-1 entries pointed at their part-0 copies; empty widescreen movies
(`.PSW` ≤ 1 sector) point at the 4:3 ones (`.PSS`, shown stretched in 16:9).

Both the standalone and the full PT-BR discs were tested to gameplay (see `docs/tested-hardware.md`).

When more than one language is prepared, the launcher asks once which one to play; **Other → Game text** changes it.
All languages share one memory card (`data/<id>/mc0`).

## Known editions (God of War)

| Edition | ELF CRC | Notes |
|---|---|---|
| USA original (SCUS-97399) | D6385328 | |
| Português (Brasil), romsportugues T3.0 (DVD5) | 5444DDCB | Same code. Translates `R_PERM.WAD`, `R_SHELL.WAD` and ten menu strings in the ELF (difficulties, months, "Vazio"). Single-layer repack: no `.PSW` movies, others re-encoded, WideScreen option hidden. |

Add an edition: run `identify.py` on the ISO, copy its `elf_crc`, add an `[[editions]]` entry with `kind`, `language`
(BCP 47, e.g. `es`, `pt-BR`) and `label`.

## Not supported

- Discs of another region whose code differs (e.g. the European SCES-53133): the recompiled program, function map and
  overrides are built for the USA code. Their languages could be carried over as data (Waffle565's `lang_pack.py`
  did this for the European text and voices) — not implemented here yet.
- Translations that patch code (`.text` differs).
