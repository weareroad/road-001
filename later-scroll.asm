    org $8000
    jp start

charX:
    db 240

charY:
    db 80

scrollPos:
    dw 0
processMode:
    db 0

message:
    db "HELLO WORLD",0

messageEnd:

MESSAGE_LENGTH equ messageEnd-message-1
MESSAGE_WIDTH  equ MESSAGE_LENGTH*8

messageIndex:
    db 0


start:
    ; Clear the 6144-byte bitmap
    ld hl,$4000
    ld de,$4001
    ld bc,6143
    xor a
    ld (hl),a
    ldir

    call CopyAndThickenFont
    call BuildShiftedFont

 ; Initialise scroll position
    ld hl,0
    ld (scrollPos),hl


mainLoop:
    halt

    ; Border RED: rendering starts
    ld a,2
    out ($fe),a

    xor a
    ld (processMode),a
    call ProcessMessage       ; Erase old positions

    ld hl,(scrollPos)
    inc hl
    ld (scrollPos),hl

    ld a,1
    ld (processMode),a
    call ProcessMessage       ; Draw new positions

    ; Border BLACK: rendering finished
    xor a
    out ($fe),a

  ; Check whether message has passed
    ; completely off left edge
    ld hl,(scrollPos)
    ld de,256+MESSAGE_WIDTH

    or a
    sbc hl,de
    jr c,mainLoop

    ; Restart
    ld hl,0
    ld (scrollPos),hl

    jr mainLoop

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
; ProcessMessage
;
; Erases or draws all visible characters
; of the message along the sine wave.
;
; processMode:
;   0 = erase
;   1 = draw
;
; Uses:
;   scrollPos (16-bit)
;   message   (zero-terminated string)
;   currentChar (temporary byte)
;
; Requires:
;   GetSineY
;   GetCharacterBitmap
;   DrawChar8
;   EraseChar8
;
; Destroys:
;   AF, BC, DE, HL, IX
; ------------------------------------------------

ProcessMessage:

    xor a
    ld (messageIndex),a

    ; Calculate starting X = 256 - scrollPos
    ld hl,256
    ld bc,(scrollPos)

    or a
    sbc hl,bc

    ex de,hl             ; DE = starting X
    ld hl,message        ; HL = message pointer

.pmnextChar:
    ld a,(hl)
    or a
    ret z                ; End of message

    ; DE = signed 16-bit X coordinate

    ; Skip negative X positions
    bit 7,d
    jr nz,.pmadvance

    ; Skip X >= 256
    ld a,d
    or a
    jr nz,.pmadvance

    ; Skip X > 248 (character must fit)
    ld a,e
    cp 249
    jr nc,.pmadvance

    ; Save ASCII character
    ld a,(hl)
    ld (currentChar),a

    ; Preserve message pointer and X
    push hl
    push de

    ; Calculate sine Y from X
    ld a,e
    call GetSineY
    ld b,a               ; B = Y

    ; Restore X, retaining stack copy
    pop de
    push de
    ld c,e               ; C = X

    ; Select drawing or erasing
    ld a,(processMode)
    or a
    jr z,.pmerase

.pmdraw:
    ; Preserve coordinates while finding bitmap
    push bc

    ld a,(messageIndex)
    ld c,e
    and a

    ; C must be X MOD 8
    ld a,c
    and 7
    ld c,a

    ld a,(messageIndex)
    call GetShiftedCharacter

    pop bc
    call DrawShiftedChar8

    jr .pmdone

.pmerase:
    call EraseChar8

.pmdone:
    ; Restore X and message pointer
    pop de
    pop hl

.pmadvance:
    ld a,(messageIndex)
    inc a
    ld (messageIndex),a

    inc hl

    ld a,e
    add a,8
    ld e,a
    jr nc,.pmnextChar

    inc d
    jr .nextChar    


; ------------------------------------------------
; Temporary storage
; ------------------------------------------------

currentChar:
    db 0




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

    ; Calculate Y from X
    ld a,e
    call GetSineY
    ld b,a

    ; Restore X for drawing
    pop de
    push de
    ld c,e

    ; Get character bitmap
    ld a,(hl)
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

    ld b,8

.eraloop:
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    dec hl

    call NextPixelRow

    djnz .eraloop
    ret

; ------------------------------------------------
; DrawShiftedChar8
;
; IX = address of pre-shifted bitmap (16 bytes)
; B  = Y coordinate
; C  = X coordinate
;
; Destroys AF, BC, DE, HL, IX
; ------------------------------------------------

DrawShiftedChar8:
    call GetScreenAddress

    ; Save horizontal alignment
    ld a,c
    and 7
    ld c,a

    ld b,8

.dsc8drawRow:
    push bc
    push hl

    ; Left byte
    ld a,(ix+0)
    or (hl)
    ld (hl),a
    inc ix

    ; Right byte
    ld a,c
    or a
    jr z,.dsc8skipRight

    inc hl
    ld a,(ix+0)
    or (hl)
    ld (hl),a
    dec hl

.dsc8skipRight:
    inc ix

    call NextPixelRow

    pop bc
    djnz .dsc8drawRow

    ret
; ------------------------------------------------
; DrawChar8 - optimised version 1
;
; Input:
;   IX = address of 8-byte character bitmap
;   B  = Y coordinate
;   C  = X coordinate
;
; Draws an 8x8 character using OR.
;
; Destroys:
;   AF, BC, DE, HL, IX
; ------------------------------------------------

DrawChar8:
    call GetScreenAddress

    ; Horizontal alignment (X MOD 8)
    ld a,c
    and 7
    ld c,a

    ld b,8

.drawRow:
    push bc
    push hl

    ; Get next font bitmap row
    ld a,(ix+0)
    inc ix

    ld d,a
    ld e,0

    ; Select horizontal shift
    ld a,c
    or a
    jr z,.shiftDone

    cp 4
    jr c,.shift1to3

    ; Shift four times
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

    ; Three additional shifts
    srl d
    rr e

.shiftTwo:
    srl d
    rr e

.shiftOne:
    srl d
    rr e

.shiftDone:
    pop hl

    ; Draw left byte
    ld a,d
    or (hl)
    ld (hl),a

    ; Draw right byte if needed
    ld a,c
    or a
    jr z,.skipRight

    inc hl
    ld a,e
    or (hl)
    ld (hl),a
    dec hl

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
;   B = Y coordinate (0-191)
;   C = X coordinate (0-255)
;
; Output:
;   HL = screen bitmap address
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

; ------------------------------------------------
; GetSineY
;
; Input:
;   A = X coordinate
;
; Output:
;   A = Y coordinate
;
; Destroys: DE, HL
; ------------------------------------------------

GetSineY:
    srl a
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
; Clears the middle third of the Spectrum screen.
; Pixel rows 64-127.
;
; ------------------------------------------------

ClearScrollBand:
    ld hl,$4800
    ld de,$4801
    ld bc,2047

    xor a
    ld (hl),a
    ldir

    ret


; ------------------------------------------------
; GetShiftedCharacter
;
; A = character index
; C = horizontal shift (0-7)
;
; Returns IX pointing at 16-byte bitmap.
;
; Destroys AF, DE, HL
; ------------------------------------------------
GetShiftedCharacter:
    push de

    ld l,a
    ld h,0

    ; Character index * 128
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl

    ld de,ShiftedFont
    add hl,de

    ; Shift offset * 16
    ld a,c
    and 7
    add a,a
    add a,a
    add a,a
    add a,a

    ld e,a
    ld d,0
    add hl,de

    push hl
    pop ix

    pop de
    ret

; ------------------------------------------------
; BuildShiftedFont
;
; Creates eight shifted versions of every
; character in the message.
;
; Each shifted version occupies 16 bytes.
; Each character occupies 128 bytes.
;
; Requires:
;   GetCharacterBitmap
;   FontBuffer already initialised
; ------------------------------------------------

BuildShiftedFont:
    ld hl,message
    ld de,ShiftedFont

.bsfnextChar:
    ld a,(hl)
    or a
    ret z

    push hl
    push de
    call GetCharacterBitmap
    pop de

    ld c,0

.bsfnextShift:
    push bc
    push ix

    ld b,8

.bsfnextRow:
    ld a,(ix+0)
    inc ix

    ld h,a
    ld l,0

    push bc
    ld b,c

.bsfshiftLoop:
    ld a,b
    or a
    jr z,.bsfshiftDone

    srl h
    rr l
    djnz .bsfshiftLoop

.bsfshiftDone:
    pop bc

    ld a,h
    ld (de),a
    inc de

    ld a,l
    ld (de),a
    inc de

    djnz .bsfnextRow

    pop ix
    pop bc

    inc c
    ld a,c
    cp 8
    jr nz,.bsfnextShift

    pop hl
    inc hl
    jr .bsfnextChar



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

SHIFTED_CHAR_SIZE equ 128

ShiftedFont:
    defs MESSAGE_LENGTH * SHIFTED_CHAR_SIZE

