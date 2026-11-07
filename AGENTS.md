# AGENTS.md

## Project

This repository is a learning project and demo for the ZX Spectrum family,
written in Z80 assembly with SjASMPlus.

The project began with a standard 48K Spectrum sine-wave scroller. That
baseline is complete and retained under `archive_artifacts/`. The active target
is now a standard ZX Spectrum 128K, using its two hardware screens for smooth
double buffering and its AY chip for PT3 music. ZX Spectrum Next features are
out of scope until this 128K demo is complete, understood and presentable.

The active demo consists of:

- a reusable fake ROM-style cassette-loading introduction;
- a linked 6,912-byte `.scr` image copied into both hardware screens;
- a one-pixel-per-frame sine-wave text scroller;
- a thickened, startup-generated, horizontally pre-shifted ROM font;
- fixed red/yellow/blue attributes behind the scroller;
- hidden-screen clear/render followed by interrupt-synchronised screen flips;
  and
- 50 Hz PT3 playback through the 128K AY sound chip.

The human developer is learning Z80 assembly. Clear explanations, accurate
register contracts and comprehensible changes are part of the deliverable.
This code is intended for eventual publication, so comments should teach why
the implementation works rather than merely restate instructions.

## Active toolchain

- Assembler: `sjasmplus` 1.24.0, available on `PATH`
- Active target: standard ZX Spectrum 128K
- Primary emulator: ZXSpin 0.7 in 128K mode
- Secondary emulator: Fuse, with an important caveat: current Fuse versions
  interpret every 128K `.sna` as Pentagon because SNA has no machine field
- Future target: ZX Spectrum Next, primarily through CSpect

The reproducible active build is:

```text
build.bat
```

It assembles `main.asm` and produces `road-001.sna`. Do not treat generated
snapshots, symbols, listings or maps as source files.

## Active source and assets

- `main.asm`: 128K device definition, component inclusion, screen asset in RAM
  bank 0, memory assertions and snapshot output
- `road-001.asm`: startup orchestration, paging, renderer, generated font
  data, sine addressing, PT3 integration and frame loop
- `loader.asm`: reusable fake cassette-loader component
- `demo.scr`: replaceable 6,912-byte screen image
- `just_say_no.pt3`: replaceable PT3 module
- `third_party/vt_sound/`: third-party PT3 player and its licence
- `README.md`: public-facing build, customization and architecture guide

`archive_artifacts/` contains superseded experiments, snapshots, standalone
test harnesses and the detailed historical handover. These files are useful
for understanding the development journey but are not active build inputs.
Do not restore or modify archived implementations unless explicitly asked.

## Working approach

1. Preserve the working active build before changing behaviour.
2. Make one conceptually coherent change at a time.
3. Assemble after every meaningful source change with `build.bat`.
4. Ask for emulator verification when appearance, sound or timing changes.
5. Keep profiling evidence separate from assumptions about cycle cost.
6. Keep the standard 128K version clean; do not introduce Next-only features
   into it.
7. Preserve user changes to the message, screen image, PT3 module and project
   name.

Correctness, frame stability and understanding take priority over cleverness.
Optimisations are welcome where required for the 50 Hz budget, but each one
must be explained and checked against the same visible workload.

## Assembly and documentation conventions

- Use SjASMPlus syntax consistently.
- Prefer descriptive global labels and scoped local labels.
- Use named constants for addresses, sizes, colours, timings and bank values.
- Keep executable code, mutable state, generated tables and static assets
  distinguishable.
- Make the memory map and paging assumptions explicit.
- Document intentional ROM dependencies, including the font at `$3D00`.
- Preserve third-party licence and attribution files.
- Avoid non-ASCII punctuation in source comments and repository documentation
  where it may render inconsistently in Windows tools.

Every substantial reusable routine should document:

```asm
; RoutineName
; Purpose:   Why this routine exists
; In:        Register and memory inputs
; Out:       Register and memory outputs
; Preserves: Registers genuinely preserved on every path
; Clobbers:  All other changed registers
```

For optimized routines, also explain:

- the straightforward operation being replaced;
- why the faster representation or instruction sequence is valid;
- table layout, alignment and indexing assumptions;
- self-imposed constraints such as shared glyph shifts or clipped edges;
- stack-pointer repurposing and why interrupts are disabled around it;
- unrolled operations and the exact amount of data they process; and
- what would need changing if dimensions or supported characters change.

Do not claim register preservation unless every branch satisfies it. Treat
undocumented registers as clobbered.

## Current architecture invariants

- Program, generated data, PT3 player/module and stack occupy fixed RAM bank 2
  at `$8000-$BFFF`.
- The downward-growing stack starts at `$BFFF`; assembly must retain at least
  the asserted 1 KB clearance below it.
- The startup `.scr` asset is linked into RAM bank 0 at `$C000`.
- Hardware screen bank 5 is visible at `$4000`; bank 7 is mapped at `$C000`
  for hidden-screen rendering.
- Paging state is mirrored in both `pagingState` and ROM variable `BANKM`.
- The display bitmap uses the Spectrum's non-linear row layout. Never replace
  its row-transition routine with a linear increment.
- The scroller envelope is pixel rows 144-167 inclusive. Startup deliberately
  clears those rows on both screens and replaces attribute rows 18-20.
- The message is zero-terminated. Only potentially visible glyphs are visited,
  so message length should not change frame rendering cost.
- The font supports ASCII 32 through 93. Generated shifted-font indexing and
  page alignment depend on the declared character range and glyph size.
- Frame rendering happens entirely on the hidden screen. The completed screen
  is flipped into view only at the interrupt boundary.
- `PROFILE_BORDER` must normally be zero for presentation builds.

## Spectrum-specific correctness

- Test all eight horizontal pixel alignments.
- A shifted eight-pixel glyph may touch two bytes; clip both display edges and
  never write beyond byte column 31.
- Verify vertical transitions around pixel rows 7/8, 63/64 and 127/128 when
  changing generic screen-address code.
- Keep interrupts disabled whenever the stack pointer is temporarily aimed at
  screen memory for the unrolled clear.
- Keep paging changes atomic with respect to interrupts.
- Maintain identical static artwork and scroller attributes in banks 5 and 7,
  or screen flipping will expose mismatched frames.
- Do not claim exact timing from border colours alone. Use calculated cycles or
  measured emulator/debugger data for numerical claims.

## Verification and handoff

For each source change, report:

- the exact build command and whether it completed without errors or warnings;
- which checks were mechanical and which require emulator testing;
- the expected visible or audible result; and
- anything that remains unverified.

For renderer changes, compare the same message and phase at byte alignment,
all shifted alignments, both horizontal edges and the lower-third screen-row
layout. For loader or PT3 changes, verify both visual timing and sound in an
emulator; successful assembly alone is not sufficient.

Never present experimental code as emulator-verified. Clearly distinguish
assembled, mechanically inspected and visually/audibly tested behaviour.
