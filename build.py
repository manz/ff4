#!/usr/bin/env python3
import io
import logging
import math
import os
import struct
import sys
from pathlib import Path
from typing import Callable
from xml.etree import ElementTree

from a816.linker import Linker
from a816.object_file import ObjectFile
from a816.program import Program
from a816.symbols import low_rom_bus
from script import Table
from script.formulas import long_low_rom_pointer
from script.pointers import (
    read_pointers_from_xml,
    write_pointers_value_as_binary,
    write_pointers_addresses_as_binary,
    Pointer,
)

from metrics import TextMetrics
from utils.dakutens import generate_dakutens
from utils.font import convert_font_to_2bpp
from utils.font_converter import FontConverter
from utils.smallvwf import generate_8x8_vwf_asset

logger = logging.getLogger(__name__)


def read_fixed_from_xml(input_file, table, formatter=None):
    pointer_table = []
    print(input_file)
    with open(input_file, encoding="utf-8") as datasource:
        tree = ElementTree.parse(datasource)
        root = tree.getroot()
        i = 0
        padding = root.get("padding")
        length = int(root.get("length"))
        max_length = 0
        for child in root:
            text = child.text
            pointer = Pointer(i)
            formatted_text = formatter(text) if formatter else text
            pointer.value = table.to_bytes(formatted_text) if text else b""
            max_length = max(max_length, len(pointer.value))
            if formatter is None:
                if len(pointer.value) < length:
                    pad_length = length - len(pointer.value)
                    pointer.value += table.to_bytes(padding) * pad_length
                elif len(pointer.value) > length:
                    pointer.value = pointer.value[:length]

            pointer_table.append(pointer)
            i += 1
    return pointer_table


def read_stringarray_from_xml(input_file, table):
    pointer_table = []
    with open(input_file, encoding="utf-8") as datasource:
        tree = ElementTree.parse(datasource)
        root = tree.getroot()
        i = 0
        eos = int(root.get("eos"), 16)
        for child in root:
            text = child.text
            pointer = Pointer(i)
            pointer.value = table.to_bytes(text) if text else b""
            pointer.value += bytearray([eos])
            pointer_table.append(pointer)
    return pointer_table


def assets_need_refresh(source, destination):
    try:
        source_stat = os.stat(source)
        destination_stat = os.stat(destination)

        return source_stat.st_mtime > destination_stat.st_mtime
    except FileNotFoundError:
        return True


def build_patch(input, output, lang):
    from a816.module_builder import build_with_imports

    obj_dir = Path("build/obj")
    if obj_dir.exists():
        for o in obj_dir.glob("*.o"):
            o.unlink()

    out_path = Path(output)
    if out_path.exists():
        out_path.unlink()

    result = build_with_imports(
        main_source=Path(input),
        output_file=Path(output),
        output_format="ips",
        module_paths=[Path("build/obj"), Path("src")],
        output_dir=Path("build/obj"),
        symbols={"LANG": lang},
        include_paths=[Path("src"), Path(".")],
        overlap_mode="warn",
    )

    if result.exit_code != 0:
        logger.error("Build failed.")
        return result.exit_code

    if not out_path.exists():
        logger.error("Build reported success but %s was not produced.", out_path)
        return 1

    if result.program is not None:
        result.program.exports_symbol_file("./build/ff4.sym")


def word_low_rom_pointer(base: int) -> Callable[[int], bytes]:
    def inner_func(pointer: int) -> bytes:
        snes_address = low_rom_bus.get_address(base) + pointer
        return struct.pack("<H", snes_address.logical_value & 0xFFFF)

    return inner_func


def build_pointed_16bits_lowrom(
    table, input_file, binary_text_file, pointers_file, address
):
    pointers = read_pointers_from_xml(input_file, table)

    write_pointers_value_as_binary(pointers, binary_text_file)

    pointer_addr = low_rom_bus.get_address(address) + (len(pointers) * 2)
    physical_addr = pointer_addr.physical

    assert physical_addr is not None, f"Physical address for {address:02x} not found."

    write_pointers_addresses_as_binary(
        pointers, word_low_rom_pointer(physical_addr), pointers_file
    )


def build_text_asset(table, input_file, binary_text_file, pointers_file, address):
    pointers = read_pointers_from_xml(input_file, table)

    write_pointers_value_as_binary(pointers, binary_text_file)

    pointer_addr = low_rom_bus.get_address(address)
    physical_addr = pointer_addr.physical

    assert physical_addr is not None, f"Physical address for {address:02x} not found."

    write_pointers_addresses_as_binary(
        pointers, long_low_rom_pointer(physical_addr), pointers_file
    )


def build_fixed_asset(table, input_file, binary_text_file):
    pointers = read_fixed_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)


def build_fixed_to_ptr_asset(
    table, input_file, binary_text_file, pointers_file, buffer_width=None
):
    pointers = read_fixed_from_xml(
        input_file, table, formatter=lambda t: t.strip() + "[end]"
    )

    metrics = TextMetrics(table, ["./assets/menu_font.dat"], char_height=8)
    max_length = 0
    max_ptr = None
    for i, pointer in enumerate(pointers):
        ptr_len = metrics.measure_bytes(pointer.value)
        if ptr_len > max_length:
            max_ptr = (i, pointer)
            max_length = ptr_len

        if buffer_width and ptr_len > buffer_width:
            text = table.to_text(pointer.value)
            print(f"{text} is too long ({ptr_len}px , {math.ceil(ptr_len / 8)} tiles)")

    text = table.to_text(max_ptr[1].value)
    print(f"{text} is the largest ({max_length}px ({math.ceil(max_length / 8)})")
    write_pointers_value_as_binary(pointers, binary_text_file)

    write_pointers_addresses_as_binary(
        pointers, lambda x: struct.pack("<H", x), pointers_file
    )


def build_null_terminated(table, input_file, binary_text_file, pointers_file=None):
    pointers = read_stringarray_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)
    if pointers_file:
        write_pointers_addresses_as_binary(
            pointers, lambda v: struct.pack("<H", v), pointers_file
        )


def build_null_terminated_with_base(
    table: Table, input_file: str, binary_file: str, base: int
) -> None:
    pointers = read_stringarray_from_xml(input_file, table)

    pointers_bytes = io.BytesIO()
    text_bytes = io.BytesIO()

    current_position = low_rom_bus.get_address(base) + 64
    for pointer in pointers:
        value = pointer.get_value()

        pointers_bytes.write(struct.pack("<H", current_position.logical_value & 0xFFFF))

        text_bytes.write(value)
        current_position += len(value)

    with open(binary_file, "wb") as fd:
        fd.write(pointers_bytes.getbuffer())
        fd.write(text_bytes.getbuffer())


def build_text_assets(banks):
    for bank in banks:
        build_text_asset(dialog_table, bank[0], bank[1], bank[2], bank[3])


def build_vwf_font_asset_2bpp(
    font_file, has_grid, data_file, len_table_file, char_height
):
    # Use the FontConverter approach but for 2bpp
    converter = FontConverter(font_file, has_grid, char_height=char_height)

    len_table, font_data = converter.convert_to_2bpp()

    # Apply width overrides
    len_table[0xFF] = 3  # Space
    len_table[0xFD] = 1  # Thin space
    len_table[0xFE] = 2  # Non-breaking space

    # Create interleaved format: char_data, char_width, char_data, char_width, ...
    output_data = bytearray()

    for char_index in range(256):
        # Add character bitmap data
        char_start = char_index * char_height * 2
        char_end = char_start + char_height * 2
        char_data = font_data[char_start:char_end]

        # Pad if necessary
        # while len(char_data) < char_height:
        #     char_data += b'\x00'

        output_data.extend(char_data)

        # Add width data
        width = len_table.get(char_index, 0)  # Default width 0
        output_data.append(width)

    with open(data_file, "wb") as fd:
        fd.write(output_data)


def build_vwf_font_asset(
    font_file, has_grid, data_file, len_table_file, char_height, table
):
    converter = FontConverter(font_file, has_grid, char_height=char_height)

    data_path = Path(data_file)

    if data_path.stem == "menu_font":
        overrides = {0xFF: 3}
    else:
        overrides = {
            0xFF: 3 if data_path.stem == "font" else 5,
            0xFD: 1,
            0xFE: 2,
            0xA0: -1,
        }

    len_table, data = converter.convert_to_1bpp(width_overrides=overrides)

    # Generate test pairs (common kerning candidates)
    known_pairs_to_kern = []

    # Uppercase + lowercase (classic kerning pairs)
    letters = ["T", "V", "F", "P", "A", "W", "Y", "L", "v", "t", "f", "r"]
    vowels = ["a", "e", "i", "o", "u", "é", "à", "â", "è", "ê", "ï", "îr"]

    if data_path.stem != "menu_font":
        for letter in letters:
            for vowel in vowels:
                known_pairs_to_kern.append(letter + vowel)

        # Lowercase + descender
        for vowel in vowels + ["n"]:
            known_pairs_to_kern.append(vowel + "j")
            known_pairs_to_kern.append(vowel + "g")
            known_pairs_to_kern.append(vowel + "y")
            known_pairs_to_kern.append(vowel + "t")
            known_pairs_to_kern.append(vowel + "f")

        # Common letter combinations that might benefit
        common_pairs = ["rn", "fi", "fl", "ff", "tt", "ll"]
        known_pairs_to_kern.extend(common_pairs)
        known_pairs_to_kern.extend(
            ["ît", "aî", "va", "ïe", "în", "bî", "îm", "Îl", "aï", "ïm"]
        )

        print(
            f"Testing {len(known_pairs_to_kern)} potential kerning pairs in {Path(font_file).stem}..."
        )
        # known_pairs_to_kern = ["Ta"]
        # Find pairs that benefit from kerning
        kerning_pairs = converter.find_kerning_pairs(table, known_pairs_to_kern)

        def add_custom_kernings(text: str, advance: int) -> None:
            chars = table.to_bytes(text)

            kerning_pairs[(chars[0], chars[1])] = advance

        add_custom_kernings("tt", 2)
    else:
        known_pairs_to_kern = [
            "Ya",
            "Pa",
            "PoFa",
            "Fe",
            "Fo",
            "Fu",
            "Ta",
            "Te",
            "To",
            "Tu",
            "Tr",
            "Ts",
            "ra",
            "re",
            "ro",
            "Aï",
            "ïe",
            "aî",
            "ît",
            "pa",
            "at",
            "ta",
            "te",
            "nt",
            "fa",
            "fe",
            "fo",
            "fu",
            "fi",
            "st",
            "va",
        ]
        kerning_pairs = converter.find_kerning_pairs(table, known_pairs_to_kern)

    with open(data_file, "wb") as fd:
        fd.write(data)

        # Write kerning data immediately after character data.
        # Entries are read on the SNES as u16 LE: key = char1 | (char2 << 8).
        # Binary search assumes ascending order on that exact value.
        sorted_pairs = sorted(
            kerning_pairs.items(),
            key=lambda pair: pair[0][0] | (pair[0][1] << 8),
        )
        count = len(sorted_pairs)
        fd.write(struct.pack("<H", count))
        for (char1, char2), advance in sorted_pairs:
            fd.write(struct.pack("BBB", char1, char2, abs(advance)))

        fd.write(struct.pack("B", char_height))


assets_builder = {
    "script": build_text_asset,
    "pointed_16bits_lowrom": build_pointed_16bits_lowrom,
    "fixed": build_fixed_asset,
    "fixed_to_ptr": build_fixed_to_ptr_asset,
    "nullterminated": build_null_terminated,
    "nullterminated_with_base": build_null_terminated_with_base,
    "vwf-font": build_vwf_font_asset,
}


def build_assets(assets):
    for asset in assets:
        print(asset)
        builder = assets_builder[asset[0]]
        builder(*asset[1:])


if __name__ == "__main__":
    dialog_table = Table("text/ff4fr.tbl")
    menu_table = Table("text/ff4_menus.tbl")
    lang = "fr"
    text_root = "text/{lang}".format(lang=lang)

    assets_list = [
        (
            "script",
            dialog_table,
            os.path.join(text_root, "bank1-1.xml"),
            "assets/bank1_1.dat",
            "assets/bank1_1.ptr",
            0x228000,
        ),
        (
            "script",
            dialog_table,
            os.path.join(text_root, "bank1-2.xml"),
            "assets/bank1_2.dat",
            "assets/bank1_2.ptr",
            0x24A000,
        ),
        (
            "script",
            dialog_table,
            os.path.join(text_root, "bank2.xml"),
            "assets/bank2.dat",
            "assets/bank2.ptr",
            0x25A000,
        ),
        (
            "pointed_16bits_lowrom",
            menu_table,
            os.path.join(text_root, "battle_messages.xml"),
            "assets/battle_messages.dat",
            "assets/battle_messages.ptr",
            0x298000,
        ),
        (
            "pointed_16bits_lowrom",
            menu_table,
            os.path.join(text_root, "battle_text.xml"),
            "assets/battle_text.dat",
            "assets/battle_text.ptr",
            0x299900,
        ),
        (
            "vwf-font",
            "fonts/vwf.png",
            False,
            "assets/font.dat",
            "assets/font_length_table.dat",
            16,
            dialog_table,
        ),
        (
            "vwf-font",
            "fonts/bold_vwf.png",
            False,
            "assets/bold_font.dat",
            "assets/bold_font_length_table.dat",
            16,
            dialog_table,
        ),
        (
            "vwf-font",
            "fonts/wicked_vwf.png",
            False,
            "assets/wicked_font.dat",
            "assets/wicked_font_length_table.dat",
            16,
            dialog_table,
        ),
        (
            "vwf-font",
            "fonts/book_vwf.png",
            False,
            "assets/book_font.dat",
            "assets/book_font_length_table.dat",
            16,
            dialog_table,
        ),
        (
            "vwf-font",
            "fonts/8x8vwf.png",
            False,
            "assets/menu_font.dat",
            "assets/menu_font_length_table.dat",
            8,
            menu_table,
        ),
        ("fixed", menu_table, os.path.join(text_root, "items.xml"), "assets/items.dat"),
        (
            "fixed",
            menu_table,
            os.path.join(text_root, "items_unleashed.xml"),
            "assets/items_unleashed.dat",
        ),
        ("fixed", menu_table, os.path.join(text_root, "magic.xml"), "assets/magic.dat"),
        (
            "fixed",
            menu_table,
            os.path.join(text_root, "monsters.xml"),
            "assets/monsters.dat",
        ),
        (
            "fixed",
            menu_table,
            os.path.join(text_root, "characters_names.xml"),
            "assets/characters_names.dat",
        ),
        (
            "fixed",
            menu_table,
            os.path.join(text_root, "battle_commands.xml"),
            "assets/battle_commands.dat",
        ),
        (
            "fixed_to_ptr",
            menu_table,
            os.path.join(text_root, "battle_commands.xml"),
            "assets/battle_commands_nul.dat",
            "assets/battle_commands_nul.ptr",
        ),
        (
            "fixed_to_ptr",
            menu_table,
            os.path.join(text_root, "attack-names.xml"),
            "assets/attack_names.dat",
            "assets/attack_names.ptr",
        ),
        (
            "fixed_to_ptr",
            menu_table,
            os.path.join(text_root, "monsters_long.xml"),
            "assets/monsters_long.dat",
            "assets/monsters_long.ptr",
            80,
        ),
        (
            "nullterminated",
            menu_table,
            os.path.join(text_root, "places-names.xml"),
            "assets/places_names.dat",
        ),
        (
            "nullterminated",
            menu_table,
            os.path.join(text_root, "item_descriptions.xml"),
            "assets/item_descriptions.dat",
        ),
        (
            "nullterminated",
            menu_table,
            os.path.join(text_root, "characters_classes.xml"),
            "assets/classes.dat",
            "assets/classes.ptr",
        ),
        (
            "nullterminated_with_base",
            menu_table,
            os.path.join(text_root, "battle_statuses.xml"),
            "assets/battle_statuses.dat",
            0x27B000,
        ),
    ]

    build_assets(assets_list)

    credits_file = Path(f"./text/{lang}/credits.txt")
    menu_table.parse_table_line("0A=.")
    # del menu_table.lookup[".."]
    credits_text = credits_file.read_text()

    credits_lines = credits_text.split("\n")
    credits_bin = Path("./assets/credits_text.bin")
    lines_bytes = []

    for line in credits_lines:
        if line:
            line_bytes = menu_table.to_bytes(line)
            line_bytes_centered = line_bytes.center(32, b"\xff")
            delta = 16 - len(line_bytes) // 2

            lines_bytes.append(b"\x02" + bytes([delta]) + line_bytes)
        else:
            lines_bytes.append(b"")

    credits_bin.write_bytes((b"\x01".join(lines_bytes)) + b"\x00")

    if lang != "en":
        the_end_gfx_path = Path(f"text") / lang / "the_end_gfx.bin"
        translated_gfx = Path("assets/the_end_gfx.bin")

        the_end_gfx = the_end_gfx_path.read_bytes()
        output_buffer = bytes()
        k = 0
        while k < len(the_end_gfx):
            output_buffer += bytes([the_end_gfx[k] | the_end_gfx[k + 1] << 4])
            k += 2
        translated_gfx.write_bytes(output_buffer)

    with open("assets/dakuten.bin", "wb") as fd:
        fd.write(generate_dakutens(menu_table))

    if not os.path.exists("build"):
        os.mkdir("build")

    exit_code = build_patch("ff4.s", "build/ff4.ips", lang)
    if exit_code:
        sys.exit(exit_code)
