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

from katsuji import build as katsuji_build
from katsuji import config as katsuji_config
from metrics import TextMetrics
from utils.dakutens import generate_dakutens

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
        overlap_mode="error",
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

    metrics = TextMetrics(table, ["assets/menu_font.dat"])
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


assets_builder = {
    "script": build_text_asset,
    "pointed_16bits_lowrom": build_pointed_16bits_lowrom,
    "fixed": build_fixed_asset,
    "fixed_to_ptr": build_fixed_to_ptr_asset,
    "nullterminated": build_null_terminated,
    "nullterminated_with_base": build_null_terminated_with_base,
}


def build_assets(assets):
    for asset in assets:
        print(asset)
        builder = assets_builder[asset[0]]
        builder(*asset[1:])


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s - %(message)s")
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
            0x29A000,
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

    # Fonts first: the fixed-width string checks measure with menu_font.dat.
    katsuji_build.build(katsuji_config.load(Path("katsuji.toml")))
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
