; Standard FF4 inventory item layout: 2-byte (id, qty) pairs.
;
; Used by every menu surface that shows player items in single-column

; rolling-buffer form:
;   - Field menu Items submenu       at $7E:1440 (48 slots)
;   - Treasure menu inventory list   at $7E:1440 (same 48-slot array)
;   - Treasure menu drops list       at $7E:FF28 (8 drop slots)
;   - Key-item picker filter buffer  at $7E:0712 (filtered subset of $1440)
;
; Battle inventory at $321A is a separate 4-byte layout (flags + id +
; qty + spell) and gets its own struct in a follow-up plan.

.struct Item {
    byte id
    byte qty
}
