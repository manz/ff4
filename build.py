# coding:utf-8
#!/usr/bin/env python3.4
import os

from a816.cpu.cpu_65c816 import snes_to_rom
from a816.program import Program
from script import Table
from script.formulas import long_low_rom_pointer
from script.pointers import read_pointers_from_xml, write_pointers_value_as_binary, write_pointers_addresses_as_binary

from utils.font import convert_font_to_1bpp
from utils.vwf_text_formater import vwf_text_format


def assets_need_refresh(source, destination):
    try:
        source_stat = os.stat(source)
        destination_stat = os.stat(destination)

        return source_stat.st_mtime > destination_stat.st_mtime
    except FileNotFoundError:
        return True


def build_patch(input, output):
    ff4_asm = Program()
    ff4_asm.assemble_as_patch(input, output)


def build_text_asset(table, input_file, binary_text_file, pointers_file, address):
    if assets_need_refresh(input_file, binary_text_file) or True:
        pointers = read_pointers_from_xml(input_file, table, vwf_text_format)
        write_pointers_value_as_binary(pointers, binary_text_file)
        write_pointers_addresses_as_binary(pointers, long_low_rom_pointer(snes_to_rom(address)), pointers_file)


def build_text_assets(banks):
    for bank in banks:
        build_text_asset(dialog_table, bank[0], bank[1], bank[2], bank[3])


def build_vwf_font_asset(font_file, data_file, len_table_file):
    if assets_need_refresh(font_file, data_file):
        len_table, data = convert_font_to_1bpp(font_file)

        # Espace
        len_table[0xFF] = 5
        # Espace fine
        len_table[0xFD] = 1
        # Espace insécable
        len_table[0xFE] = 5

        with open(data_file, 'wb') as fd:
            fd.write(data)
        with open(len_table_file, 'wb') as fd:
            fd.write(bytes(len_table.values()))


assets_builder = {
    'script': build_text_asset,
    'vwf-font': build_vwf_font_asset
}


def build_assets(assets):
    for asset in assets:
        builder = assets_builder[asset[0]]
        builder(*asset[1:])


if __name__ == '__main__':
    dialog_table = Table('text/ff4fr.tbl')

    assets_list = [
        # ('script', dialog_table, 'text/us-bank1-1.xml', 'assets/bank1_1.dat', 'assets/bank1_1.ptr', 0x228000),
        ('script', dialog_table, 'text/us-bank1-1.xml', 'assets/bank1_1.dat', 'assets/bank1_1.ptr', 0x228000),

        ('script', dialog_table, 'text/us-bank1-2.xml', 'assets/bank1_2.dat', 'assets/bank1_2.ptr', 0x24A000),
        ('script', dialog_table, 'text/us-bank2.xml', 'assets/bank2.dat', 'assets/bank2.ptr', 0x25A000),
        ('vwf-font', 'vwf.bmp', 'assets/font.dat', 'assets/font_length_table.dat')
    ]

    build_assets(assets_list)
    build_patch('ff4.s', 'build/ff4.ips')


