"""ff4 text measurement and word wrap, on katsuji's `Wrapper` with the game's control codes."""

from pathlib import Path

from katsuji.formats import VwfFont
from katsuji.script import Table
from katsuji.wrap import Controls, Fixed, Wrapper

FF4_CONTROLS = Controls(
    space=0xFF,
    newline=0x01,
    font_switch=0xFE,
    fixed={
        0x03: Fixed(arguments=1, width=0),  # [music] n
        0x04: Fixed(arguments=1, width=6 * 8),  # character name
        0x05: Fixed(arguments=1, width=0),  # [delay] n
        0x06: Fixed(arguments=0, width=0),  # [close_window]
        0x08: Fixed(arguments=0, width=4 * 8),  # gil count
    },
)


NAME = 0x04  # a character's name: `04 n`


class TextMetrics:
    """Pixel widths and window wrapping for strings encoded with `table`, set in `font_files`.

    Font index N is the font `0xFE N` switches to.
    """

    def __init__(self, table: Table, font_files: list[str]) -> None:
        self.table = table
        fonts = [VwfFont.decode(Path(font_file).read_bytes()) for font_file in font_files]
        self.wrapper = Wrapper(fonts, FF4_CONTROLS)
        self.names = self._default_names()

    def _default_names(self) -> dict[int, bytes]:
        """Each name code's spelling in glyphs, the widest where the table spells it two ways (Tella, Tellah)."""
        names: dict[int, bytes] = {}
        for text, code in self.table.lookup.items():
            if len(code) == 2 and code[0] == NAME:
                glyphs = b"".join(self.table.to_bytes(letter) for letter in text)
                if code[1] not in names or self.wrapper.measure(glyphs) > self.wrapper.measure(names[code[1]]):
                    names[code[1]] = glyphs
        return names

    def measure_bytes(self, binary: bytes) -> int:
        return self.wrapper.measure(binary)

    def measure_string(self, line: str, font: int = 0) -> int:
        """Pixel width of `line` started in font `font`, each character name at the widest a player can type."""
        return self.wrapper.measure(self.table.to_bytes(line), font)

    def measure_named(self, line: str, font: int = 0) -> int:
        """`measure_string` with each character name as wide as its default spelling: where a line is placed
        (centred), not whether it fits."""
        return self.wrapper.measure(self._named(self.table.to_bytes(line)), font)

    def _named(self, binary: bytes) -> bytes:
        """`binary` with each name code (`04 n`) spelled out in glyphs: a name is laid out at its default width,
        not the 6 widest letters a player could type (the widest default, Edward, is 37 pixels, 43 in bold)."""
        out = bytearray()
        index = 0
        while index < len(binary):
            code = binary[index]
            if code == NAME and index + 1 < len(binary) and binary[index + 1] in self.names:
                out += self.names[binary[index + 1]]
                index += 2
                continue
            step = 2 if code == FF4_CONTROLS.font_switch else 1 + getattr(FF4_CONTROLS.fixed.get(code), "arguments", 0)
            out += binary[index : index + step]
            index += step
        return bytes(out)

    def font_after(self, text: str, font: int = 0) -> int:
        """The font in use once `text`, started in font `font`, is written."""
        return self.wrapper.wrap(self.table.to_bytes(text), 1 << 30, font)[1]

    def word_warp(self, line: str, max_pixel_width: int, start_font_index: int = 0) -> tuple[str, int]:
        """Break `line` into lines narrower than `max_pixel_width`; returns the text and the font in use at its end."""
        wrapped, font_index = self.wrapper.wrap(self.table.to_bytes(line), max_pixel_width, start_font_index)
        return self.table.to_text(wrapped), font_index
