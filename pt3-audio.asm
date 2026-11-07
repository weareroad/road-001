; Isolated Spectrum 128K PT3 playback experiment.
;
; The player is initialized once, then called exactly once after each 50 Hz
; frame interrupt. Border profiling shows player cost in red.

    org $8000
    jp AudioStart

PROFILE_PT3 equ 1
AUDIO_STACK_TOP equ $bfff

AudioStart:
    di
    ld sp,AUDIO_STACK_TOP
    ld iy,$5c3a

    ; Black border and a clean white-on-black display.
    xor a
    out ($fe),a

    ld hl,$4000
    ld de,$4001
    ld bc,6143
    ld (hl),a
    ldir

    ld hl,$5800
    ld de,$5801
    ld bc,767
    ld (hl),%00000111
    ldir

    ; VT_START+3 initializes the player with the module address in HL.
    ld hl,AudioModule
    call VT_START+3

    im 1
    ei

.playLoop:
    halt

    if PROFILE_PT3
        ld a,2
        out ($fe),a       ; Red: one PT3 replay tick
    endif

    call VT_START+5       ; PLAY: call once per 50 Hz frame

    if PROFILE_PT3
        xor a
        out ($fe),a
    endif

    jr .playLoop

    include "third_party/vt_sound/PT3PROM-sjasmplus.asm"

AudioModule:
    incbin "just_say_no.pt3"
AudioModuleEnd:

AUDIO_MODULE_SIZE equ AudioModuleEnd-AudioModule

