

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
    *=0x00AF4D
    jsr.l key_item_session
    rts
}
