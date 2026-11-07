; Reusable fake cassette-loading component for a 48K-compatible Spectrum.
;
; This does not read a tape. It generates ROM-style pulse timings through
; port $FE, producing the familiar speaker noise and loading-border colours.
; The timings are intentionally approximate at instruction level, but retain
; the standard relative pulse lengths and block structure.

; Edit this one fixed-width field for each demo. Spectrum tape headers store
; exactly ten filename characters, padded with spaces.
    module FakeLoader

ProgramText:
    db "Program: "
ProgramName:
    db "road-001  "
ProgramNameEnd:
    db 0

    assert ProgramNameEnd-ProgramName == 10

SCREEN_BITMAP      equ $4000
SCREEN_ATTRIBUTES  equ $5800
ROM_FONT           equ $3d00

ATTR_BLACK_ON_WHITE equ %00111000

; The authentic header pilot uses 8063 pulses (about five seconds). This
; stylised version uses four-fifths of that duration to keep the intro moving.
PILOT_HEADER_PULSES equ 6450
PILOT_DATA_PULSES   equ 3223
FAKE_DATA_BYTES     equ 340

; Run
;
; Plays the complete fake loading sequence and returns with interrupts
; disabled. The caller may then install its real screen and start the demo.
; Clobbers: AF, BC, DE, HL, IX
Run:
    di
    im 1

    call ClearWhiteScreen

    ; Let the untouched white screen register before the tape starts.
    ld b,25
    call WaitFrames

    ; A real header block starts with about five seconds of pilot tone.
    di
    ld a,%00000010          ; Red border, speaker low
    ld (tapeOutput),a
    ld hl,PILOT_HEADER_PULSES
    call EmitPilot
    call EmitSync

    ld a,%00000001          ; Blue/low; header data is yellow/blue
    ld (tapeOutput),a

    ld hl,HeaderPrefix
    ld bc,HeaderPrefixEnd-HeaderPrefix
    call EmitDataBytes
    ld hl,ProgramName
    ld bc,ProgramNameEnd-ProgramName
    call EmitDataBytes
    ld hl,HeaderSuffix
    ld bc,HeaderSuffixEnd-HeaderSuffix
    call EmitDataBytes

    ; The ROM reports the decoded header during the inter-block pause.
    ld ix,ProgramText
    ; The real loader opens the upper-screen channel and prints at its current
    ; position; on a freshly cleared Spectrum that is row 0, column 0.
    ld de,$4000
    call PrintString

    ld b,50
    call WaitFrames

    ; A data block uses the shorter, roughly two-second pilot tone.
    di
    ld a,%00000010
    ld (tapeOutput),a
    ld hl,PILOT_DATA_PULSES
    call EmitPilot
    call EmitSync

    ; Synthetic data lasting about two seconds. No bytes are loaded: this is
    ; purely the audiovisual part of the old cassette experience.
    ld de,FAKE_DATA_BYTES
    call EmitFakeData

    ; Hand control back to the host demo.
    xor a
    out ($fe),a              ; Black border and speaker off
    ret

; ------------------------------------------------------------
; ClearWhiteScreen
; ------------------------------------------------------------

ClearWhiteScreen:
    ld hl,SCREEN_BITMAP
    ld de,SCREEN_BITMAP+1
    ld bc,6143
    ld (hl),0
    ldir

    ld hl,SCREEN_ATTRIBUTES
    ld de,SCREEN_ATTRIBUTES+1
    ld bc,767
    ld (hl),ATTR_BLACK_ON_WHITE
    ldir

    ld a,7                   ; Matching non-bright white border
    out ($fe),a
    ret

; ------------------------------------------------------------
; WaitFrames
;
; In: B = number of 50 Hz frames
; ------------------------------------------------------------

WaitFrames:
    ei
.next:
    halt
    djnz .next
    di
    ret

; ------------------------------------------------------------
; EmitPilot
;
; In: HL = pulse count. Each pulse is close to the ROM's 2168 T-state pilot
; pulse. Red/cyan alternate as the speaker output changes level.
; ------------------------------------------------------------

EmitPilot:
.next:
    ld a,(tapeOutput)
    xor %00010111           ; Red/low <-> cyan/high
    ld (tapeOutput),a
    out ($fe),a

    ld b,158
.delay:
    djnz .delay

    dec hl
    ld a,h
    or l
    jr nz,.next
    ret

; ------------------------------------------------------------
; EmitSync
;
; The standard first and second sync pulses are 667 and 735 T states.
; ------------------------------------------------------------

EmitSync:
    ld b,45
    call EmitPilotStylePulse
    ld b,50
    jp EmitPilotStylePulse

EmitPilotStylePulse:
    ld a,(tapeOutput)
    xor %00010111
    ld (tapeOutput),a
    out ($fe),a
.delay:
    djnz .delay
    ret

; ------------------------------------------------------------
; EmitDataBytes
;
; In: HL = bytes, BC = byte count
; ------------------------------------------------------------

EmitDataBytes:
.next:
    ld a,(hl)
    inc hl
    push hl
    push bc
    call EmitDataByte
    pop bc
    pop hl

    dec bc
    ld a,b
    or c
    jr nz,.next
    ret

; ------------------------------------------------------------
; EmitFakeData
;
; In: DE = number of synthetic bytes
; ------------------------------------------------------------

EmitFakeData:
    ld a,%00000001
    ld (tapeOutput),a

.next:
    ld a,d
    xor e                    ; Changing but deterministic bit pattern
    push de
    call EmitDataByte
    pop de

    dec de
    ld a,d
    or e
    jr nz,.next
    ret

; ------------------------------------------------------------
; EmitDataByte
;
; In: A = byte, most-significant bit emitted first
; ------------------------------------------------------------

EmitDataByte:
    ld d,a
    ld e,8

.nextBit:
    sla d
    ld c,62                 ; Zero bit: two pulses near 855 T states
    jr nc,.durationReady
    ld c,128                ; One bit: two pulses near 1710 T states

.durationReady:
    call EmitDataPulse
    call EmitDataPulse
    dec e
    jr nz,.nextBit
    ret

EmitDataPulse:
    ld a,(tapeOutput)
    xor %00010111           ; Blue/low <-> yellow/high
    ld (tapeOutput),a
    out ($fe),a

    ld b,c
.delay:
    djnz .delay
    ret

; ------------------------------------------------------------
; PrintString
;
; Draws a zero-terminated ROM-font string at a character-aligned position.
;
; In: IX = string, DE = bitmap address of its top-left character cell
; ------------------------------------------------------------

PrintString:
.nextCharacter:
    ld a,(ix+0)
    or a
    ret z
    inc ix

    sub 32
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld bc,ROM_FONT
    add hl,bc

    push de
    ld b,8
.nextRow:
    ld a,(hl)
    ld (de),a
    inc hl
    inc d                    ; Next scanline in this character cell
    djnz .nextRow
    pop de

    inc e
    jr .nextCharacter

tapeOutput:
    db 0

; Standard header-shaped data. ProgramName is inserted between these two
; pieces so changing its single definition updates both sound and display.
HeaderPrefix:
    db $00,$00
HeaderPrefixEnd:

HeaderSuffix:
    dw 0
    dw 0
    dw 0
    db $00
HeaderSuffixEnd:

End:
    endmodule

