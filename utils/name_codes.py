"""Character names are stored in menu codes; the dialog draws them through its own table.

The two tables agree on A-Z, a-z, the digits and the capital accents, not on the lowercase accents or the
punctuation (é is $A0 in the menus, $76 in dialog). `name_codes` maps every menu code to the dialog code of the
same letter, so a name typed at Namingway reads the same in a dialog.
"""

from pathlib import Path


def _single_glyphs(table_file: Path) -> dict[int, str]:
    """`table_file`'s one-byte codes that draw one character."""
    glyphs = {}
    for line in table_file.read_text(encoding="utf-8").splitlines():
        code, _, glyph = line.partition("=")
        if len(code) == 2 and len(glyph) == 1:
            glyphs[int(code, 16)] = glyph
    return glyphs


def name_codes(menu_table: Path, dialog_table: Path) -> bytes:
    """256 bytes: the dialog code for each menu code; a code the dialog has no letter for stays itself."""
    dialog = {}
    for code, glyph in sorted(_single_glyphs(dialog_table).items()):
        dialog.setdefault(glyph, code)
    menu = _single_glyphs(menu_table)
    return bytes(dialog.get(menu.get(code, ""), code) for code in range(256))


def drawable_in_dialog(menu_table: Path, dialog_table: Path, codes: bytes) -> list[int]:
    """The menu `codes` the dialog cannot draw as the same letter."""
    menu = _single_glyphs(menu_table)
    dialog = _single_glyphs(dialog_table)
    mapping = name_codes(menu_table, dialog_table)
    return [code for code in codes if code and dialog.get(mapping[code]) != menu.get(code)]
