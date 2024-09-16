#!/usr/bin/env python3.4
import struct

import script
from a816.cpu.cpu_65c816 import snes_to_rom
from a816.symbols import low_rom_bus
from script import Table
from script.formulas import base_relative_16bits_pointer_formula
from script.pointers import Script, write_pointers_as_xml, Pointer


def write_fixed_text_as_xml(pointers, table, length, output_file):
    sorted_pointers_by_id = sorted(pointers, key=lambda p: p.id)
    with open(output_file, 'wt', encoding='utf-8') as fd:
        fd.writelines('<?xml version="1.0" encoding="utf-8"?>\n')
        fd.write('<sn:fixedlist length="{:d}" xmlns:sn="http://snes.ninja/ScriptNS">\n'.format(length))
        for pointer in sorted_pointers_by_id:
            fd.write('<sn:fixed>')
            fd.write(table.to_text(pointer.value)) #.strip())
            fd.write('</sn:fixed>\n')
        fd.write('</sn:fixedlist>\n')

def write_nul_terminated_strings_as_xml(strings, output_file):
    with open(output_file, 'wt', encoding='utf-8') as fd:
        fd.writelines('<?xml version="1.0" encoding="utf-8"?>\n')
        fd.write('<sn:stringarray eos="0x00" xmlns:sn="http://snes.ninja/ScriptNS">\n')
        for s in strings:
            fd.write('<sn:string>')
            fd.write(s) #.strip())
            fd.write('</sn:string>\n')
        fd.write('</sn:stringarray>\n')

def dump_en():
    # jtable = Table('../text/ff4_jap.tbl')
    jtable = Table('../text/ff4_menus.tbl')
    item_description = low_rom_bus.get_address(0x2407ad)
    item_desc = []

    # with open('../ff4j.smc', 'rb') as rom:
    with open('../Final Fantasy IV (Japan) (Rev 1) [En by J2e v3.21].sfc', 'rb') as rom:
        rom.seek(item_description.physical)
        for k in range(443):
            s = bytes()
            while (char := rom.read(1)) != b'\x00':
                print(char)
                s += char
            item_desc.append(jtable.to_text(s))

    write_nul_terminated_strings_as_xml(item_desc, "../text/en/item_descriptions.xml")
    ...

def dump_jp():
    jtable = Table('../text/ff4_jap.tbl')
    #jtable = Table('.text/ff4_menus.tbl')
    item_description = low_rom_bus.get_address(0x0fae2a)
    item_desc = []

    with open('../ff4j.smc', 'rb') as rom:
    #with open('../Final Fantasy IV (Japan) (Rev 1) [En by J2e v3.21].sfc', 'rb') as rom:
        rom.seek(item_description.physical)
        for k in range(47):
            s = bytes()
            while (char := rom.read(1)) != b'\x00':
                print(char)
                s += char
            item_desc.append(jtable.to_text(s))

    write_nul_terminated_strings_as_xml(item_desc, "../text/jp/item_descriptions.xml")
    ...


def dump_handedness():
    jtable = Table('../text/ff4_jap.tbl')
    addr = low_rom_bus.get_address(0x01e2d9)
    with open('../ff4j.smc', 'rb') as rom:
        rom.seek(addr.physical)
        data = rom.read(8*4)
        text = jtable.to_text(data)
        ...

if __name__ == '__main__':
    jtable = Table('../text/ff4_jap.tbl')
#     addr = low_rom_bus.get_address(0xef200)
#     with open('../ff4j.smc', 'rb') as rom:
#         rom.seek(addr.physical)
#         i = 0
#         battle_messages_pointers = []
#         while i < 0xba:
#             data = rom.read(2)
#             pointer = struct.unpack('<H', data)
#             pos = rom.tell()
#
#             string_pointer = low_rom_bus.get_address((addr.logical_value & 0xff0000)+ pointer[0])
#             rom.seek(string_pointer.physical)
#             s = bytes()
#
#             end_of_string = False
#             while end_of_string is False:
#                 # print(char)
#                 char = rom.read(1)
#                 s += char
#
#                 if char == b'\x04':
#                     char = rom.read(1)
#                     s += char
#                     continue
#
#                 if char == b'\x00':
#                     end_of_string = True
#             ptr = Pointer(i)
#             ptr.value = s
#             battle_messages_pointers.append( ptr)
#             rom.seek(pos)
#             i+=1
#         write_pointers_as_xml(battle_messages_pointers, jtable, '../text/jp/battle_messages.xml')

    addr = low_rom_bus.get_address(0x0fb200)
    with open('../ff4j.smc', 'rb') as rom:
        rom.seek(addr.physical)
        i = 0
        battle_messages_pointers = []
        while i < 58:
            data = rom.read(2)
            pointer = struct.unpack('<H', data)
            pos = rom.tell()

            string_pointer = low_rom_bus.get_address((addr.logical_value & 0xff0000) + pointer[0])
            rom.seek(string_pointer.physical)
            s = bytes()

            end_of_string = False
            while end_of_string is False:
                # print(char)
                char = rom.read(1)
                s += char

                if char == b'\x04':
                    char = rom.read(1)
                    s += char
                    continue

                if char == b'\x00':
                    end_of_string = True
            ptr = Pointer(i)
            ptr.value = s
            battle_messages_pointers.append(ptr)
            rom.seek(pos)
            i += 1
        write_pointers_as_xml(battle_messages_pointers, jtable, '../text/jp/battle_text.xml')

    # dump_en()
    exit(0)
    table = Table('.text/ff4_menus.tbl')
    jtable = Table('text/ff4_jap.tbl')


    # with open('ff4j.smc', 'rb') as rom:
    #     script = Script(rom)
    #     pointers_1_1 = script.read_pointers(rom, 0x80200, 0x200, 2, base_relative_16bits_pointer_formula(0x80600))
    #     pointers_1_1 = script.read_pointers_content(pointers_1_1, 0x8F693)
    #     write_pointers_as_xml(pointers_1_1, jtable, 'text/jp-bank1-1.xml')
    #
    #     items = script.read_fixed_text_list(rom, snes_to_rom(0x0F88FB + 5)+0x200, 0x100, 6)
    #     write_fixed_text_as_xml(items, jtable, 8, 'jp-items.xml')


    # exit(0)

    with open('ff4J2e.smc', 'rb') as rom:
        script = Script(rom)

        # extf .\roms\FF4J2E.smc .\tables\ff4f.tbl .\txt_us\monst_mag.txt $119D80 $b8 8 $00 $00
        # extf .\roms\FF4J2E.smc .\tables\ff4f.tbl .\txt_us\magic.txt $11AFC0 $48 8 $00 $00
        # extf .\roms\FF4J2E.smc .\tables\ff4f.tbl .\txt_us\items.txt $78200 $100 9 $00 $00

        # monster_spells = script.read_fixed_text_list(rom, 0x119D80, 0xb8, 8)
        items = script.read_fixed_text_list(rom, 0x78200, 0x100, 9)
        write_fixed_text_as_xml(items, table, 8, 'text/en/en-items.xml')

        # pointers_1_1 = script.read_pointers(rom, 0x80200, 0x200, 2, base_relative_16bits_pointer_formula(0x80600))
        # pointers_1_1 = script.read_pointers_content(pointers_1_1, 0x8F693)
        # write_pointers_as_xml(pointers_1_1, table, 'text/en/en-bank1-1.xml')

        # pointers_1_2 = script.read_pointers(rom, 0x80400, 0x100, 2, base_relative_16bits_pointer_formula(0x110400))
        # pointers_1_2 = script.read_pointers_content(pointers_1_2, 0x115700)
        # write_pointers_as_xml(pointers_1_2, table, 'text/en-bank1-2.xml')

        # pointers_2 = script.read_pointers(rom, 0x100200, 0x150, 2, base_relative_16bits_pointer_formula(0x100500))
        # pointers_2 = script.read_pointers_content(pointers_2, 0x10F033)
        # write_pointers_as_xml(pointers_2, table, 'text/en/en-bank2.xml')


        # pointer_table_here = 0xA8200 + 0x200
        #
        # pointers_places_name = script.read_pointers(rom, 0xA8200 + 0x200, 0x180, 2, base_relative_16bits_pointer_formula(0x17F200))
        # pointers_places_name = script.read_pointers_content(pointers_places_name, 0x17F933)
        # jp_places = 0xA9880
        # jp_places_end = 0xA9C80
        #
        # # write_pointers_as_xml(pointers_places_name, table, 'text/en/us-places.xml')
        # write_fixed_text_as_xml(monster_spells, table, 8, 'text/en/en-monster-spells.xml')
