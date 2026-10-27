"""
Stub harness for the BRK-handler test: enables native mode + 16-bit registers,
then triggers BRK to exercise `brk_handler` capture.
"""

.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf
.map identifier=2 bank_range=0x7e, 0x7f addr_range=0x0000, 0xffff mask=0x10000 writable=1

; Assembled standalone into WRAM, where the test sets PC; there is no ROM layout to place it in.

*= 0x7E0000  ; noqa: UP001
    clc
    xce
    rep #0x30
    ldx #0xCAFE
    ldy #0xBEEF
    brk #0x42
