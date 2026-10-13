"""
The cartridge: its header (title, the board grown to 2 MB ROM + 128 KB SRAM) and, behind ENABLE_BRK_HANDLER, the BRK
trap every `raise` lands in.
"""
.import "@std/snes/header"
.import "core/preamble"
.include "core/bank20.i"


; The cartridge header: the title, and the board grown from SHVC-1A3B to SHVC-1A5B (the vanilla map mode, region,
; maker and checksum fields stay as the ROM has them).
.patch SnesHeader at SNES_HEADER_BASE {
    title = "Final Fantasy IV     "
    cartridge_type = 0x02  ; ROM + RAM + battery
    rom_size = 0x0B  ; 2^11 KiB = 2 MB
    sram_size = 0x07  ; 2^7 KiB = 128 KB
}

.if ENABLE_BRK_HANDLER {
; JML trampoline in vector-table padding; native/emu BRK vectors point here.
    .alloc at 0x00FFE0 {
    jmp.l brk_handler
    }


    .alloc at 0x00FFE6 {
    .dw 0xFFE0
    }


    .alloc at 0x00FFFE {
    .dw 0xFFE0
    }
}


.alloc _brk_trap in bank20_reloc {
brk_handler:
"""
BRK trap: mask interrupts, disable NMI, fetch the BRK signature byte
(the imm operand of `brk #$NN`) into A, then STP. Kintsuki halts on
STP: tooling reads the signature via `emu.get_state().a` and the
crash site via `emu.callstack()`.

CPU push order on BRK: PB, PC.hi, PC.lo, P (PCH/PCL packed as a
16-bit push by the CPU). Pulled in reverse. Pushed PC = BRK + 2:
signature byte sits at PB:(PC - 1).
"""


    sei
    sep #0x20
    lda #0x00  ; disable NMI / auto-joypad
    sta.l cpu_regs.NMITIMEN
    pla  ; A = P (discard)
    rep #0x20
    pla  ; A = pushed PC (= BRK + 2)
    dec  ; A = BRK + 1 (offset of signature byte)
    sta.b 0x00  ; DP $00..$01 = low 16 bits of signature addr
    sep #0x20
    pla  ; A = PB
    sta.b 0x02  ; DP $02 = bank for indirect long
    rep #0x20
    and.w #0x00FF  ; clear high byte of A so signature is the only thing left
    sep #0x20
    lda [0x00]  ; A = signature byte (BRK's #$NN imm)
    stp
}
