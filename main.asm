; Active ZX Spectrum 128K demo build
;
; Assemble with:
;   sjasmplus main.asm

    DEVICE ZXSPECTRUM128

; Set to 1 after placing a 6912-byte Spectrum .scr file at demo.scr.
USE_SCREEN_ASSET equ 1

    INCLUDE "scroller-128.asm"
    INCLUDE "loader.asm"

; The fake loader is also resident in fixed bank 2. Keep the same minimum
; stack clearance after all active components have been included.
    assert FakeLoader.End < STACK_TOP-$0400

; Store the startup screen in spare RAM bank 0. The active demo code and
; stack remain in fixed bank 2, while bank 7 remains available as the shadow
; screen during playback.
    MMU $c000,0,$c000

ScreenAsset:
    if USE_SCREEN_ASSET
        incbin "demo.scr"
    else
        defs 6912,0
    endif
ScreenAssetEnd:

    assert ScreenAssetEnd-ScreenAsset == 6912

    SAVESNA "demo-128.sna", start
