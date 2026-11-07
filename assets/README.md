# Spectrum screen asset

Place the demo's static loading/background screen in the project root as:

```text
demo.scr
```

The file must be a standard 6,912-byte ZX Spectrum screen dump:

- bytes 0-6143: bitmap data for pixel rows 0-191;
- bytes 6144-6911: the 32x24 colour-attribute grid.

The intended composition is a static graphic in the upper two-thirds and a
mostly blank lower third. At startup the build copies this image into both
128K hardware screen banks. The demo then overwrites attribute rows 18-20
(pixel rows 144-167) with its fixed red/yellow/blue scroller colours.

After adding `demo.scr`, set `USE_SCREEN_ASSET equ 1` in `main.asm` and run:

```text
build.bat
```
