"""ff4 text measurement and word wrap, on katsuji's `Wrapper` with the game's control codes."""

from pathlib import Path

from katsuji.formats import VwfFont
from katsuji.wrap import Controls, Fixed, Wrapper
from script import Table

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


class TextMetrics:
    """Pixel widths and window wrapping for strings encoded with `table`, set in `font_files`.

    Font index N is the font `0xFE N` switches to.
    """

    def __init__(self, table: Table, font_files: list[str]) -> None:
        self.table = table
        fonts = [VwfFont.decode(Path(font_file).read_bytes()) for font_file in font_files]
        self.wrapper = Wrapper(fonts, FF4_CONTROLS)

    def measure_bytes(self, binary: bytes) -> int:
        return self.wrapper.measure(binary)

    def measure_string(self, line: str, font: int = 0) -> int:
        """Pixel width of `line` started in font `font`."""
        return self.wrapper.measure(self.table.to_bytes(line), font)

    def font_after(self, text: str, font: int = 0) -> int:
        """The font in use once `text`, started in font `font`, is written."""
        return self.wrapper.wrap(self.table.to_bytes(text), 1 << 30, font)[1]

    def word_warp(self, line: str, max_pixel_width: int, start_font_index: int = 0) -> tuple[str, int]:
        """Break `line` into lines narrower than `max_pixel_width`; returns the text and the font in use at its end."""
        wrapped, font_index = self.wrapper.wrap(self.table.to_bytes(line), max_pixel_width, start_font_index)
        return self.table.to_text(wrapped), font_index
