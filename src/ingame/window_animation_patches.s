/* Final Fantasy IV Instant Window Patch
   Targets Bank 0x01 based on the menu.asm disassembly labels. */

/* --- open_window Override (@83E3) ---
   Replaces the 25-frame vertical wipe loop with a single DMA. */
*= 0x0183E3
open_window:
    sep #0x20           ; 8-bit A (shorta)
    lda #0x7E           ; Source RAM bank for tilemap buffers
    sta 0x21
    rep #0x10           ; 16-bit X/Y (longi)
    ldx.w 0x35          ; VRAM destination address
    stx.w 0x1D
    ldx.w 0x29          ; Source tilemap buffer address (RAM)
    stx.w 0x1F
    rep #0x20           ; 16-bit A (longa)
    lda #0x0C80         ; Size for full window buffer (25 rows * 128 bytes)
    sta.w 0x22
    sep #0x20           ; 8-bit A
    /* jsr WaitVblank */ ; Removed loop delay
    jsr.w TfrVRAM       ; Perform instant DMA
    rts

/* --- close_window Override (@8417) ---
   Clears the VRAM area instantly by pointing to the empty part of the buffer. */
*= 0x018417
close_window:
    sep #0x20
    lda #0x7E
    sta 0x21
    rep #0x10
    ldx.w 0x35          ; VRAM destination address
    stx.w 0x1D
    rep #0x20
    lda.w 0x29          ; Source tilemap buffer address
    clc
    adc #0x0C00         ; Offset to the 'empty/closed' window state tiles
    tax
    stx.w 0x1F          ; Set source pointer
    lda #0x0C80         ; Full size
    sta.w 0x22
    sep #0x20
    jsr.w TfrVRAM       ; Perform instant DMA
    rts

/* --- transform_window Override (@84D0) ---
   Skips the coordinate growth loop and jumps directly to final dimensions. */
*= 0x0184D0
transform_window:
    phb : phk : plb     ; Setup Bank Registry for local access
    sep #0x20
    /* Snap current coordinates ($63-$66) to target coordinates ($67-$6A) instantly */
    lda.w 0x67 : sta.w 0x63
    lda.w 0x68 : sta.w 0x64
    lda.w 0x69 : sta.w 0x65
    lda.w 0x6A : sta.w 0x66

    /* Draw the final static window components */
    jsr.w DrawWindowRowTop
    jsr.w DrawWindowRowBtm
    jsr.w DrawWindowColLeft
    jsr.w DrawWindowColRight

    /* Sync to PPU once */
    jsr.w WaitVblank
    lda.w 0xC3          ; Current menu window BG index
    ldx.w #TfrBGTilesTbl ; Address of jump table at @85B8
    jsr.w ExecJumpTbl
    jsr.w UpdateScrollRegs_far

    /* Point the engine's transformation pointers to an RTS to finish the state.
       Vanilla FF4 uses @858C as the terminal RTS for this routine. */
    ldx.w #0x858C
    stx.w 0x01CD
    stx.w 0x01D0
    plb
    rts