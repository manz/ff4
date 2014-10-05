#!/usr/bin/env python3.4
from script import Table
from script.formulas import base_relative_16bits_pointer_formula
from script.pointers import Script, write_pointers_as_xml

if __name__ == '__main__':
    table = Table('text/ff4.tbl')

    with open('ff4J2e.smc', 'rb') as rom:
        main_script = Script(rom)
        pointers_1_1 = main_script.read_pointers(rom, 0x80200, 0x200, 2, base_relative_16bits_pointer_formula(0x80600))
        pointers_1_1 = main_script.read_pointers_content(pointers_1_1, 0x8F693)

        pointers_1_2 = main_script.read_pointers(rom, 0x80400, 0x100, 2, base_relative_16bits_pointer_formula(0x110400))
        pointers_1_2 = main_script.read_pointers_content(pointers_1_2, 0x115700)

        pointers_2 = main_script.read_pointers(rom, 0x100200, 0x150, 2, base_relative_16bits_pointer_formula(0x100500))
        pointers_2 = main_script.read_pointers_content(pointers_2, 0x10F033)

        write_pointers_as_xml(pointers_1_1, table, 'text/us-bank1-1.xml')
        write_pointers_as_xml(pointers_1_2, table, 'text/us-bank1-2.xml')
        write_pointers_as_xml(pointers_2, table, 'text/us-bank2.xml')
