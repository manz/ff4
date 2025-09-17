from script import Table
from pathlib import Path
import struct


class TextMetrics:
    def __init__(self, table: Table, font_files: list[str], char_height: int = 16):
        self.table = table
        self.font_files = font_files
        self.char_height = char_height

        # Load new interleaved format
        self.length_tables = []
        self.kerning_tables = []
        for font_file in font_files:
            length_table, kerning_table = self._load_interleaved_font(
                font_file, char_height
            )
            self.length_tables.append(length_table)
            self.kerning_tables.append(kerning_table)

    def measure_bytes(self, binary: bytes) -> int:
        size = 0
        k = 0
        current_font_index = 0
        prev_char = None

        while k < len(binary):
            char = binary[k]
            match char:
                case 0xFE:
                    k += 1
                    current_font_index = binary[k]
                    prev_char = None  # Reset previous char on font change
                case 0x4:
                    k += 1
                    size += 6 * 8
                    prev_char = None  # Reset previous char after special sequence
                case _:
                    # Add character width
                    char_width = self.length_tables[current_font_index][char]
                    size += char_width

                    # Add spacing (default 1 pixel, adjusted by kerning)
                    spacing = 1
                    if prev_char is not None:
                        # Check for kerning adjustment
                        kerning_pair = (prev_char, char)
                        if kerning_pair in self.kerning_tables[current_font_index]:
                            kerning_value = self.kerning_tables[current_font_index][
                                kerning_pair
                            ]
                            spacing = kerning_value + 1  # Kerning + 1 = actual spacing

                    size += spacing
                    prev_char = char

            k += 1

        return size

    def measure_string(self, line: str) -> int:
        binary_line = self.table.to_bytes(line)
        return self.measure_bytes(binary_line)

    def word_warp(
        self, line: str, max_pixel_width: int, start_font_index: int = 0
    ) -> tuple[str, int]:
        breaking_chars = b"\xff"

        binary_line = self.table.to_bytes(line)
        binary_breaked_line = b""
        current_line_pixel_width = 0
        index = 0
        current_font_index = start_font_index  # Start with provided font index
        prev_char = None  # Reset previous character for each new string

        # Calculate space width with current font context
        space_char = 0xFF  # Space character
        space_width = self.length_tables[current_font_index][space_char] + 1
        while index < len(binary_line):
            next_break_point = binary_line.find(breaking_chars, index)

            if next_break_point != -1:
                next_word = binary_line[index:next_break_point]
                # Measure word with current font context
                next_word_pixel_length = self._measure_bytes_with_context(
                    next_word, current_font_index, prev_char
                )

                if current_line_pixel_width + next_word_pixel_length >= max_pixel_width:
                    current_line_pixel_width = next_word_pixel_length
                    binary_breaked_line += b"\x01"
                    prev_char = None  # Reset after line break
                else:
                    if current_line_pixel_width > 0:
                        binary_breaked_line += b"\xff"

                    current_line_pixel_width += next_word_pixel_length + space_width
                    prev_char = 0xFF  # Space character

                binary_breaked_line += next_word

                # Update font context and prev_char after processing word
                current_font_index, prev_char = self._update_context_after_bytes(
                    next_word, current_font_index, prev_char
                )

                # Recalculate space width for new font context
                space_width = self.length_tables[current_font_index][space_char] + 1

                index = next_break_point + 1
            else:
                # No more break points, process remaining text
                remaining_word = binary_line[index:]
                if remaining_word:
                    remaining_word_pixel_length = self._measure_bytes_with_context(
                        remaining_word, current_font_index, prev_char
                    )
                    if index > 0:
                        if (
                            current_line_pixel_width + remaining_word_pixel_length
                            >= max_pixel_width
                        ):
                            binary_breaked_line += b"\x01"
                        else:
                            binary_breaked_line += b"\xff"
                    binary_breaked_line += remaining_word

                # Update font context after processing remaining word
                current_font_index, prev_char = self._update_context_after_bytes(
                    remaining_word, current_font_index, prev_char
                )
                break

        return self.table.to_text(binary_breaked_line), current_font_index

    def _measure_bytes_with_context(
        self, binary: bytes, font_index: int, prev_char: int = None
    ) -> int:
        """Measure bytes with given font context and previous character."""
        size = 0
        k = 0
        current_font_index = font_index

        while k < len(binary):
            char = binary[k]
            match char:
                case 0xFE:
                    k += 1
                    current_font_index = binary[k]
                    prev_char = None  # Reset previous char on font change
                case 0x4:
                    k += 1
                    size += 6 * 8
                    prev_char = None  # Reset previous char after special sequence
                case 0x8:
                    size = 4 * 8  # Assume 4 full chars for gils count.
                    prev_char = None
                case _:
                    # Add character width
                    char_width = self.length_tables[current_font_index][char]
                    size += char_width

                    # Add spacing (default 1 pixel, adjusted by kerning)
                    spacing = 1
                    if prev_char is not None:
                        # Check for kerning adjustment
                        kerning_pair = (prev_char, char)
                        if kerning_pair in self.kerning_tables[current_font_index]:
                            kerning_value = self.kerning_tables[current_font_index][
                                kerning_pair
                            ]
                            spacing = kerning_value + 1  # Kerning + 1 = actual spacing

                    size += spacing
                    prev_char = char

            k += 1

        return size

    def _update_context_after_bytes(
        self, binary: bytes, font_index: int, prev_char: int = None
    ) -> tuple[int, int]:
        """Update font context and prev_char after processing bytes."""
        k = 0
        current_font_index = font_index

        while k < len(binary):
            char = binary[k]
            match char:
                case 0xFE:
                    k += 1
                    current_font_index = binary[k]
                    prev_char = None
                case 0x4:
                    k += 1
                    prev_char = None
                case _:
                    prev_char = char

            k += 1

        return current_font_index, prev_char

    def measure_line_count(self, line: str, max_pixel_width: int) -> int:
        breaking_chars = b"\xff"

        binary_line = self.table.to_bytes(line)
        lines_count = 0
        current_line_pixel_width = 0
        index = 0
        current_font_index = 0  # Always start with normal font (index 0)
        space_char = 0xFF  # Space character
        space_width = self.length_tables[current_font_index][space_char] + 1

        prev_char = None

        while index < len(binary_line):
            next_break_point = binary_line.find(breaking_chars, index)

            if next_break_point != -1:
                next_word = binary_line[index:next_break_point]

                # Measure word with current font context
                next_word_pixel_length = self._measure_bytes_with_context(
                    next_word, current_font_index, prev_char
                )

                if current_line_pixel_width + next_word_pixel_length >= max_pixel_width:
                    current_line_pixel_width = next_word_pixel_length
                    lines_count += 1
                    prev_char = None  # Reset after line break
                else:
                    current_line_pixel_width += next_word_pixel_length + space_width
                    prev_char = 0xFF  # Space character

                # Update font context after processing word
                current_font_index, prev_char = self._update_context_after_bytes(
                    next_word, current_font_index, prev_char
                )

                # Recalculate space width for new font context
                space_width = self.length_tables[current_font_index][space_char] + 1

                index = next_break_point + 1
            else:
                # No more break points, process remaining text
                remaining_word = binary_line[index:]
                if remaining_word:
                    remaining_word_pixel_length = self._measure_bytes_with_context(
                        remaining_word, current_font_index, prev_char
                    )
                    if (
                        current_line_pixel_width + remaining_word_pixel_length
                        >= max_pixel_width
                    ):
                        lines_count += 1
                break

        return lines_count + 1

    def _load_interleaved_font(
        self, font_file: str, char_height: int = 16
    ) -> tuple[bytes, dict]:
        """Load font data in the new interleaved format with kerning after character data."""
        try:
            with open(font_file, "rb") as f:
                font_data = f.read()
        except FileNotFoundError:
            # Return empty tables if font file doesn't exist
            return bytes(256), {}

        # Extract character width data from interleaved format
        length_table = bytearray(256)
        bytes_per_char = char_height + 1

        for char_index in range(256):
            data_offset = char_index * bytes_per_char
            width_offset = data_offset + char_height

            if width_offset < len(font_data):
                length_table[char_index] = font_data[width_offset]
            else:
                length_table[char_index] = 8  # Default width

        kerning_table = {}
        kerning_offset = 256 * (char_height + 1)

        if len(font_data) > kerning_offset + 2:
            # Check if there's actually kerning data at this offset
            # Read potential kerning count and validate it's reasonable
            try:
                kerning_count = struct.unpack(
                    "<H", font_data[kerning_offset : kerning_offset + 2]
                )[0]
                # Sanity check: kerning count should be reasonable (< 10000)
                if 0 < kerning_count < 10000:
                    data_start = kerning_offset + 2

                    # Read kerning pairs: char1, char2, kerning_value
                    for i in range(kerning_count):
                        entry_offset = data_start + (i * 3)
                        if entry_offset + 3 <= len(font_data):
                            char1, char2, kerning_abs = struct.unpack(
                                "BBB", font_data[entry_offset : entry_offset + 3]
                            )
                            # Kerning values are stored as abs() of the actual kerning in the file
                            # Convert back to negative (kerning is always negative for tighter spacing)
                            kerning_value = -kerning_abs if kerning_abs > 0 else 0
                            kerning_table[(char1, char2)] = kerning_value
                        else:
                            break
            except (struct.error, IndexError):
                # Invalid data at 0x1000, no kerning
                pass

        return bytes(length_table), kerning_table
