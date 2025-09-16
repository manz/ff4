; equip main window
*=0x01dda9
    menu_window(0, 0, 30, 11)

; char 1
*=0x01dd95
  menu_window(0, 0, 30, 11)
; char 2
*=0x01dd99
  menu_window(0, 5, 30, 11)
; char 3
*=0x01dd9d
  menu_window(0, 10, 30, 11)
; char 4
*=0x01dda1
  menu_window(0, 15, 30, 11)
; char 5
*=0x01dda5
  menu_window(0, 20, 30, 11)

; magic
;*=0x01B010
;    ldx.w #0xFF18 + 8

*=0x01dd55
  menu_window(1,0,19,7)

*=0x01dd59
  menu_window(1,5,19,7)

*=0x01dd5d
    menu_window(1,10,19,7)

*=0x01dd61
  menu_window(1,15,19,7)

*=0x01dd65
  menu_window(1,20,19,7)

; magic kind window
*=0x01dd69
  menu_window(23,2,7,7)

; status
*=0x01de01
  menu_window(0,1,29,24)
  menu_window(18,6,12,4)

; clear next line of text in the right menu
*=0x01a974
    ldy.w #0x270
    lda #7
    
; item title
*=0x01dcd2
   menu_window(22, 0, 7, 3)


