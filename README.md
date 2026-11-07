# ZX Spectrum sine scroller

A learning project in Z80 assembly, initially targeting the 48K ZX Spectrum. The first milestone is a smooth right-to-left text scroller whose characters follow a gentle sine wave. ZX Spectrum Next features will come later, after the 48K implementation is stable and understood.

## Current baseline

`main.asm` packages the earlier `scroll.asm` implementation as a 48K snapshot. This version uses the simple run-time-shifting character renderer. It deliberately does not use the experimental pre-shifted-font code in `later-scroll.asm`.

Current behaviour intended by the source:

- clear the bitmap on startup;
- copy and thicken the Spectrum ROM font;
- synchronize each update with `HALT`;
- clear the scroller band;
- draw the complete message at arbitrary pixel X positions along a sine path;
- advance left by one pixel per frame and restart after the message leaves the screen.

The source assembles successfully and has been visually confirmed in Fuse and ZXSpin. The message scrolls along the sine path, but the clear-and-redraw frame update is visibly flickery. This version is the correctness reference for subsequent profiling and optimization.

## Build

With SjASMPlus on `PATH`:

```text
build.bat
```

or directly:

```text
sjasmplus main.asm
```

This creates `demo.sna`, a 48K snapshot with execution beginning at `start` (`$8000` via the entry jump).

## Run

Open `demo.sna` in Fuse or ZXSpin. CSpect is primarily reserved for the later Spectrum Next phase.

## Source guide

- `main.asm` — SjASMPlus 48K entry and snapshot packaging.
- `scroll.asm` — current baseline candidate and original renderer.
- `later-scroll.asm` — broken/unfinished optimization experiment; reference only.
- `scroller-handover.md` — detailed history, known issues, and recovery plan.
- `AGENTS.md` — project conventions and verification requirements.

## Next checkpoint

Profile the clear and draw phases independently, then reduce their cost one change at a time while comparing output with this reference renderer.
