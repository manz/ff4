;; Caller patches for init_bg_scroll_hdma after relocation to bank $21.
;; Vanilla `JSL $01EBD2` at $02:818A becomes `JSL $21EBD2`.
;; (In LoROM bank $21 is the only thing that changes; offset $EBD2 within
;; the bank is identical so internal in-bank JSR/JMP targets stay valid.)

*=0x02818A
    jsr.l init_bg_scroll_hdma
