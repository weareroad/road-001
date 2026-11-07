# ROAD-001 : ZX Spectrum 128K sine-scroller demo

https://youtu.be/oSsJlL5o9Cw

A ZX Spectrum demo and Z80 assembly learning project. The current demo targets
the 128K Spectrum and combines:

- a static full-screen `.scr` image;
- a smooth, double-buffered sine-wave text scroller;
- fixed red, yellow and blue colour bands behind the scroller; and
- PT3 music played through the 128K AY sound chip.

The core effect was first developed for the 48K Spectrum. That working version
is retained separately, while the active 128K version uses the extra RAM for
hardware screen flipping and AY music. A Spectrum Next version may follow
later, but this demo deliberately uses standard 128K hardware.

## Current status

The active demo is working in ZXSpin's 128K mode. Earlier rendering stages were
also checked in Fuse.

The renderer builds each frame on the hidden hardware screen and flips it into
view only when complete. The current message and PT3 replay remain within one
50 Hz frame in emulator testing. Border profiling is normally disabled.

Before the main presentation, a reusable fake cassette loader reproduces a
short ROM-style loading sequence and reports the demo's internal project name.

## Requirements

- SjASMPlus on `PATH` (currently tested with version 1.24.0)
- a ZX Spectrum 128K emulator; ZXSpin 0.7 is the primary development emulator

CSpect is intended primarily for the eventual Spectrum Next phase.

Current Fuse releases automatically interpret 128K `.sna` files as Pentagon
snapshots because the format has no machine-identification field. Consequently
this snapshot is not a reliable standard-128K test in Fuse unless that emulator
behaviour changes. Selecting 128K manually does not override it.

## Build and run

Run:

```text
build.bat
```

This assembles `main.asm` and creates `road-001.sna`. Open that snapshot in
ZXSpin configured as a ZX Spectrum 128K; it starts the demo automatically.

The former 48K build and standalone experiments are retained in
`archive_artifacts/`, but they are not part of the active build workflow.

## Customising the demo

### Message

Edit `message` near the beginning of `road-001.asm`.

The adjacent `db` strings are assembled as one continuous message, not
displayed as separate lines. Using 32-character source lines is convenient but
not required. The terminating zero is not part of the text.

The renderer is zero-terminated and only processes characters that can be
visible, so a longer message does not increase the work performed per frame.
Its complete pixel journey must fit the 16-bit scroll-position counter, and the
assembled program must retain its reserved stack space. Both conditions are
checked at assembly time. The practical memory limit is reached well before
the counter's theoretical limit of roughly 8,159 characters.

The font supports characters from ASCII 32 (space) through 93 (`]`). Uppercase
letters, digits, spaces and basic punctuation in that range are suitable. The
32-character source lines are only a convenient editing layout; use as many
lines as needed and terminate the combined message with `db 0`.

### Loader project name

Edit `FakeLoader.ProgramName` near the top of `loader.asm`. It must contain
exactly ten characters, padded with trailing spaces like a real Spectrum tape
header:

```text
ProgramName:
    db "road-01   "
```

This one value supplies both the audible synthetic header block and the visible
`Program: road-01` caption. The assembler checks its fixed width.

In the active build, `FakeLoader.Run` returns directly to normal demo
initialization after the final fake data burst. The former standalone loader
test wrapper and snapshot are retained under `archive_artifacts/` for reference.

### Static graphic

Replace `demo.scr` with a standard 6,912-byte Spectrum screen dump:

- bytes 0-6143 are the bitmap;
- bytes 6144-6911 are the 32 by 24 attribute grid.

`main.asm` links this file into RAM bank 0. At startup it is copied to both
hardware screen banks, so the artwork remains stationary while the display is
flipped.

The scroller uses pixel rows 144-167. Those bitmap rows are deliberately
cleared on both screens after loading the image, so the source graphic does not
have to leave them blank. Attribute rows 18-20 are then replaced with bright
red, yellow and blue ink on black paper. Everything outside that band is
preserved from `demo.scr`.

In other words, the reserved scroller band is **144-167 inclusive**, not the
whole lower section from 144-191. Static artwork may safely occupy pixel rows
0-143 and 168-191. Any bitmap pixels in rows 144-167 will be erased during
startup, while pixels above and below that band remain untouched.

Set `USE_SCREEN_ASSET` in `main.asm` to `0` to build with a blank placeholder
instead of including `demo.scr`.

### Music

The current module is `just_say_no.pt3`. To use another PT3 module, replace
that file or change the `incbin` filename at `AudioModule` near the end of
`road-001.asm`.

The bundled replay routine is Vortex Tracker's PT3 player from
`third_party/vt_sound/PT3PROM-sjasmplus.asm`. Its licence is retained in
`third_party/vt_sound/LICENSE`.

### Scroller colours

The three fixed ink colours are defined near the top of `road-001.asm` as
`ATTR_BRIGHT_RED`, `ATTR_BRIGHT_YELLOW` and `ATTR_BRIGHT_BLUE`.

The attributes remain stationary; the moving bitmap takes on each colour as it
passes through the corresponding row.

### Border profiling

Set `PROFILE_BORDER equ 1` near the top of `road-001.asm` to display the
frame phases in the border:

- yellow: clear the hidden scroller band;
- red: render the message;
- cyan: flip the completed screen;
- magenta: replay one PT3 tick;
- black: remaining frame time.

Return it to `0` for the finished presentation.

## Startup sequence

The active build starts in this order:

1. Run the fake cassette-loading sequence on a standard white screen.
2. Copy `demo.scr` into screen bank 5 and shadow-screen bank 7.
3. Copy and thicken the ROM font.
4. Generate the horizontally shifted font data and sine-address table.
5. Clear the complete 24-pixel-high scroller bitmap band on both screens.
6. Install the red, yellow and blue scroller attributes on both screens.
7. Reset the scroll position and initialize PT3 playback.
8. Enable interrupts and enter the frame loop.

During playback, each frame clears and renders into the hidden screen, waits
for the frame boundary, flips the completed screen into view, and advances the
music player.

## 128K memory design

- `$8000-$BFFF`, fixed bank 2: program, generated font/tables, PT3 player,
  module and stack
- bank 0 at `$C000`: linked startup `.scr` asset
- bank 5 at `$4000`: normal hardware screen
- bank 7 at `$C000`: shadow hardware screen during playback

The startup asset is only needed while the screens are initialized. Bank 7 is
then left mapped for the double-buffered renderer.

## Source guide

- `main.asm` - active 128K entry point, components, screen asset and snapshot
  packaging
- `road-001.asm` - active demo, renderer, initialization and music
- `loader.asm` - reusable fake cassette-loader component
- `demo.scr` - replaceable static Spectrum screen image
- `just_say_no.pt3` - current replaceable music module
- `third_party/vt_sound/` - PT3 replay routine and licence
- `pt3-audio.asm` - retained standalone PT3 integration reference; not an
  active build input
- `AGENTS.md` - project conventions for coding-agent work
- `archive_artifacts/` - superseded 48K builds, standalone loader/audio tests,
  early renderers, snapshots, alternative screens and historical handover notes

The older files document the route to the current implementation. They are not
required by the active 128K build and should remain isolated from active-source
changes unless a historical comparison is explicitly requested.
