#!/usr/bin/env python3.4
# coding:utf-8
import os
from xml.etree import ElementTree

from a816.cpu.cpu_65c816 import snes_to_rom
from a816.program import Program
from script import Table
from script.formulas import long_low_rom_pointer
from script.pointers import read_pointers_from_xml, write_pointers_value_as_binary, write_pointers_addresses_as_binary, \
    Pointer
import struct
from utils.font import convert_font_to_1bpp
from utils.smallvwf import generate_8x8_vwf_asset


def read_fixed_from_xml(input_file, table, formatter=None):
    pointer_table = []
    with open(input_file, encoding='utf-8') as datasource:
        tree = ElementTree.parse(datasource)
        root = tree.getroot()
        i = 0
        padding = root.get('padding')
        length = int(root.get('length'))
        for child in root:
            text = child.text
            pointer = Pointer(i)
            pointer.value = table.to_bytes(formatter(text) if formatter else text) if text else b''

            if len(pointer.value) < length:
                pad_length = length - len(pointer.value)
                pointer.value += table.to_bytes(padding) * pad_length
            elif len(pointer.value) > length:
                pointer.value = pointer.value[:length]

            pointer_table.append(pointer)
    return pointer_table


def read_stringarray_from_xml(input_file, table):
    pointer_table = []
    with open(input_file, encoding='utf-8') as datasource:
        tree = ElementTree.parse(datasource)
        root = tree.getroot()
        i = 0
        eos = int(root.get('eos'), 16)
        for child in root:
            text = child.text
            pointer = Pointer(i)
            pointer.value = table.to_bytes(text) if text else b''
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


def build_patch(input, output):
    ff4_asm = Program()
    ff4_asm.assemble_as_patch(input, output)
    ff4_asm.resolver.dump_symbol_map()


def build_text_asset(table, input_file, binary_text_file, pointers_file, address):
    pointers = read_pointers_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)
    write_pointers_addresses_as_binary(pointers, long_low_rom_pointer(snes_to_rom(address)), pointers_file)


def build_fixed_asset(table, input_file, binary_text_file):
    pointers = read_fixed_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)


def build_null_terminated(table, input_file, binary_text_file, pointers_file=None):
    pointers = read_stringarray_from_xml(input_file, table)
    write_pointers_value_as_binary(pointers, binary_text_file)
    if pointers_file:
        write_pointers_addresses_as_binary(pointers, lambda v: struct.pack('<H', v), pointers_file)


def build_text_assets(banks):
    for bank in banks:
        build_text_asset(dialog_table, bank[0], bank[1], bank[2], bank[3])


def build_vwf_font_asset(font_file, has_grid, data_file, len_table_file):
    len_table, data = convert_font_to_1bpp(font_file, has_grid)

    # Espace
    len_table[0xFF] = 3
    # Espace fine
    len_table[0xFD] = 1
    # Espace insécable
    len_table[0xFE] = 2

    with open(data_file, 'wb') as fd:
        fd.write(data)
    with open(len_table_file, 'wb') as fd:
        fd.write(bytes(len_table.values()))


assets_builder = {
    'script': build_text_asset,
    'fixed': build_fixed_asset,
    'nullterminated': build_null_terminated,
    'vwf-font': build_vwf_font_asset
}


def build_assets(assets):
    for asset in assets:
        builder = assets_builder[asset[0]]
        builder(*asset[1:])


if __name__ == '__main__':
    dialog_table = Table('text/ff4fr.tbl')
    menu_table = Table('text/ff4_menus.tbl')

    lang = 'fr'
    text_root = 'text/{lang}'.format(lang=lang)

    assets_list = [
        ('script', dialog_table, os.path.join(text_root, '{lang}-bank1-1.xml'.format(lang=lang)), 'assets/bank1_1.dat',
         'assets/bank1_1.ptr', 0x228000),
        ('script', dialog_table, os.path.join(text_root, '{lang}-bank1-2.xml'.format(lang=lang)), 'assets/bank1_2.dat',
         'assets/bank1_2.ptr', 0x24A000),
        ('script', dialog_table, os.path.join(text_root, '{lang}-bank2.xml'.format(lang=lang)), 'assets/bank2.dat',
         'assets/bank2.ptr', 0x25A000),
        ('vwf-font', 'fonts/vwf.png', False, 'assets/font.dat', 'assets/font_length_table.dat'),
        ('vwf-font', 'fonts/bold_vwf.png', False, 'assets/bold_font.dat', 'assets/bold_font_length_table.dat'),
        ('vwf-font', 'fonts/wicked_vwf.png', False, 'assets/wicked_font.dat', 'assets/wicked_font_length_table.dat'),
        ('vwf-font', 'fonts/book_vwf.png', False, 'assets/book_font.dat', 'assets/book_font_length_table.dat'),
        ('fixed', menu_table, os.path.join(text_root, '{lang}-items.xml'.format(lang=lang)), 'assets/items.dat'),
        ('fixed', menu_table, os.path.join(text_root, '{lang}-magic.xml'.format(lang=lang)), 'assets/magic.dat'),
        ('fixed', menu_table, os.path.join(text_root, '{lang}-characters_names.xml'.format(lang=lang)),
         'assets/characters_names.dat'),
        ('fixed', menu_table, os.path.join(text_root, '{lang}-characters_names.xml'.format(lang=lang)),
         'assets/characters_names.dat'),
        ('fixed', menu_table, os.path.join(text_root, '{lang}-battle_commands.xml'.format(lang=lang)),
         'assets/battle_commands.dat'),
        ('nullterminated', menu_table, os.path.join(text_root, '{lang}-places-names.xml'.format(lang=lang)),
         'assets/places_names.dat'),
        ('nullterminated', menu_table, os.path.join(text_root, '{lang}-characters_classes.xml'.format(lang=lang)),
         'assets/classes.dat', 'assets/classes.ptr')
    ]

    build_assets(assets_list)
    generate_8x8_vwf_asset(['Niveau', 'Gils', 'Passer', 'Garde'], 'vwf_precomp', 0x90)

    if not os.path.exists('build'):
        os.mkdir('build')

    build_patch('ff4.s', 'build/ff4.ips')


