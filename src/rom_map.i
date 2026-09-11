"""
The cart's ROM bus map.

`.map` is per translation unit and an imported module does not inherit
the patch-main's, so any module that places code at an absolute address
needs the mapping described where it can see it. Kept in its own header
rather than copied per module: the declaration is identical everywhere
and the linker accepts the repeats.
"""


.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf
