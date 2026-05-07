"""
Stub harness for the BRK-handler test: enables native mode + 16-bit registers,
then triggers BRK to exercise `brk_handler` capture.
"""
clc
xce
rep #0x30
ldx #0xCAFE
ldy #0xBEEF
brk #0x42
