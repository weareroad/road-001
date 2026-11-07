# ZX Spectrum 48K Sine-Scroller Handover

## Purpose and evidence level

This project is a Z80-assembly scrolling-text effect for the **48K ZX Spectrum**. It draws multiple 8-pixel-high characters at arbitrary pixel X positions, moves them vertically along a sine wave, and ORs their pixels into the Spectrum bitmap.

This document separates three evidence levels:

- **TESTED / WORKING** — explicitly reported working in the development conversation.
- **PARTLY TESTED** — some behaviour was observed, but the complete path was not correct.
- **UNVERIFIED / BROKEN** — experimental code that must not be treated as a baseline.

The original assembler source was not attached to the handover session. Consequently, this document does **not** invent missing instruction sequences, cycle counts, or register-preservation guarantees. Contracts below distinguish confirmed inputs/outputs from details that must be checked against the recovered source.

## Target and intended toolchain

- Machine: ZX Spectrum 48K
- CPU: Z80
- Existing emulator/debugger: ZXSpin
- Existing assembler: ZXSpin's built-in assembler
- Planned assembler: SjASMPlus
- Suggested development environment: VS Code plus Codex, with ZXSpin retained for running, stepping, memory inspection, and border timing
- Previously suggested origin: `$8000` (verify against the recovered source before relying on it)

## Current project state

### TESTED / WORKING baseline

The following capabilities were explicitly reported as working before the pre-shifted-font experiment:

1. Spectrum bitmap-address calculation for an arbitrary pixel position.
2. Advancing through consecutive Spectrum pixel rows despite the display file's non-linear layout.
3. Drawing an 8-row character at arbitrary horizontal pixel alignment.
4. The original, run-time-shifting `DrawChar8` renderer.
5. Thickened font rendering.
6. Sine-wave vertical movement.
7. The multi-character scrolling architecture.
8. A border-colour profiling technique for comparing renderer cost.

The safest recovery point is therefore the multi-character sine scroller using the **original `DrawChar8`**, before `BuildShiftedFont`, `GetShiftedCharacter`, and `DrawShiftedChar8` were introduced.

### PARTLY TESTED latest experiment

The pre-shifted-font version was observed to:

- leave initialisation (a red border was visible),
- draw part of `HELLO`, and
- produce corrupted output resembling pixels travelling down lines at the extreme left and right edges.

This proves only that execution reached the display loop. It does not validate the generated shifted-font data, its lookup, or its renderer.

### UNVERIFIED / BROKEN path

Treat all pre-shifted-font code as broken until independently rebuilt and tested:

- `BuildShiftedFont`
- `GetShiftedCharacter`
- `DrawShiftedChar8`
- the modified `ProcessMessage` drawing branch
- stack/register patches made during the experiment

Do not optimise or repair this path in place before the original renderer has been restored as a clean reference build.

## Routine inventory and register contracts

The table records the strongest claims supported by the conversation. “Verify” means the exact source-level ABI was not retained in the accessible history.

| Routine | Status | Confirmed contract | Preservation/clobbers |
|---|---|---|---|
| `GetScreenAddress` | **TESTED / WORKING** | Input coordinates are carried in `B = pixel Y`, `C = pixel X`; returns the corresponding display-file byte address in `HL`. The drawing code depends on `C` still being available after the call. | Confirm from baseline source. At minimum, regard `HL` as output and do not assume flags or `AF` survive. Verify whether `BC` is formally preserved rather than merely left usable by the current implementation. |
| `NextPixelRow` | **TESTED / WORKING** | Input `HL = current bitmap byte address`; output `HL = same byte column on the next pixel row`, correctly crossing Spectrum character-row/third boundaries. | Confirm from source. Conservatively treat `AF` and `HL` as clobbered/output; do not assume flags survive. |
| `GetSineY` | **TESTED / WORKING** | Converts the scroller's phase/index into the character's Y coordinate used by the drawing path. | Exact input register, output register, table base, range, and clobbers must be recovered from the working source. Do not guess while porting. |
| Original `DrawChar8` | **TESTED / WORKING** | Draws an 8-row glyph at `B = pixel Y`, `C = pixel X`, including non-byte-aligned X positions by shifting at render time. It handles byte-aligned characters without unnecessarily touching a second screen byte. | Exact glyph-pointer register and preservation rules must be recovered. Assume `AF`, `BC`, `DE`, `HL`, and the active glyph pointer may be destroyed until the source proves otherwise. |
| `ProcessMessage` / multi-character loop | **TESTED / WORKING only in the original path** | Advances and draws multiple message characters, obtains per-character sine Y positions, and invokes the original renderer. | Document the live meaning of every register at the call sites during migration; the experimental pre-shifted branch made this fragile. |
| Unrolled run-time-shift renderer | **Reported working, source not retained here** | An optimisation stage existed between the original renderer and pre-shifted fonts. Re-establish only after the original baseline passes. | Recover and measure; do not infer ABI from the broken pre-shifted version. |
| `BuildShiftedFont` | **BROKEN / UNTRUSTED** | Intended to generate eight horizontal shifts per message character, each shift occupying 16 bytes (two bytes per each of eight rows). | Stack, `HL`, `DE`, and `IX` handling were repeatedly patched and remain suspect. Review from scratch. |
| `GetShiftedCharacter` | **UNVERIFIED** | Intended inputs included a character/message index in `A` and shift amount in `C`, returning a pointer to a 16-byte shifted glyph, apparently in `IX`. | Verify all arithmetic, table layout, bounds, and clobbers. |
| `DrawShiftedChar8` | **BROKEN / UNVERIFIED** | Experimental contract: `IX = 16-byte pre-shifted bitmap`, `B = pixel Y`, `C = pixel X`; intended to OR eight rows into the display. | A proposed version declared `AF`, `BC`, `DE`, `HL`, and `IX` destroyed, but that version was not confirmed working. |

### Contract policy for the migrated source

Every public routine should have a header in this form:

```asm
; RoutineName
; In:       B = ...; C = ...
; Out:      HL = ...
; Preserves: DE, IX
; Clobbers: AF, BC, HL
```

“Preserves” must mean preserved on every path, including early returns. Treat undocumented registers as clobbered while cleaning up the code.

## What the known-good renderer must preserve

The original `DrawChar8` is the behavioural oracle. A replacement must match all of these properties:

- Eight source rows are drawn.
- Pixel X may be any value, not merely a multiple of eight.
- A non-zero bit shift can affect two adjacent display bytes.
- A byte-aligned glyph writes only its left display byte.
- Moving to the next pixel row uses `NextPixelRow`, not a linear `INC HL` assumption.
- Screen writes do not wrap from byte column 31 into unrelated display memory.
- The chosen compositing behaviour (reported as OR drawing) remains unchanged.

Do not substitute the experimental `DrawShiftedChar8` for this routine when establishing the baseline.

## Pre-shifted-font layout that was attempted

The intended layout appears to have been:

- 8 horizontal shifts per message character;
- 8 pixel rows per shift;
- 2 bytes per row;
- therefore 16 bytes per shifted glyph and 128 bytes per message character.

The conversation gave the example `HELLO WORLD` as an 11-character message, for a total of:

```text
11 characters × 8 shifts × 16 bytes = 1,408 bytes ($0580)
```

If such a buffer began at `$9000`, its inclusive range would be `$9000..$957F`. That address was an example, not a confirmed allocation. The real build must prove that the buffer does not overlap code, font data, variables, the display, or the active stack.

For shift zero, the first 16 bytes for a glyph should alternate:

```text
source row 0, $00,
source row 1, $00,
...
source row 7, $00
```

Inspecting this first block in the debugger is a useful generator test before any drawing code is enabled.

## Known and suspected bugs in the pre-shifted-font attempts

### 1. Fragile dual use of `HL`

`BuildShiftedFont` used `HL` both as ordinary pointer state and as a temporary 16-bit shifted bitmap, including code of the form:

```asm
ld h,a
ld l,0
```

That is valid only if every live pointer formerly held in `HL` is safely preserved and restored. The stack and pointer lifetime were not convincingly correct.

### 2. Register lifetime across `GetCharacterBitmap`

`GetCharacterBitmap` modifies `DE` and `HL`, while `IX` was also advanced during generation. Although `PUSH IX`/`POP IX` was used in an attempt to restore a font pointer for each shift, the combined contract remained fragile. Repeated patches made the full stack/register state difficult to reason about.

### 3. Drawing two bytes for shift zero

An experimental `DrawShiftedChar8` wrote both bytes of every 16-byte shifted glyph even when `X & 7 == 0`. At the right edge this can write past byte column 31, corrupting an unrelated location in the Spectrum's non-linear screen map.

The proposed correction was to skip the right-byte screen write for shift zero while still advancing over both bytes in the 16-byte glyph record. **This correction was proposed but not verified**, so it belongs in a future unit test, not in the trusted baseline.

### 4. Edge clipping/wrapping was not established

Even for non-zero shifts, a character whose left byte is column 31 has no in-bounds right byte. The renderer needs an explicit clipping policy. Blindly incrementing `HL` at the edge is incorrect.

### 5. Over-complicated `ProcessMessage` register juggling

The experimental draw branch pushed `BC`, copied the horizontal position through `E`/`C`, masked a shift, loaded `messageIndex`, called the shifted-glyph lookup, restored `BC`, and then drew. This makes it easy for the lookup contract and drawing coordinates to disagree. Rewrite the call site with named memory variables or a short, documented register schedule.

### 6. Buffer overlap was considered but not proven to be the fault

The user reported that `ShiftedFont` was not in a dangerous memory position. Keep overlap checks in the build/debug checklist, but do not assume overlap caused the observed corruption.

## Border profiling and timing observations

Border-colour changes were used as a visual profiler: set a distinctive border colour immediately before a region, change it immediately after, and inspect the horizontal width/vertical extent of the colour band in the emulator. On a Spectrum this provides a quick qualitative view of how much frame time a routine consumes.

What is actually established:

- The technique worked well enough to compare renderer revisions.
- It should be retained when reintroducing optimisations.
- A red border in the latest build demonstrated that execution had passed the shifted-font initialisation and reached later code; it did **not** prove that initialisation produced valid data.
- The original run-time renderer and a later unrolled-shift renderer were sufficiently functional to serve as performance comparison points.

What is **not** preserved in the accessible conversation:

- exact T-state counts;
- exact scanline or frame fractions for each version;
- a trustworthy numeric speed-up for pre-shifting.

Do not manufacture those figures. During migration, record both measured border spans and calculated T-states for the same fixed test message and phase. Keep interrupts, border-write overhead, and emulator speed settings consistent between runs.

Suggested profiling brackets:

1. whole frame update;
2. message traversal only;
3. a fixed number of `DrawChar8` calls;
4. shifted-font generation separately from per-frame drawing;
5. lookup plus draw for the eventual pre-shifted implementation.

## ZXSpin assembler quirks encountered

The ZXSpin built-in assembler did not provide the expected reusable local-label behaviour. Labels such as `.loop`, `.nextRow`, and `.done` appeared to behave globally, forcing routine-name prefixes to avoid collisions.

Important distinction:

- `DrawChar8:` is a global label.
- In SjASMPlus, `.loop:` is a local label scoped beneath the preceding global label.
- The leading dot provides local scope; the trailing colon is just a label-definition terminator (and may be optional depending on syntax/settings).
- Local-label rules are assembler-specific, not part of the Z80 instruction set.

Do not perform a blind syntax conversion. Assemble a minimal local-label test with the installed SjASMPlus version, then adopt one consistent style throughout the project.

## Migration plan: ZXSpin assembler to SjASMPlus/Codex

### Phase 1 — recover and freeze a working baseline

1. Recover the last source that used the original `DrawChar8`.
2. Remove or compile out the pre-shifted-font path.
3. Build a snapshot/TAP that reproduces the working multi-character sine scroller.
4. Put source, font assets, generated binary, and launch instructions under Git.
5. Save a screenshot or short capture and record a checksum of the binary as the behavioural baseline.

Exit criterion: the original message scrolls across the screen on the sine path without edge corruption.

### Phase 2 — port without changing behaviour

1. Create an SjASMPlus entry file and retain the existing origin and memory map.
2. Convert labels and directives only as required.
3. Use global routine labels plus scoped local labels such as `.loop`.
4. Add explicit `In`, `Out`, `Preserves`, and `Clobbers` headers.
5. Generate a symbol/listing file and inspect the placement of code, buffers, font data, and stack.
6. Run the resulting binary in ZXSpin and compare it with the frozen baseline.

Exit criterion: the SjASMPlus build is behaviourally identical before any optimisation work starts.

### Phase 3 — restore one optimisation at a time

1. Restore the known working unrolled run-time-shift renderer.
2. Verify output at X alignments 0 through 7 and at both screen edges.
3. Profile it against the original renderer with identical workload.
4. Commit only after correctness and timing are recorded.

### Phase 4 — redesign pre-shifted fonts from a written format

1. Specify the byte layout independently of the generator.
2. Prefer generating shifted data at build time with SjASMPlus macros or a small deterministic asset tool; this removes fragile runtime initialisation and makes the bytes inspectable.
3. Add known-vector checks for one glyph at shifts 0, 1, and 7.
4. Implement lookup arithmetic and test addresses without drawing.
5. Implement drawing with explicit right-edge clipping and a shift-zero fast path.
6. Compare every alignment against the original `DrawChar8` pixel-for-pixel.
7. Only then profile the new path.

### Phase 5 — cleanup

1. Separate screen addressing, sine handling, font data, scroller state, and renderers into clear sections or include files.
2. Replace patched/prefixed internal labels with SjASMPlus local labels.
3. Keep the original renderer available behind a build switch as a correctness oracle.
4. Document the memory map and stack location.
5. Add a reproducible one-command build and brief emulator run instructions.

## Minimum correctness test matrix

For a glyph with pixels in both its leftmost and rightmost columns, compare the reference and candidate renderers at:

- X shifts 0, 1, 2, 3, 4, 5, 6, and 7;
- X near the left edge;
- X positions whose second byte would be screen column 31;
- X positions whose left byte is screen column 31;
- Y around each Spectrum display discontinuity, especially pixel rows 7/8, 63/64, and 127/128;
- empty glyph, solid glyph, and a recognisable real glyph such as `H`;
- one character and the complete message.

Clear the bitmap before each case and compare the exact screen bytes, not only the visible image.

## First task for the next Codex session

Use this instruction:

> Read `SCROLLER_HANDOVER.md` and inspect the complete assembler source. First identify the last working path that uses the original `DrawChar8`. Document the actual register contracts from the code, build it unchanged with its current assembler if possible, and establish a reproducible visual and binary baseline. Do not repair or reintroduce the pre-shifted-font code until the SjASMPlus port matches that baseline.

## Final warning

The working screen-address, row-advance, sine, and original drawing routines are valuable. Preserve them first. The shifted-font experiment contains multiple interacting pointer, stack, lookup, and edge-write risks; apparent partial output such as part of `HELLO` is not evidence that any one of those stages is correct.
