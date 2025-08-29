#!/usr/bin/env python3
import logging
import os
import struct
from pathlib import Path
from typing import Callable
from xml.etree import ElementTree

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

from utils.font import convert_font_to_1bpp, convert_font_to_2bpp
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
            print(f"{hex(i)}: {text}")
            formatted_text = formatter(text) if formatter else text
            pointer.value = table.to_bytes(formatted_text) if text else b""
            max_length = max(max_length, len(pointer.value))
            if len(pointer.value) < length:
                pad_length = length - len(pointer.value)
                pointer.value += table.to_bytes(padding) * pad_length
            elif len(pointer.value) > length:
                pointer.value = pointer.value[:length]

            pointer_table.append(pointer)
            i += 1
        print(f"max {max_length}")
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
    ff4_asm = Program()
    ff4_asm.resolver.current_scope.add_symbol("LANG", lang)

    exit_code = ff4_asm.assemble_as_patch(input, output)

    if exit_code != 0:
        logger.error("Build failed.")
        return exit_code

    ff4_asm.exports_symbol_file("./build/ff4.sym")


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


def build_null_terminated(table, input_file, binary_text_file, pointers_file=None):
    pointers = read_stringarray_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)
    if pointers_file:
        write_pointers_addresses_as_binary(
            pointers, lambda v: struct.pack("<H", v), pointers_file
        )


def build_text_assets(banks):
    for bank in banks:
        build_text_asset(dialog_table, bank[0], bank[1], bank[2], bank[3])


def build_vwf_font_asset_2bpp(
    font_file, has_grid, data_file, len_table_file, char_height
):
    len_table, data = convert_font_to_2bpp(font_file, has_grid, char_height)

    # Espace
    len_table[0xFF] = 3
    # Espace fine
    len_table[0xFD] = 1
    # Espace insécable
    len_table[0xFE] = 2

    with open(data_file, "wb") as fd:
        fd.write(data)
    with open(len_table_file, "wb") as fd:
        fd.write(bytes(len_table.values()))


def build_vwf_font_asset(font_file, has_grid, data_file, len_table_file, char_height):
    len_table, data = convert_font_to_1bpp(font_file, has_grid)

    # Espace
    len_table[0xFF] = 3
    # Espace fine
    len_table[0xFD] = 1
    # Espace insécable
    len_table[0xFE] = 2
    len_table[0xA0] = len_table[0xA0] - 1

    with open(data_file, "wb") as fd:
        fd.write(data)
    with open(len_table_file, "wb") as fd:
        fd.write(bytes(len_table.values()))


assets_builder = {
    "script": build_text_asset,
    "pointed_16bits_lowrom": build_pointed_16bits_lowrom,
    "fixed": build_fixed_asset,
    "nullterminated": build_null_terminated,
    "vwf-font": build_vwf_font_asset,
    "vwf-font-2bpp": build_vwf_font_asset_2bpp,
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
        ),
        (
            "vwf-font",
            "fonts/bold_vwf.png",
            False,
            "assets/bold_font.dat",
            "assets/bold_font_length_table.dat",
            16,
        ),
        (
            "vwf-font",
            "fonts/wicked_vwf.png",
            False,
            "assets/wicked_font.dat",
            "assets/wicked_font_length_table.dat",
            16,
        ),
        (
            "vwf-font",
            "fonts/book_vwf.png",
            False,
            "assets/book_font.dat",
            "assets/book_font_length_table.dat",
            16,
        ),
        (
            "vwf-font-2bpp",
            "fonts/8x8vwf2p.png",
            True,
            "assets/menu_font.dat",
            "assets/menu_font_length_table.dat",
            8,
        ),
        ("fixed", menu_table, os.path.join(text_root, "items.xml"), "assets/items.dat"),
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
            "fixed",
            menu_table,
            os.path.join(text_root, "attack-names.xml"),
            "assets/attack-names.dat",
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
    ]

    build_assets(assets_list)

    credits_file = Path(f"./text/{lang}/credits.txt")
    menu_table.parse_table_line("0A=.")
    del menu_table.lookup[".."]
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

    small_text = ["Niveau", "Gils"]

    generate_8x8_vwf_asset(small_text, "vwf_precomp", 0x90)
    menu_vwf_table = Table("text/vwf_precomp.tbl")

    if not os.path.exists("build"):
        os.mkdir("build")

    build_patch("ff4.s", "build/ff4.ips", lang)
