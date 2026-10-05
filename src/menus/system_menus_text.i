"""
System-menu text plumbing: JML thunks redirecting bank-01 entry points to relocated text routines. The
pointer-load macro lives in system_menus_macros.i.
"""
.include "src/menus/system_menus_macros.i"

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
