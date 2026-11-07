    org $8000
    jp start

; Set to 1 to show frame-time phases in the border:
;   yellow = clearing the off-screen frame buffer
;   red    = rendering the message into the frame buffer
;   cyan   = copying the completed buffer to the visible screen
;   black  = waiting/remaining frame time
PROFILE_BORDER equ 1

FONT_FIRST_CHAR  equ 32
FONT_LAST_CHAR   equ 93
FONT_GLYPH_COUNT equ FONT_LAST_CHAR-FONT_FIRST_CHAR+1

SCROLLER_CENTRE_Y  equ 152
SCROLLER_AMPLITUDE equ 8
SCROLLER_GLYPH_H   equ 8
SCROLLER_TOP_Y     equ SCROLLER_CENTRE_Y-SCROLLER_AMPLITUDE
SCROLLER_HEIGHT    equ SCROLLER_AMPLITUDE*2+SCROLLER_GLYPH_H

; Screen address of pixel row 144, byte column 0. This is deliberately
; fixed because the production scroller now lives wholly in the lower third.
SCROLLER_SCREEN_ADDRESS equ $5040

    assert SCROLLER_TOP_Y == 144
    assert SCROLLER_TOP_Y >= 128
    assert SCROLLER_TOP_Y+SCROLLER_HEIGHT <= 192

charX:
    db 240

charY:
    db 80

scrollPos:
    dw 0

messageIndex:
    db 0

savedStackPointer:
    dw 0

currentShiftOffset:
    db 0

message:
    ; Eight source lines of 32 characters form one continuous message.
    db "WELCOME TO THE ZX SPECTRUM DEMO."
    db "THIS IS A LONGER STAGE TWO TEXT."
    db "THE FONT IS PRE-SHIFTED ONCE.   "
    db "ONLY VISIBLE GLYPHS GET RENDERED"
    db "QUOTES, COMMAS, FULL-STOPS...   "
    db "QUESTIONS? YES! (BRACKETS) TOO. "
    db "AT-SIGNS @ AND AMPERSANDS & WORK"
    db "THANKS FOR WATCHING!            "
    db 0

messageEnd:

MESSAGE_LENGTH equ messageEnd-message-1
MESSAGE_WIDTH  equ MESSAGE_LENGTH*8

    assert MESSAGE_LENGTH <= 256


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
    call BuildShiftedFont
    call BuildSineRowOffsetTable

 ; Initialise scroll position
    ld hl,0
    ld (scrollPos),hl

    im 1
    ei

mainLoop:
    if PROFILE_BORDER
        ld a,6             ; Yellow: clear the next frame
        out ($fe),a
    endif

    call ClearFrameBuffer

    ; Advance and construct the next complete frame off screen.
    ld hl,(scrollPos)
    inc hl
    ld (scrollPos),hl

    if PROFILE_BORDER
        ld a,2             ; Red: off-screen rendering begins
        out ($fe),a
    endif

    call DrawMessageToBuffer

    if PROFILE_BORDER
        xor a              ; Black: frame construction is complete
        out ($fe),a
    endif

    ; Keep the old complete frame visible until the next interrupt.
    halt

    if PROFILE_BORDER
        ld a,5             ; Cyan: publish the completed frame
        out ($fe),a
    endif

    call CopyFrameBufferToScreen

    if PROFILE_BORDER
        xor a
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
    xor a
    ld (messageIndex),a

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

    ; Preserve the screen coordinates while looking up the prepared glyph.
    push bc
    ld a,c
    and 7
    ld c,a
    ld a,(messageIndex)
    call GetShiftedCharacter
    pop bc

    call DrawShiftedChar8

    ; Restore state
    pop de
    pop hl

.advance:
    ; Next character, 8 pixels to the right
    ld a,(messageIndex)
    inc a
    ld (messageIndex),a

    inc hl

    ld a,e
    add a,8
    ld e,a
    jr nc,.nextChar
    inc d
    jr .nextChar

; ------------------------------------------------
; DrawMessageToBuffer
;
; Builds the message in the linear off-screen frame buffer.
; The traversal and clipping match DrawMessage; only the final
; glyph destination differs.
;
; Destroys: AF, BC, DE, HL, IX
; ------------------------------------------------

DrawMessageToBuffer:
    ; Work out whether the message has reached the left edge yet.
    ld hl,(scrollPos)
    ld de,256
    or a
    sbc hl,de             ; HL = scrollPos - 256
    jr nc,.messageEntered

    ; No characters have passed the left edge. Start at message[0] with
    ; X = 256 - scrollPos.
    ld hl,256
    ld bc,(scrollPos)
    or a
    sbc hl,bc
    ex de,hl              ; DE = first character X
    ld hl,message
    jr .setSharedShift

.messageEntered:
    ; One whole character leaves the screen every eight pixels. Skip those
    ; characters immediately instead of traversing the message from its
    ; beginning on every frame.
    ld a,l
    and 7
    push af               ; Remainder determines partial left-edge X

    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                  ; HL = first potentially visible character index

    ld bc,message
    add hl,bc             ; HL = first potentially visible message byte

    pop af
    or a
    jr z,.firstAtZero

    neg
    ld e,a
    ld d,$ff              ; First character begins at X = -1 through -7
    jr .setSharedShift

.firstAtZero:
    ld de,0

.setSharedShift:
    ; All message characters are eight pixels apart and therefore use the
    ; same one of the eight prepared horizontal shifts in this frame.
    ld a,e
    and 7
    add a,a
    add a,a
    add a,a
    add a,a
    ld b,a                ; Keep the shared 0-112 shift offset in B

.nextChar:
    ld a,(hl)
    or a
    ret z

    ; A partially clipped character at the left edge is skipped. The next
    ; character will begin at X = 1 through 7 and can be drawn completely.
    bit 7,d
    jr nz,.advance

    ; Once X has reached 256, every remaining character is also off-screen.
    ld a,d
    or a
    ret nz

    ld a,e
    cp 249
    ret nc

    push hl
    push de

    ; Fast shared-font lookup. Supported ASCII starts at 32; folding that
    ; subtraction into the font page constant avoids SUB in the hot path.
    ; Even glyphs begin at page offset $00, odd glyphs at $80.
    ld a,(hl)
    srl a                 ; Carry = odd/even; A = ASCII / 2
    ld d,a
    ld a,0
    rra
    ld e,a

    ld a,d
    add a,(ShiftedFont >> 8)-(FONT_FIRST_CHAR/2)
    ld d,a

    ld a,b
    add a,e
    ld e,a

    push de
    pop ix

    pop de
    push de
    ld c,e

    call DrawShiftedChar8ToBuffer

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

; ------------------------------------------------
; GetSharedShiftedGlyph
;
; Finds a prepared glyph in the 256-byte-aligned, glyph-major shared font.
; Each glyph occupies 128 bytes; parity selects the low-byte half while
; characterIndex / 2 selects the high byte. The frame's shared shift is a
; 0-112 byte offset that never carries into the next page.
;
; In:        A = supported ASCII character
; Out:       IX = address of its prepared 16-byte shifted glyph
; Preserves: BC
; Clobbers:  AF, DE, IX
; ------------------------------------------------

GetSharedShiftedGlyph:
    ; Unsupported values display as spaces rather than indexing outside
    ; the prepared font table.
    cp FONT_FIRST_CHAR
    jr c,.useSpace
    cp FONT_LAST_CHAR+1
    jr c,.supported

.useSpace:
    ld a,' '

.supported:
    sub FONT_FIRST_CHAR
    srl a                 ; Carry = odd glyph index; A = index / 2
    ld d,a

    ld a,0                ; Convert carry into either $00 or $80
    rra
    ld e,a

    ld a,d
    add a,ShiftedFont >> 8
    ld d,a

    ld a,(currentShiftOffset)
    add a,e
    ld e,a

    push de
    pop ix
    ret


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
; GetFrameBufferAddressForX
;
; Converts an X coordinate directly to its sine-wave row in the
; 32-byte-wide linear buffer.
;
; In:        C = pixel X
; Out:       HL = buffer byte address
; Clobbers:  AF, DE, HL
; ------------------------------------------------

GetFrameBufferAddressForX:
    ; The sine phase is (X / 2) MOD 64. Each table entry is a 16-bit
    ; precomputed row offset, so double the phase for the lookup.
    ld a,c
    srl a
    and 63
    add a,a
    ld l,a
    ld h,0
    ld de,SineRowOffsetTable
    add hl,de

    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl             ; HL = precomputed row * 32

    ld a,c
    srl a
    srl a
    srl a
    ld e,a
    ld d,0
    add hl,de

    ld de,FrameBuffer
    add hl,de
    ret

    macro DRAW_BUFFER_SHIFTED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        inc hl
        ld a,(ix+rowOffset+1)
        ; The right byte is untouched in a cleared, left-to-right render.
        ld (hl),a
        dec hl
        add hl,de
    endm

    macro DRAW_BUFFER_ALIGNED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        add hl,de
    endm

; ------------------------------------------------
; DrawShiftedChar8ToBuffer
;
; In:        IX = prepared glyph, C = screen X
; Out:       none
; Clobbers:  AF, DE, HL
; ------------------------------------------------

DrawShiftedChar8ToBuffer:
    call GetFrameBufferAddressForX
    ld de,32             ; Distance between linear buffer rows

    ld a,c
    and 7
    jr z,.aligned

    DRAW_BUFFER_SHIFTED_ROW 0
    DRAW_BUFFER_SHIFTED_ROW 2
    DRAW_BUFFER_SHIFTED_ROW 4
    DRAW_BUFFER_SHIFTED_ROW 6
    DRAW_BUFFER_SHIFTED_ROW 8
    DRAW_BUFFER_SHIFTED_ROW 10
    DRAW_BUFFER_SHIFTED_ROW 12
    DRAW_BUFFER_SHIFTED_ROW 14
    ret

.aligned:
    DRAW_BUFFER_ALIGNED_ROW 0
    DRAW_BUFFER_ALIGNED_ROW 2
    DRAW_BUFFER_ALIGNED_ROW 4
    DRAW_BUFFER_ALIGNED_ROW 6
    DRAW_BUFFER_ALIGNED_ROW 8
    DRAW_BUFFER_ALIGNED_ROW 10
    DRAW_BUFFER_ALIGNED_ROW 12
    DRAW_BUFFER_ALIGNED_ROW 14
    ret

; Clears all 40 * 32 bytes of the off-screen frame buffer.
ClearFrameBuffer:
    ; Use the stack as a fast 16-bit fill engine. Interrupts must remain
    ; disabled while SP points into the buffer because an interrupt would
    ; otherwise place its return address inside the image.
    di
    ld (savedStackPointer),sp
    ld sp,FrameBuffer+FRAME_BUFFER_SIZE
    ld hl,0

    ; 128 iterations * 3 pushes * 2 bytes = 768 bytes.
    ld b,FRAME_BUFFER_SIZE/6
.clearLoop:
    push hl
    push hl
    push hl
    djnz .clearLoop

    ld sp,(savedStackPointer)
    ei
    ret

; Copies the 24 linear buffer rows to pixel rows 144-167 in the
; Spectrum's non-linear display file.
    macro COPY_EIGHT_BYTES
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
    endm

CopyFrameBufferToScreen:
    ld hl,FrameBuffer
    ld de,SCROLLER_SCREEN_ADDRESS
    ld a,FRAME_BUFFER_HEIGHT

.nextRow:
    push af
    push de

    ; Unrolled LDI is 16 T-states per byte. LDIR would take 21 T-states
    ; for every byte except the last one in each row.
    ld bc,32
    COPY_EIGHT_BYTES
    COPY_EIGHT_BYTES
    COPY_EIGHT_BYTES
    COPY_EIGHT_BYTES

    pop de              ; Restore the start of this screen row
    ex de,hl             ; HL = screen row, DE = next buffer row
    call NextLowerThirdPixelRow
    ex de,hl             ; DE = next screen row, HL = buffer row

    pop af
    dec a
    jr nz,.nextRow
    ret

; ------------------------------------------------
; NextLowerThirdPixelRow
;
; Specialized row advance for the production band at Y=144-167.
; Unlike the general NextPixelRow routine, this path cannot cross a
; 64-pixel screen third and its low address byte cannot overflow.
;
; In:        HL = current lower-third screen row address
; Out:       HL = same byte column on the next pixel row
; Clobbers:  AF, HL
; ------------------------------------------------

NextLowerThirdPixelRow:
    inc h
    ld a,h
    and 7
    ret nz

    ld a,l
    add a,32
    ld l,a

    ld a,h
    sub 8
    ld h,a
    ret

; ------------------------------------------------
; DrawShiftedChar8
;
; Draws one prepared 16-byte glyph. Each of its eight
; rows contains a left byte followed by a right byte.
;
; In:        IX = prepared glyph, B = pixel Y, C = pixel X
; Out:       none
; Preserves: DE
; Clobbers:  AF, BC, HL, IX
; ------------------------------------------------

    macro DRAW_PREPARED_SHIFTED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        inc hl
        ld a,(ix+rowOffset+1)
        or (hl)
        ld (hl),a
        dec hl
        call NextPixelRow
    endm

    macro DRAW_PREPARED_ALIGNED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        call NextPixelRow
    endm

DrawShiftedChar8:
    call GetScreenAddress

    ; Select the one-byte or two-byte path once for the whole glyph.
    ld a,c
    and 7
    jr z,.aligned

    DRAW_PREPARED_SHIFTED_ROW 0
    DRAW_PREPARED_SHIFTED_ROW 2
    DRAW_PREPARED_SHIFTED_ROW 4
    DRAW_PREPARED_SHIFTED_ROW 6
    DRAW_PREPARED_SHIFTED_ROW 8
    DRAW_PREPARED_SHIFTED_ROW 10
    DRAW_PREPARED_SHIFTED_ROW 12
    DRAW_PREPARED_SHIFTED_ROW 14
    ret

.aligned:
    ; The aligned path also avoids writing beyond screen byte column 31.
    DRAW_PREPARED_ALIGNED_ROW 0
    DRAW_PREPARED_ALIGNED_ROW 2
    DRAW_PREPARED_ALIGNED_ROW 4
    DRAW_PREPARED_ALIGNED_ROW 6
    DRAW_PREPARED_ALIGNED_ROW 8
    DRAW_PREPARED_ALIGNED_ROW 10
    DRAW_PREPARED_ALIGNED_ROW 12
    DRAW_PREPARED_ALIGNED_ROW 14
    ret

; ------------------------------------------------
; GetShiftedCharacter
;
; Locates one of eight prepared shifts for a message character.
;
; In:        A = message character index, C = shift (0-7)
; Out:       IX = address of 16-byte prepared glyph
; Preserves: DE
; Clobbers:  AF, HL, IX
; ------------------------------------------------

GetShiftedCharacter:
    push de

    ld l,a
    ld h,0

    ; Each message character occupies 8 shifts * 16 bytes = 128 bytes.
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl

    ld de,ShiftedMessageFont
    add hl,de

    ; Each horizontal shift occupies 16 bytes.
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
; Generates eight prepared horizontal shifts for each
; supported glyph. Called once at startup.
;
; Clobbers: AF, BC, DE, HL, IX
; ------------------------------------------------

BuildShiftedFont:
    ld de,ShiftedFont
    ld a,FONT_FIRST_CHAR

.nextCharacter:
    push af             ; ASCII character
    push de             ; Output pointer
    call GetCharacterBitmap
    pop de

    ld c,0              ; Horizontal shift 0-7

.nextShift:
    push bc
    push ix             ; Return to glyph row zero for every shift
    ld b,8

.nextRow:
    ld a,(ix+0)
    inc ix

    ld h,a              ; H:L is the shifted 16-bit row
    ld l,0

    push bc
    ld b,c

.shiftRow:
    ld a,b
    or a
    jr z,.rowReady

    srl h
    rr l
    djnz .shiftRow

.rowReady:
    pop bc

    ld a,h
    ld (de),a
    inc de
    ld a,l
    ld (de),a
    inc de

    djnz .nextRow

    pop ix
    pop bc

    inc c
    ld a,c
    cp 8
    jr nz,.nextShift

    pop af
    inc a
    cp FONT_LAST_CHAR+1
    jr nz,.nextCharacter
    ret

; ------------------------------------------------
; BuildSineRowOffsetTable
;
; Converts each signed sine value into a 16-bit offset for the linear
; frame buffer: (8 + sine value) * 32. Called once at startup.
;
; Clobbers: AF, BC, DE, HL
; ------------------------------------------------

BuildSineRowOffsetTable:
    ld hl,sineTable
    ld de,SineRowOffsetTable
    ld b,64

.nextValue:
    push bc

    ld a,(hl)
    add a,SCROLLER_AMPLITUDE

    push hl
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl

    ld a,l
    ld (de),a
    inc de
    ld a,h
    ld (de),a
    inc de

    pop hl
    inc hl

    pop bc
    djnz .nextValue
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
    add a,SCROLLER_CENTRE_Y

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
    db 0,1,2,3,3,4,5,5
    db 6,6,7,7,8,8,8,8
    db 8,8,8,8,8,7,7,6
    db 6,5,5,4,3,3,2,1
    db 0,-1,-2,-3,-3,-4,-5,-5
    db -6,-6,-7,-7,-8,-8,-8,-8
    db -8,-8,-8,-8,-8,-7,-7,-6
    db -6,-5,-5,-4,-3,-3,-2,-1

SHIFTED_GLYPH_SIZE equ 128

; Alignment makes GetSharedShiftedGlyph's page arithmetic possible.
    align 256

; Eight shifts * 16 bytes for each supported glyph. The old alias remains
; temporarily for the unused stage-1 reference routines above.
ShiftedFont:
ShiftedMessageFont:
    defs FONT_GLYPH_COUNT * SHIFTED_GLYPH_SIZE,0

FRAME_BUFFER_HEIGHT equ SCROLLER_HEIGHT
FRAME_BUFFER_SIZE   equ 32 * FRAME_BUFFER_HEIGHT

; 64 little-endian offsets generated from sineTable at startup.
SineRowOffsetTable:
    defs 64 * 2,0

; Linear rows corresponding to visible pixel rows 144-167.
FrameBuffer:
    defs FRAME_BUFFER_SIZE,0
