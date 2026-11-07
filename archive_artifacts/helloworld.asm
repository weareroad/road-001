; Minimal ZX Spectrum 48K snapshot test.
;
; Build:
;   sjasmplus helloworld.asm
;
; Output:
;   helloworld.sna

    DEVICE ZXSPECTRUM48
    ORG $8000

start:
    di
    ld sp,$ff00

    ; Black border.
    xor a
    out ($fe),a

    ; Clear the 6144-byte pixel bitmap at $4000-$57ff.
    ld hl,$4000
    ld de,$4001
    ld bc,6143
    ld (hl),0
    ldir

    ; Set all 768 attributes to white ink on black paper.
    ld hl,$5800
    ld de,$5801
    ld bc,767
    ld (hl),%00000111
    ldir

    ; Draw at character column 10, pixel row 80.
    ; Pixel row 80 begins at $4840 in the Spectrum bitmap.
    ld hl,message
    ld de,$484a

.nextCharacter:
    ld a,(hl)
    or a
    jr z,.finished

    push hl                 ; Preserve the message pointer.
    push de                 ; Preserve this character's screen address.
    call GetGlyphAddress

    ; At this Y position, consecutive glyph rows are $100 bytes apart.
    ld b,8
.drawRow:
    ld a,(hl)
    ld (de),a
    inc hl
    inc d
    djnz .drawRow

    pop de
    inc de                  ; Move one character column to the right.
    pop hl
    inc hl
    jr .nextCharacter

.finished:
    ei
.forever:
    jr .forever

; GetGlyphAddress
; In:        A = ASCII character in the range 32-127
; Out:       HL = address of its 8-byte glyph in the Spectrum ROM
; Preserves: DE
; Clobbers:  AF, BC, HL
GetGlyphAddress:
    sub 32
    ld l,a
    ld h,0
    add hl,hl               ; Character index * 2
    add hl,hl               ; Character index * 4
    add hl,hl               ; Character index * 8
    ld bc,$3d00             ; Spectrum ROM font base
    add hl,bc
    ret

message:
    db "HELLO WORLD",0

    SAVESNA "helloworld.sna",start
