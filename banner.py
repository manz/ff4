#!/usr/bin/env python3
"""
Banner tool to display text using FF4 fonts in the terminal.
"""

import sys
import argparse
import numpy as np
from script import Table
from metrics import TextMetrics
from utils.font_converter import FontConverter


def create_banner(
    text: str,
    font_files: list[str],
    char_height: int = None,
    enable_kerning: bool = True,
    autohint: bool = False,
    debug: bool = False,
) -> str:
    """Create a banner representation of the text using unified numpy array rendering."""
    # Auto-detect character height from the first font file if not specified
    if char_height is None:
        try:
            with open(font_files[0], "rb") as f:
                data = f.read()
                if len(data) == 0:
                    raise ValueError("Font file is empty")
                char_height = data[-1]
        except FileNotFoundError:
            raise FileNotFoundError(f"Font file not found: {font_files[0]}")
        except Exception as e:
            raise RuntimeError(f"Error reading font file: {e}")

    # Select appropriate table file based on character height
    if char_height == 16:
        table_file = "text/ff4fr.tbl"
    elif char_height == 8:
        table_file = "text/ff4_menus.tbl"
    else:
        raise ValueError(
            f"Unsupported character height: {char_height}. Expected 8 or 16."
        )

    # Initialize TextMetrics and table
    table = Table(table_file)

    # Map font files to their corresponding PNG sources
    font_png_map = {
        "assets/font.dat": "fonts/vwf.png",
        "assets/wicked_font.dat": "fonts/wicked_vwf.png",
        "assets/book_font.dat": "fonts/book_vwf.png",
        "assets/bold_font.dat": "fonts/bold_vwf.png",
        "assets/menu_font.dat": "fonts/8x8vwf.png",  # 8x8 VWF font
    }

    # Convert text to bytes
    text_bytes = table.to_bytes(text)
    if not text_bytes:
        return ""

    # Process text to handle font changes and extract sequences for each font
    sequences = []
    current_font_index = 0
    i = 0
    current_sequence = []

    while i < len(text_bytes):
        char = text_bytes[i]

        if char == 0xFE and i + 1 < len(text_bytes):
            # Font change - finish current sequence and start new one
            if current_sequence:
                sequences.append((current_font_index, current_sequence))
                current_sequence = []

            i += 1
            font_index = text_bytes[i]
            if 0 <= font_index < len(font_files):
                current_font_index = font_index
        elif char == 0x04:
            # Special sequence - skip for now
            pass
        else:
            # Regular character
            current_sequence.append(char)

        i += 1

    # Add final sequence
    if current_sequence:
        sequences.append((current_font_index, current_sequence))

    if not sequences:
        return ""

    # Render each sequence using FontConverter
    rendered_segments = []
    for font_index, sequence in sequences:
        if not sequence:
            continue

        font_file = font_files[font_index]
        if font_file not in font_png_map:
            print(
                f"Warning: Font {font_file} not supported for rendering",
                file=sys.stderr,
            )
            continue

        font_png_path = font_png_map[font_file]

        has_grid = False  # No grids in any fonts now
        converter = FontConverter(
            font_png_path,
            has_grid,
            char_width=8 if char_height == 8 else 8,
            char_height=char_height,
        )

        # Prepare kerning and width tables if not using autohint
        external_kerning_table = None
        external_width_table = None
        if not autohint:
            metrics = TextMetrics(table, [font_file], char_height)
            if enable_kerning:
                external_kerning_table = metrics.kerning_tables[0]
                if debug and external_kerning_table:
                    print(
                        f"Using file-based kerning for font {font_index}, {len(external_kerning_table)} pairs loaded",
                        file=sys.stderr,
                    )
            external_width_table = metrics.length_tables[0]
            if debug:
                print(f"Using file-based widths for font {font_index}", file=sys.stderr)

        # Render the sequence
        sequence_bytes = bytes(sequence)
        default_kerning = 1 if enable_kerning else 0

        if autohint:
            if debug:
                print(
                    f"Using autohint with FontConverter: {font_png_path}",
                    file=sys.stderr,
                )
            rendered_array = converter.render_kerned_string(
                sequence_bytes, default_kerning
            )
        else:
            rendered_array = converter.render_kerned_string(
                sequence_bytes,
                default_kerning,
                external_kerning_table,
                external_width_table,
            )

        rendered_segments.append(rendered_array)

    if not rendered_segments:
        return ""

    # Concatenate all rendered segments horizontally
    final_array = rendered_segments[0]
    for segment in rendered_segments[1:]:
        # Ensure both arrays have the same height
        max_height = max(final_array.shape[0], segment.shape[0])
        if final_array.shape[0] < max_height:
            pad_height = max_height - final_array.shape[0]
            final_array = np.pad(
                final_array, ((0, pad_height), (0, 0)), mode="constant"
            )
        if segment.shape[0] < max_height:
            pad_height = max_height - segment.shape[0]
            segment = np.pad(segment, ((0, pad_height), (0, 0)), mode="constant")

        # Concatenate horizontally
        final_array = np.concatenate([final_array, segment], axis=1)
    print(f"width: {final_array.shape[1]}")
    # Convert numpy array to terminal banner format
    result = ""
    for row in final_array:
        line = ""
        for pixel in row:
            if pixel > 0:
                line += "██"
            else:
                line += "  "
        result += line + "\n"

    return result.rstrip()


def main():
    parser = argparse.ArgumentParser(
        description="Display text as a banner using FF4 fonts"
    )
    parser.add_argument("text", help="Text to display")
    parser.add_argument(
        "--font",
        choices=["normal", "wicked", "book", "bold", "vwf8"],
        default="normal",
        help="Font to use (default: normal)",
    )
    parser.add_argument(
        "--height", type=int, help="Character height (auto-detected if not specified)"
    )
    parser.add_argument(
        "--no-kerning",
        action="store_true",
        help="Disable kerning (use default spacing)",
    )
    parser.add_argument(
        "--autohint",
        action="store_true",
        help="Use auto-generated kerning instead of file kerning",
    )
    parser.add_argument(
        "--debug", action="store_true", help="Show debug information about kerning"
    )

    args = parser.parse_args()

    # Configure font setup based on font type
    if args.font == "vwf8":
        # 8x8 VWF font setup
        font_files = ["assets/menu_font.dat"]
        char_height = args.height or 8
        text = args.text  # No font prefix needed for VWF8
    else:
        # Standard 16x16 fonts setup
        font_files = [
            "assets/font.dat",  # Index 0: normal
            "assets/wicked_font.dat",  # Index 1: wicked
            "assets/book_font.dat",  # Index 2: book
            "assets/bold_font.dat",  # Index 3: bold
        ]

        # Add font prefix to text if not normal
        if args.font == "wicked":
            text = "[wicked]" + args.text
        elif args.font == "book":
            text = "[force_book]" + args.text
        elif args.font == "bold":
            text = "[bold]" + args.text
        else:
            text = args.text

    try:
        enable_kerning = not args.no_kerning
        banner = create_banner(
            text, font_files, None, enable_kerning, args.autohint, args.debug
        )
        print(banner)
    except Exception as e:
        print(f"Error creating banner: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
