"""
System-menu text plumbing: pointer-load helper + JML thunks redirecting bank-01 entry points to relocated text
routines.
"""
.macro load_system_menu_text_pointer(pointer) {
    """Bias the system-menu text pointer into Y by stripping the 0x8000 ROM offset."""
    ldy.w #pointer - 0x8000
}

{
.alloc at 0x018301 {
        jmp.l display_text_in_menus
}
.alloc at 0x0182CD {
        jmp.l load_text_with_destination_in_x
}
.alloc at 0x0180D9 {
        jmp.l display_window_with_text
}
.alloc at 0x018798 {
        jmp.l display_time
}
}
