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

The active Spectrum 128K build is:

```text
build.bat
```

This creates `demo-128.sna` from `scroller-128.asm`.

The frozen Spectrum 48K teaser build remains available through:

```text
build-48.bat
```

This creates `demo-48.sna` from `scroller-stage2.asm`.

## Run

Open `demo.sna` in Fuse or ZXSpin. CSpect is primarily reserved for the later Spectrum Next phase.

## Source guide

- `main.asm` — active SjASMPlus 128K entry and snapshot packaging.
- `main-48.asm` — frozen 48K teaser entry and snapshot packaging.
- `scroller-128.asm` — active 128K development source.
- `scroller-stage2.asm` — frozen, scalable 48K teaser source.
- `scroll.asm` — earlier 48K reference implementation.
- `later-scroll.asm` — broken/unfinished optimization experiment; reference only.
- `scroller-handover.md` — detailed history, known issues, and recovery plan.
- `AGENTS.md` — project conventions and verification requirements.

## Next checkpoint

Profile the clear and draw phases independently, then reduce their cost one change at a time while comparing output with this reference renderer.
