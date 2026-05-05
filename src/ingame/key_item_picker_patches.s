

"""
Key-item picker ROM patches.

Hijack vanilla ShowItemWindow at $00:AF4D (NOT $00:AF4B — the
ff4decomp notes file is off by 2 bytes  ; the real entry verified via
EventCmd_f7's `JSR $AF4D` opcode at $00:ED9B-$ED9D in vanilla bytes).

EventCmd_f7 ($00:ED96) flow:
  $00:ED98: INX  ; advance script PC
  $00:ED99: STX $B3  ; save script PC
  $00:ED9B: JSR $AF4D  ; <-- ShowItemWindow entry
  $00:ED9E: JSR ...

Replace 4 bytes at $00:AF4D-$00:AF50 with `JSL key_item_init_impl`.
init_impl ends with RTL (from engine_init_rolling_buffer macro), pops
24-bit return = $00:AF51, where we stash an RTS to bail back to
EventCmd_f7's $00:ED9E continuation.

Vanilla bytes at $00:AF4D-$00:AF52:
  A5 CC      LDA $CC  ; wait-loop: $CC = player gfx flag
  D0 FC      BNE $AF4D
  A9 01      LDA #$01

Patched:
  22 LL MM HH JSL key_item_init_impl
  60          RTS
  A9 01       (vanilla LDA #$01 stays — never reached after RTS)
"""

.if TREASURE_INVENTORY_ROLLING {
; Bank-$00 trampoline (placed first so the *=$00AF67 patch can resolve
; the symbol forward).
    *=0x00BB40
key_item_render_trampoline:
    jsr.l key_item_render_all
    rts

; Replace vanilla `JSR UpdateItemText` at $00:AF67 (3 bytes) with a
; JSR to the bank-$00 trampoline at $00:BB40. Vanilla preamble
; (InitItemList + WaitVblankLong) before this call stays; vanilla
; input loop + IRQ slide animation after this call stays. Render
; writes into BG3 buffer at $7E:D600 — vanilla NMI ($00:9447 /
; TfrBG3) transfers to VRAM each vblank since $EB=$01 has been
; latched at $00:AF53.
    *=0x00AF67
    jsr key_item_render_trampoline
}
