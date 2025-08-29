from script import Table


class TextMetrics:
    def __init__(self, table: Table, length_tables: list[bytes]):
        self.table = table
        # self.length_table = length_table
        self.length_tables = length_tables

    def measure_bytes(self, binary: bytes) -> int:
        size = 0
        k = 0
        current_font_index = 0
        while k < len(binary):
            char = binary[k]
            match char:
                case 0xfe:
                    k += 1
                    current_font_index = binary[k]
                case 0x4:
                    k += 1
                    size += 6 * 8
                case _:
                    size += self.length_tables[current_font_index][char] + 1

            k += 1

        return size

    def measure_string(self, line: str) -> int:
        binary_line = self.table.to_bytes(line)
        return self.measure_bytes(binary_line)

    def word_warp(self, line: str, max_pixel_width: int) -> str:
        breaking_chars = b"\xff"

        binary_line = self.table.to_bytes(line)
        binary_breaked_line = b""
        current_line_pixel_width = 0
        index = 0

        space_width = self.measure_string(" ") + 1
        while index < len(binary_line):
            next_break_point = binary_line.find(breaking_chars, index)

            if next_break_point != -1:
                next_word = binary_line[index:next_break_point]
                next_word_pixel_length = self.measure_bytes(next_word)
                if current_line_pixel_width + next_word_pixel_length >= max_pixel_width:
                    current_line_pixel_width = next_word_pixel_length
                    binary_breaked_line += b"\x01"

                else:
                    if current_line_pixel_width > 0:
                        binary_breaked_line += b"\xff"

                    current_line_pixel_width += next_word_pixel_length + space_width
                binary_breaked_line += next_word

                index = next_break_point + 1
            else:
                # No more break points, process remaining text
                remaining_word = binary_line[index:]
                if remaining_word:
                    remaining_word_pixel_length = self.measure_bytes(remaining_word)
                    if index > 0:
                        if (
                                current_line_pixel_width + remaining_word_pixel_length
                                >= max_pixel_width
                        ):
                            binary_breaked_line += b"\x01"
                        else:
                            binary_breaked_line += b"\xff"
                    binary_breaked_line += remaining_word

                break

        return self.table.to_text(binary_breaked_line)

    def measure_line_count(self, line: str, max_pixel_width: int) -> int:
        breaking_chars = b"\xff"

        binary_line = self.table.to_bytes(line)
        lines_count = 0
        current_line_pixel_width = 0
        index = 0
        space_width = self.measure_string(" ") + 1

        while index < len(binary_line):
            next_break_point = binary_line.find(breaking_chars, index)

            if next_break_point != -1:
                next_word = binary_line[index:next_break_point]

                next_word_pixel_length = self.measure_bytes(next_word)
                if current_line_pixel_width + next_word_pixel_length >= max_pixel_width:
                    current_line_pixel_width = next_word_pixel_length
                    lines_count += 1
                else:
                    current_line_pixel_width += next_word_pixel_length + space_width

                index = next_break_point + 1
            else:
                # No more break points, process remaining text
                remaining_word = binary_line[index:]
                if remaining_word:
                    remaining_word_pixel_length = self.measure_bytes(remaining_word)
                    if (
                            current_line_pixel_width + remaining_word_pixel_length
                            >= max_pixel_width
                    ):
                        lines_count += 1
                break

        return lines_count + 1
