# AGENTS.md

## Project

This repository is a learning project and demo for the ZX Spectrum family, written in Z80 assembly. The first target is a standard 48K ZX Spectrum. ZX Spectrum Next features will be introduced only after a small, reliable 48K baseline is understood and working.

The initial MVP is a smooth, steady sine-wave text scroller: a message moves from right to left while a gentle sine wave controls the vertical position of its characters.

The human developer is learning Z80 assembly. Explanations, clear register contracts, and small comprehensible changes are therefore part of the deliverable—not optional commentary.

## Toolchain

- Assembler: `sjasmplus` (currently version 1.24.0; executable is on `PATH`)
- Primary target: ZX Spectrum 48K
- Emulators/debuggers: ZXSpin 0.7, Fuse, or CSpect
- Later target: ZX Spectrum Next, primarily through CSpect
- See `tools.md`, `run-demo.bat`, and `launchcspect.bat` for local tool locations and existing launch notes.

Prefer a reproducible command-line build. Generated binaries, symbols, listings, snapshots, or disk images should have clear names and should not be treated as source files.

## Existing material

- `scroller-handover.md` is the detailed history and technical handover. Read it before changing scroller code.
- `scroll.asm` contains useful earlier work and the closest available reference for the original run-time-shifting renderer.
- `later-scroll.asm` contains experiments and ideas, including an unfinished pre-shifted-font path. It is not a trusted baseline and is known not to work correctly.

The old files are evidence and reference material. Do not assume the project must continue from the most complicated version; a careful clean implementation is preferred.

## Working approach

1. Establish the smallest working program and a one-command SjASMPlus build.
2. Add one behaviour at a time: screen addressing, one glyph, arbitrary pixel alignment, multiple glyphs, horizontal scrolling, then sine displacement.
3. Assemble after every meaningful change and run in an emulator whenever visual behaviour changes.
4. Keep the simple correct renderer as a reference before attempting optimisations.
5. Introduce Spectrum Next features only after the 48K MVP is stable and understood.

Correctness and understanding come before speed. Avoid combining ports, redesigns, and optimisations in one change. Do not repair the experimental pre-shifted-font implementation in place unless explicitly asked; redesign and test it independently after the baseline works.

## Assembly conventions

- Use SjASMPlus syntax consistently.
- Prefer descriptive global routine/data labels and scoped local labels for internal branches.
- Avoid unexplained magic numbers; use named constants for addresses, dimensions, timings, and buffer sizes.
- Comment why code is necessary, especially where Spectrum display layout or Z80 constraints make code non-obvious.
- Keep data, mutable state, tables, buffers, and executable code clearly separated.
- Make the memory map explicit and check that code, buffers, stack, screen memory, and system areas cannot overlap.
- Do not rely accidentally on ROM contents or undocumented initial register values; document intentional dependencies such as the ROM font at `$3D00`.

Every reusable routine should document its contract, for example:

```asm
; RoutineName
; In:        B = pixel Y, C = pixel X
; Out:       HL = screen address
; Preserves: DE, IX
; Clobbers:  AF, BC, HL
```

Preservation claims must hold on every path. Treat undocumented registers as clobbered.

## Spectrum-specific correctness

- The 48K bitmap occupies `$4000-$57FF`; its pixel-row layout is non-linear.
- Do not advance vertically with a simple linear address assumption. Use and test a dedicated next-pixel-row routine.
- Pixel-aligned glyph drawing must be tested at shifts 0 through 7.
- A shifted 8-pixel glyph may touch two bytes. Clip explicitly at the left and right screen edges and never allow a write past byte column 31.
- Test vertical transitions around pixel rows 7/8, 63/64, and 127/128.
- Keep frame updates synchronized deliberately (initially `HALT` is acceptable with normal 48K interrupts enabled).
- Preserve the intended compositing rule. The reference implementation uses OR drawing; erasing or clearing must not damage neighbouring glyphs unexpectedly.

## Verification

For each change, report:

- the exact SjASMPlus build command and whether it succeeded;
- which emulator or other check was used;
- what was visually or mechanically verified;
- any behaviour that remains unverified.

When changing rendering, test at minimum a byte-aligned X position, all eight horizontal alignments, both screen edges, and a Spectrum display-row discontinuity. Compare exact bitmap bytes where practical, not only screenshots.

Border-colour timing is useful for qualitative profiling, but do not claim cycle counts without calculation or measurement. Optimise only after a stable reference exists, and compare identical workloads.

## Scope discipline

Keep the first MVP intentionally modest: one screen, one message, an 8-pixel-high font, steady right-to-left movement, and a gentle sine path. Avoid music, interrupts, custom Next hardware, elaborate build systems, and precomputed renderer optimisations until this loop works reliably.

Never present experimental code as working. Clearly label assumptions and distinguish assembled, emulator-tested, and merely reasoned-about behaviour.
