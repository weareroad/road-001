    org $8000
    jp start

; Set to 1 to show frame-time phases in the border:
;   yellow  = clearing the hidden hardware-screen band
;   red     = rendering the message into the hidden screen
;   cyan    = flipping the completed hardware screen into view
;   magenta = one PT3 audio replay tick
;   black  = waiting/remaining frame time
PROFILE_BORDER equ 0

PAGING_PORT          equ $7ffd
PAGING_BANK_7        equ %00000111
PAGING_SHADOW_SCREEN equ %00001000
PAGING_48K_ROM       equ %00010000
PAGING_INITIAL       equ PAGING_48K_ROM|PAGING_BANK_7
SYSTEM_BANKM         equ $5b5c

ATTR_BRIGHT_RED   equ %01000010
ATTR_BRIGHT_YELLOW equ %01000110
ATTR_BRIGHT_BLUE  equ %01000001

; Keep the runtime stack in fixed bank 2 ($8000-$BFFF). The 128K machine
; pages different RAM banks into $C000-$FFFF, so the old $FF00 stack would
; disappear whenever that upper bank changed.
STACK_TOP equ $bfff

FONT_FIRST_CHAR  equ 32
FONT_LAST_CHAR   equ 93
FONT_GLYPH_COUNT equ FONT_LAST_CHAR-FONT_FIRST_CHAR+1

SCROLLER_CENTRE_Y  equ 152
SCROLLER_AMPLITUDE equ 8
SCROLLER_GLYPH_H   equ 8
SCROLLER_TOP_Y     equ SCROLLER_CENTRE_Y-SCROLLER_AMPLITUDE
SCROLLER_HEIGHT    equ SCROLLER_AMPLITUDE*2+SCROLLER_GLYPH_H

    assert SCROLLER_TOP_Y == 144
    assert SCROLLER_TOP_Y >= 128
    assert SCROLLER_TOP_Y+SCROLLER_HEIGHT <= 192

scrollPos:
    dw 0

savedStackPointer:
    dw 0

pagingState:
    db PAGING_INITIAL

hiddenScreenBaseHigh:
    db $c0

message:
    ; one continuous message.
    db "HELLO....              "
    db "IT'S THOSE CHAPS FROM "
    db "WE-ARE-ROAD AGAIN.       "
    db "THIS TIME WE "
    db "BRING YOU OUR HIGHLY-DERIVATIVE "
    db "128K SPECTRUM SCROLLER DEMO, THE "
    db "FIRST IN A SERIES OF 'HOW DO WE "
    db "DO THAT, THEN?' EXPERIMENTS.    "
    db "CONSIDER YOURSELVES WARNED!     "
    db "WE USED CHATGPT TO LEARN HOW TO "
    db "OPTIMISE THE HELL OUT OF OUR BABY"
    db "-STEPS Z80 CODE.                "
    db "THE TUNE IS ADAM'S JUST-SAY-NO PT3 "
    db "FROM OUR FORTHCOMING SPEC-NEXT GAME, "
    db "PLAYGROUND PANIC. THE PT3 REPLAY ROUTINE "
    db "IS FROM VORTEX TRACKER.         "
    db "SEE YOU ON THE SPECTRUM NEXT IN THE "
    db "(FAIRLY) NEAR FUTURE                      "
    db "BYE!!                          "
    db 0

messageEnd:

MESSAGE_LENGTH equ messageEnd-message-1
MESSAGE_WIDTH  equ MESSAGE_LENGTH*8

    ; Message traversal is zero-terminated, so its length does not affect the
    ; amount of rendering performed in one frame. The complete journey length
    ; must fit in the 16-bit scrollPos counter. A separate assertion after the
    ; audio module protects the fixed-bank stack from oversized source data.
    assert MESSAGE_LENGTH > 0
    assert 256+MESSAGE_WIDTH <= $ffff


start:
    di
    ld sp,STACK_TOP
    ld iy,$5c3a           ; Spectrum ROM system-variable base

    call FakeLoader.Run

    ; Black border.
    xor a
    out ($fe),a

    call InitialiseScreensFromAsset

    call CopyAndThickenFont
    call BuildShiftedFont
    call BuildSineScreenOffsetTable

    call ClearScrollerAreas
    call InitialiseScrollerAttributes

    ; The display and all generated data are now ready. Start playback only
    ; after completing every potentially visible initialization step.
    ld hl,0
    ld (scrollPos),hl

    ; Initialize the PT3 player with the module stored in fixed bank 2.
    ld hl,AudioModule
    call PT3Player.VT_START+3

    im 1
    ei

mainLoop:
    call SelectHiddenScreen

    if PROFILE_BORDER
        ld a,6             ; Yellow: clear the hidden screen band
        out ($fe),a
    endif

    call ClearHiddenScrollBand

    ; Advance and construct the next complete frame off screen.
    ld hl,(scrollPos)
    inc hl
    ld (scrollPos),hl

    if PROFILE_BORDER
        ld a,2             ; Red: hidden-screen rendering begins
        out ($fe),a
    endif

    call DrawMessageToHiddenScreen

    if PROFILE_BORDER
        xor a              ; Black: frame construction is complete
        out ($fe),a
    endif

    ; Keep the old complete screen visible until the next interrupt.
    halt

    if PROFILE_BORDER
        ld a,5             ; Cyan: flip the completed hardware screen
        out ($fe),a
    endif

    ld a,(pagingState)
    xor PAGING_SHADOW_SCREEN
    di
    call WritePagingState
    ei

    if PROFILE_BORDER
        xor a
        out ($fe),a
    endif

    if PROFILE_BORDER
        ld a,3             ; Magenta: one 50 Hz PT3 replay tick
        out ($fe),a
    endif

    call PT3Player.VT_START+5

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
; InitialiseScreensFromAsset
;
; The linked 6912-byte .scr asset lives at $C000 in RAM bank 0. Copy it
; into the normal display in bank 5, then duplicate it into the shadow
; display in bank 7. This leaves bank 7 mapped and bank 5 displayed,
; which is the initial state expected by the double-buffered scroller.
; ------------------------------------------------

InitialiseScreensFromAsset:
    ; Map bank 0 at $C000 while continuing to display bank 5.
    ld a,PAGING_48K_ROM
    call WritePagingState

    ld hl,ScreenAsset
    ld de,$4000
    ld bc,6912
    ldir

    ; Map bank 7 at $C000, still displaying bank 5.
    ld a,PAGING_INITIAL
    call WritePagingState

    ; Bank 5 remains visible at $4000; bank 7 is now at $C000.
    ld hl,$4000
    ld de,$c000
    ld bc,6912
    ldir
    ret

; ------------------------------------------------
; WritePagingState
;
; Writes the 128K paging latch and keeps both our private copy and the ROM
; system copy synchronized. The caller is responsible for excluding
; interrupts while changing the latch.
;
; In:       A = complete value for port $7FFD
; Clobbers: AF, BC
; ------------------------------------------------

WritePagingState:
    ld (pagingState),a
    ld (SYSTEM_BANKM),a
    ld bc,PAGING_PORT
    out (c),a
    ret

; ------------------------------------------------
; ClearScrollerAreas
;
; Removes the asset's pixels from the complete 24-pixel-high scroller band
; on both hardware screens. This means demo.scr does not need to contain a
; perfectly blank lower section. Bank 5 is at $4000 and the mapped bank 7
; shadow screen is at $C000.
; ------------------------------------------------

ClearScrollerAreas:
    ld hl,$5040          ; Pixel row 144 in bank 5
    call ClearScrollerArea

    ld hl,$d040          ; Pixel row 144 in bank 7
    jp ClearScrollerArea

; In: HL = first bitmap byte of the scroller area
; Clobbers: AF, BC, DE, HL
ClearScrollerArea:
    ld b,SCROLLER_HEIGHT

.nextRow:
    push bc
    push hl

    ld (hl),0
    ld d,h
    ld e,l
    inc de
    ld bc,31
    ldir

    pop hl
    call NextLowerThirdPixelRow
    pop bc
    djnz .nextRow
    ret

; ------------------------------------------------
; InitialiseScrollerAttributes
;
; Installs three stationary colour stripes behind the scroller on both
; hardware screens. Bitmap pixels adopt these colours as they pass through.
; ------------------------------------------------

InitialiseScrollerAttributes:
    ; Normal screen, bank 5: attribute rows 18, 19 and 20.
    ld hl,$5a40
    ld a,ATTR_BRIGHT_RED
    call FillAttributeRow

    ld hl,$5a60
    ld a,ATTR_BRIGHT_YELLOW
    call FillAttributeRow

    ld hl,$5a80
    ld a,ATTR_BRIGHT_BLUE
    call FillAttributeRow

    ; Shadow screen, bank 7 mapped at $C000.
    ld hl,$da40
    ld a,ATTR_BRIGHT_RED
    call FillAttributeRow

    ld hl,$da60
    ld a,ATTR_BRIGHT_YELLOW
    call FillAttributeRow

    ld hl,$da80
    ld a,ATTR_BRIGHT_BLUE
    call FillAttributeRow
    ret

; FillAttributeRow
; In:        HL = first attribute byte, A = attribute value
; Clobbers:  BC, DE, HL
FillAttributeRow:
    ld (hl),a
    ld d,h
    ld e,l
    inc de
    ld bc,31
    ldir
    ret

; DrawMessageToHiddenScreen
;
; Draws the message directly into whichever 128K hardware screen is hidden.
;
; Destroys: AF, BC, DE, HL, IX
; ------------------------------------------------

DrawMessageToHiddenScreen:
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

    call DrawShiftedChar8ToHiddenScreen

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



; ------------------------------------------------
; SelectHiddenScreen
;
; Chooses the CPU address base of the screen that the ULA is not currently
; displaying. Bank 7 remains mapped at $C000 throughout the demo.
; ------------------------------------------------

SelectHiddenScreen:
    ld a,(pagingState)
    and PAGING_SHADOW_SCREEN
    jr z,.shadowIsHidden

    ld a,$40             ; Bank 7 visible: bank 5 at $4000 is hidden
    ld (hiddenScreenBaseHigh),a
    ret

.shadowIsHidden:
    ld a,$c0             ; Bank 5 visible: bank 7 at $C000 is hidden
    ld (hiddenScreenBaseHigh),a
    ret

; ------------------------------------------------
; ClearHiddenScrollBand
;
; Clears 24 non-linear screen rows with sixteen zero-word pushes per row.
; SP is restored before any call and before returning. Interrupts remain
; disabled whenever SP points into screen memory.
; ------------------------------------------------

ClearHiddenScrollBand:
    di
    ld (savedStackPointer),sp

    ; SCROLLER_TOP_Y=144 has offset $1040 within either screen bank.
    ld a,(hiddenScreenBaseHigh)
    add a,$10
    ld h,a
    ld l,$40
    push hl
    pop ix               ; IX = start of current hidden-screen row

    ld b,SCROLLER_HEIGHT

.nextRow:
    ld sp,(savedStackPointer)
    push ix
    pop hl
    ld de,32
    add hl,de
    ld sp,hl             ; Stack starts just after this 32-byte row

    ld hl,0
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl

    ld sp,(savedStackPointer)
    push ix
    pop hl
    call NextLowerThirdPixelRow
    push hl
    pop ix

    djnz .nextRow

    ld sp,(savedStackPointer)
    ei
    ret

; ------------------------------------------------
; GetHiddenScreenAddressForX
;
; Converts an X coordinate directly to its sine-wave address in whichever
; hardware screen is currently hidden.
;
; In:        C = pixel X
; Out:       HL = hidden-screen byte address
; Clobbers:  AF, DE, HL
; ------------------------------------------------

GetHiddenScreenAddressForX:
    ; The sine phase is (X / 2) MOD 64. Each table entry is a 16-bit
    ; precomputed row offset, so double the phase for the lookup.
    ld a,c
    srl a
    and 63
    add a,a
    ld l,a
    ld h,0
    ld de,SineScreenOffsetTable
    add hl,de

    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl             ; HL = screen offset relative to bank base

    ld a,c
    srl a
    srl a
    srl a
    or l                 ; Row addresses are byte-column aligned
    ld l,a

    ld a,(hiddenScreenBaseHigh)
    add a,h
    ld h,a
    ret

    macro DRAW_HIDDEN_SHIFTED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        inc hl
        ld a,(ix+rowOffset+1)
        ld (hl),a
        dec hl
        call NextLowerThirdPixelRow
    endm

    macro DRAW_HIDDEN_ALIGNED_ROW rowOffset
        ld a,(ix+rowOffset)
        or (hl)
        ld (hl),a
        call NextLowerThirdPixelRow
    endm

; ------------------------------------------------
; DrawShiftedChar8ToHiddenScreen
;
; In:        IX = prepared glyph, C = screen X
; Out:       none
; Clobbers:  AF, DE, HL
; ------------------------------------------------

DrawShiftedChar8ToHiddenScreen:
    call GetHiddenScreenAddressForX

    ld a,c
    and 7
    jr z,.aligned

    DRAW_HIDDEN_SHIFTED_ROW 0
    DRAW_HIDDEN_SHIFTED_ROW 2
    DRAW_HIDDEN_SHIFTED_ROW 4
    DRAW_HIDDEN_SHIFTED_ROW 6
    DRAW_HIDDEN_SHIFTED_ROW 8
    DRAW_HIDDEN_SHIFTED_ROW 10
    DRAW_HIDDEN_SHIFTED_ROW 12
    DRAW_HIDDEN_SHIFTED_ROW 14
    ret

.aligned:
    DRAW_HIDDEN_ALIGNED_ROW 0
    DRAW_HIDDEN_ALIGNED_ROW 2
    DRAW_HIDDEN_ALIGNED_ROW 4
    DRAW_HIDDEN_ALIGNED_ROW 6
    DRAW_HIDDEN_ALIGNED_ROW 8
    DRAW_HIDDEN_ALIGNED_ROW 10
    DRAW_HIDDEN_ALIGNED_ROW 12
    DRAW_HIDDEN_ALIGNED_ROW 14
    ret

; ------------------------------------------------
; NextLowerThirdPixelRow
;
; Specialized row advance for the production band at Y=144-167. This path
; cannot cross a 64-pixel screen third and its low byte cannot overflow.
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
; BuildSineScreenOffsetTable
;
; Converts each signed sine value into a Spectrum bitmap address offset
; relative to the start of either hardware screen. Called once at startup.
;
; Clobbers: AF, BC, DE, HL
; ------------------------------------------------

BuildSineScreenOffsetTable:
    ld ix,sineTable
    ld de,SineScreenOffsetTable
    ld b,64

.nextValue:
    push bc

    ld a,(ix+0)
    add a,SCROLLER_CENTRE_Y
    ld b,a
    ld c,0
    call GetScreenAddress

    ; GetScreenAddress returns a normal-screen address in $4000-$57FF.
    ; Removing bit 6 turns it into an offset suitable for either screen base.
    res 6,h

    ld a,l
    ld (de),a
    inc de
    ld a,h
    ld (de),a
    inc de

    inc ix

    pop bc
    djnz .nextValue
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

; Alignment makes the hot-path shared-glyph page arithmetic possible.
    align 256

; Eight shifts * 16 bytes for each supported glyph.
ShiftedFont:
    defs FONT_GLYPH_COUNT * SHIFTED_GLYPH_SIZE,0

; 64 little-endian screen offsets generated from sineTable at startup.
SineScreenOffsetTable:
    defs 64 * 2,0

; Keep the third-party player in its own namespace: its original source uses
; short global names such as START, PLAY and INIT that would otherwise collide
; with demo labels. Code and writable state both remain in fixed bank 2.
    module PT3Player
        include "third_party/vt_sound/PT3PROM-sjasmplus.asm"
    endmodule

AudioModule:
    incbin "just_say_no.pt3"
AudioModuleEnd:

AUDIO_MODULE_SIZE equ AudioModuleEnd-AudioModule

; Leave at least 1 KB between persistent data and the downward-growing stack.
    assert AudioModuleEnd < STACK_TOP-$0400
