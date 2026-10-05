"""
System-menu text macros. Header only: no code, no placement, safe to include
from any module that loads a system-menu text pointer.
"""


.macro load_system_menu_text_pointer(pointer) {
    """Bias the system-menu text pointer into Y by stripping the 0x8000 ROM offset."""
    ldy.w #pointer - 0x8000
}
