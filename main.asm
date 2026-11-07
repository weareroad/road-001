; Active ZX Spectrum 128K demo build
;
; Assemble with:
;   sjasmplus main.asm

    DEVICE ZXSPECTRUM128

    INCLUDE "scroller-128.asm"

    SAVESNA "demo-128.sna", start
