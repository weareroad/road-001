    org $8000
    jp start

; Set to 1 to show frame-time phases in the border:
;   yellow = erasing characters at their old positions
;   red    = drawing the message
;   black  = remaining frame time
PROFILE_BORDER equ 1

charX:
    db 240

charY:
    db 80

scrollPos:
    dw 0

message:
    db "HELLO FROM THE ZX SPECTRUM!   ",0

messageEnd:

MESSAGE_LENGTH equ messageEnd-message-1
MESSAGE_WIDTH  equ MESSAGE_LENGTH*8


start:
    di
    ld sp,$ff00
    ld iy,$5c3a           ; Spectrum ROM system-variable base

    ; Black border.
    xor a
    out ($fe),a

    ; Clear the 6144-byte bitmap
    ld hl,$4000
    ld de,$4001
    ld bc,6143

    xor a
    ld (hl),a
    ldir

    ; White ink on black paper across the whole screen.
    ld hl,$5800
    ld de,$5801
    ld bc,767
    ld (hl),%00000111
    ldir

    call CopyAndThickenFont

 ; Initialise scroll position
    ld hl,0
    ld (scrollPos),hl

    im 1
    ei

mainLoop:
    halt

    if PROFILE_BORDER
        ld a,6             ; Yellow: erase phase begins
        out ($fe),a
    endif

    call EraseMessage

    ; Advance the message before drawing its new position.
    ld hl,(scrollPos)
    inc hl
    ld (scrollPos),hl

    if PROFILE_BORDER
        ld a,2             ; Red: draw phase begins
        out ($fe),a
    endif

    call DrawMessage

    if PROFILE_BORDER
        xor a              ; Black: rendering is complete
        out ($fe),a
    endif

    ; Restart after the message has passed completely off the left edge.
    ld hl,(scrollPos)
    ld de,256+MESSAGE_WIDTH
    or a
    sbc hl,de

    jr c,mainLoop

 ; Yes - restart from the right
    ld hl,0
    ld (scrollPos),hl

    jr mainLoop


; ------------------------------------------------
; EraseMessage
;
; Erases all visible characters at the current
; scroll position. This replaces clearing the whole
; 40-pixel-high scroll band every frame.
;
; Uses:
;   scrollPos
;   message
;
; Destroys: AF, BC, DE, HL
; ------------------------------------------------

EraseMessage:
    ; Starting X = 256 - scrollPos
    ld hl,256
    ld bc,(scrollPos)
    or a
    sbc hl,bc
    ex de,hl             ; DE = signed 16-bit starting X

    ld hl,message

.nextChar:
    ld a,(hl)
    or a
    ret z

    ; Skip characters left of the screen.
    bit 7,d
    jr nz,.advance

    ; Skip characters at or beyond X = 256.
    ld a,d
    or a
    jr nz,.advance

    ; A complete 8-pixel glyph must begin at X <= 248.
    ld a,e
    cp 249
    jr nc,.advance

    push hl
    push de

    ld a,e
    call GetSineY
    ld b,a

    pop de
    push de
    ld c,e
    call EraseChar8

    pop de
    pop hl

.advance:
    inc hl

    ld a,e
    add a,8
    ld e,a
    jr nc,.nextChar

    inc d
    jr .nextChar


;    xor a
;    ld (scrollPos),a
;    ld (scrollPos+1),a

;    jr mainLoop

;    ld a,240
;    ld (charX),a

;mainLoop:
;    halt

    ; Erase old character
;    ld a,(charX)
;    ld c,a
;    ld a,(charY)
;    ld b,a
;    call EraseChar8

    ; Move left
;    ld a,(charX)
;    dec a
;    cp 8
;    jr nc,.storeX
;    ld a,240

;.storeX:
;    ld (charX),a

    ; Calculate new Y
;    call GetSineY
;    ld (charY),a

    ; Draw character at new position
;    ld b,a
;    ld a,(charX)
;    ld c,a
;    ld a, "D"
;    call GetCharacterBitmap
;    ld ix,FontBuffer + $108
;    ld b,80
;    ld c,101

;    call DrawChar8

;    jr mainLoop

; ------------------------------------------------
; DrawMessage
;
; Draws all visible characters of message
; along the sine wave.
;
; Uses:
;   scrollPos
;   message
;
; Destroys: AF, BC, DE, HL, IX
; ------------------------------------------------

DrawMessage:
    ld hl,message

    ; Initial X = 256 - scrollPos
    ld de,256
    ld bc,(scrollPos)

    ex de,hl
    or a
    sbc hl,bc
    ex de,hl

    ld hl,message

.nextChar:
    ld a,(hl)
    or a
    ret z

    ; DE = signed 16-bit X coordinate
    ; Skip characters to the left of screen

    bit 7,d
    jr nz,.advance

    ; Skip characters beyond right edge
    ld a,d
    or a
    jr nz,.advance

    ; E = low byte of X
    ; Only draw if X <= 248
    ld a,e
    cp 249
    jr nc,.advance

    ; Save message pointer and X position
    push hl
    push de

    ; GetSineY destroys HL, so preserve the character separately from
    ; the message pointer before calculating its vertical position.
    ld a,(hl)
    push af

    ; Calculate Y from X
    ld a,e
    call GetSineY
    ld b,a

    ; Restore the character while retaining Y in B.
    pop af

    ; Restore X for drawing
    pop de
    push de
    ld c,e

    ; Get character bitmap
    call GetCharacterBitmap

    call DrawChar8

    ; Restore state
    pop de
    pop hl

.advance:
    ; Next character, 8 pixels to the right
    inc hl

    ld a,e
    add a,8
    ld e,a
    jr nc,.nextChar
    inc d
    jr .nextChar


; ------------------------------------------------
; GetCharacterBitmap
;
; Input:
;   A = ASCII character (32-127)
;
; Output:
;   IX = pointer to character bitmap
;
; Destroys:
;   AF, DE, HL, IX
; ------------------------------------------------

GetCharacterBitmap:
    sub 32              ; Convert ASCII to font index

    ; Multiply by 8
    ld l,a
    ld h,0

    add hl,hl           ; x2
    add hl,hl           ; x4
    add hl,hl           ; x8

    ld de,FontBuffer
    add hl,de

    push hl
    pop ix              ; IX = bitmap address

    ret


; ------------------------------------------------
; CopyAndThickenFont
;
; Copies and thickens 96 characters
; from $3D00 into FontBuffer.
;
; ------------------------------------------------

CopyAndThickenFont:
    ld hl,$3D00
    ld de,FontBuffer
    ld bc,768

.loop:
    ld a,(hl)
    push bc             ; Preserve byte counter

    ld b,a              ; Preserve original byte
    srl a
    or b                ; Original OR shifted

    ld (de),a

    pop bc

    inc hl
    inc de
    dec bc

    ld a,b
    or c
    jr nz,.loop

    ret



; B = Y coordinate
; C = X coordinate
; Assumes X <= 248, Y <= 184

EraseChar8:
    call GetScreenAddress

    ld a,c
    and 7
    ld c,a              ; C = horizontal shift

    ld b,8

.eraloop:
    xor a
    ld (hl),a

    ld a,c
    or a
    jr z,.skipRight

    xor a
    inc hl
    ld (hl),a
    dec hl

.skipRight:

    call NextPixelRow

    djnz .eraloop
    ret

; ------------------------------------------------
; DrawChar8
;
; Input:
;   IX = pointer to 8-byte bitmap
;   B  = Y position
;   C  = X position
;
; Assumptions:
;   X <= 248
;   Y <= 184
;
; Draws using OR (transparent background)
; ------------------------------------------------

DrawChar8:
    call GetScreenAddress

    ld a,c
    and 7
    ld c,a              ; C = shift count

    ld b,8              ; Eight rows

.drawRow:
    push bc
    push hl

    ld a,(ix+0)
    inc ix

    ; D = left byte, E = right byte

    ld d,a
    ld e,0

    ; Select an unrolled shift path. This avoids the loop-control cost of
    ; shifting each row one bit at a time with DJNZ.
    ld a,c
    or a
    jr z,.shiftDone

    cp 4
    jr c,.shift1to3

    ; First four shifts for alignments 4-7.
    srl d
    rr e
    srl d
    rr e
    srl d
    rr e
    srl d
    rr e

    sub 4
    jr z,.shiftDone

.shift1to3:
    dec a
    jr z,.shiftOne

    dec a
    jr z,.shiftTwo

    ; Third remaining shift.
    srl d
    rr e

.shiftTwo:
    srl d
    rr e

.shiftOne:
    srl d
    rr e

.shiftDone:
    pop hl              ; Restore row start

    ld a,d
    or (hl)
    ld (hl),a

    ; Only write second byte if shifted

    ld a,c
    or a
    jr z,.skipRight

    inc hl
    ld a,e
    or (hl)
    ld (hl),a
    dec hl              ; Restore original X!

.skipRight:
    call NextPixelRow

    pop bc
    djnz .drawRow

    ret

; ------------------------------------------------
; NextPixelRow
;
; Input:
;   HL = current screen byte address
;
; Output:
;   HL = address of same X, next pixel row
;
; ------------------------------------------------

NextPixelRow:
    inc h
    ld a,h
    and 7
    ret nz

    ld a,l
    add a,32
    ld l,a
    ret c

    ld a,h
    sub 8
    ld h,a
    ret

; ------------------------------------------------
; GetScreenAddress
;
; Input:
;   B = Y pixel coordinate (0-191)
;   C = X pixel coordinate (0-255)
;
; Output:
;   HL = screen byte address
;
; Destroys: A
; ------------------------------------------------

GetScreenAddress:
    ld a,b
    and %11000000
    rrca
    rrca
    rrca
    or %01000000
    ld h,a

    ld a,b
    and %00000111
    or h
    ld h,a

    ld a,b
    and %00111000
    rlca
    rlca
    ld l,a

    ld a,c
    srl a
    srl a
    srl a
    or l
    ld l,a

    ret


; Input:  A = X coordinate
; Output: A = Y coordinate
; Destroys: DE, HL

GetSineY:
    ; Divide X by 2 to stretch the wave
    srl a

    ; Wrap index to 0-63
    and 63

    ld e,a
    ld d,0
    ld hl,sineTable
    add hl,de

    ld a,(hl)
    add a,80

    ret

; ------------------------------------------------
; ClearScrollBand
;
; Clears screen pixel rows 64-103 inclusive.
; Does not modify colour attributes.
;
; Destroys: AF, BC, DE, HL
; ------------------------------------------------

ClearScrollBand:
    ld b,64
    ld c,0
    call GetScreenAddress

    ld d,40             ; Number of pixel rows

.rowLoop:
    push hl
    ld b,32             ; 32 bytes per screen row
    xor a

.byteLoop:
    ld (hl),a
    inc hl
    djnz .byteLoop

    pop hl
    call NextPixelRow

    dec d
    jr nz,.rowLoop

    ret

FontBuffer:
    defs 768,0


sineTable:
    db 0,2,3,5,6,8,9,10
    db 11,12,13,14,15,15,16,16
    db 16,16,16,15,15,14,13,12
    db 11,10,9,8,6,5,3,2
    db 0,-2,-3,-5,-6,-8,-9,-10
    db -11,-12,-13,-14,-15,-15,-16,-16
    db -16,-16,-16,-15,-15,-14,-13,-12
    db -11,-10,-9,-8,-6,-5,-3,-2
