"""Dev-build switches (a816.toml [defines], off in release): jump straight to the ending, or to the item picker."""
.import "core/preamble"
.import "core/vanilla"


.if TRIGGER_ENDING_CUTSCENE {
; all effects are the Ending cutscene
    .alloc at 0xc436 {
    lda #0x39
    nop
    }
}

.if DEBUG_SHOW_ITEM_WINDOW {
; Hijack ExecEvent to always run F7 (select item) with Baron Key
; event_cmd_f7 ($00:ED97) expects: X points to script, $09d5+X+1 = item ID
    .alloc at 0x00E1EB {
    lda #0xD1
    sta.w event_script + 1
    lda #0xFF
    sta.w event_script + 2
    ldx #0x0000
    stx 0xb3
    jmp.w event_cmd_f7
    }
}
