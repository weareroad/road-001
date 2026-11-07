; ZX Spectrum 48K sine-scroller baseline
;
; Assemble with:
;   sjasmplus main.asm

    DEVICE ZXSPECTRUM48

    INCLUDE "scroller-stage2.asm"

    SAVESNA "demo.sna", start
