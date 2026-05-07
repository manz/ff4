"""
Dialog-VWF shared header: zero-page variable addresses + macro definitions consumed by every module that
touches dialog VWF state.
"""
; src/vwf.i - VWF module shared definitions
; This header defines zero-page variable addresses used by the VWF system
; Include this in any file that needs to access VWF state

; Base address for VWF variables in zero-page
var_base = 0x23

; VWF state variables
CNTR = var_base  ; Counter for shift routine
CURRENT_C = var_base + 2  ; Current character code (16-bit)
BITSLEFT = var_base + 4  ; Remaining bits in current tile
font_addr = var_base + 6  ; Font data pointer (24-bit: +6, +7, +8)
oldtilepos = var_base + 9  ; Previous tile position
TILEPOS = var_base + 11  ; Current tile position

; Dialog pointer (used by dialog.s)
dialog_ptr = 0x20  ; 24-bit pointer to dialog text

; Control flag
no_wait_for_action = 0xcb  ; If non-zero, skip action button wait
