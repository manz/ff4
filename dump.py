#!/usr/bin/env python3.4
from a816.cpu.cpu_65c816 import snes_to_rom
from script import Table
from script.formulas import base_relative_16bits_pointer_formula, long_low_rom_pointer
from script.pointers import Script, recode_pointer_values, write_pointers_value_as_binary, \
    write_pointers_addresses_as_binary, write_pointers_as_xml

if __name__ == '__main__':
    table = Table('text/ff4fr.tbl')
    with open('ff4J2e.smc', 'rb') as rom:
        main_script = Script(rom)
        # pointer_table = PointerTable(fd, 0x080200, 0x200, 2, base_relative_16bits_pointer_formula(bank1))
        # pointer_table.dump(table, 0x8F693)
        # pointer_table.write_as_script('/tmp/test.txt')

        pointers_1 = main_script.read_pointers(rom, 0x80200, 0x200, 2, base_relative_16bits_pointer_formula(0x80600))
        pointers_1 = main_script.read_pointers_content(pointers_1, 0x8F693)

        # pointers_2 = main_script.read_pointers(rom, 0x110200, 0x100, 2, base_relative_16bits_pointer_formula(0x110400))
        # pointers_2 = main_script.read_pointers_content(pointers_2, 0x115700)
        #
        # fused_pointers = main_script.append_pointers(pointers_1, pointers_2)

        write_pointers_as_xml(pointers_1, table, 'text/us-bank1.xml')

        recode_pointer_values(pointers_1, table, Table('text/ff4fr.tbl'))
        write_pointers_value_as_binary(pointers_1, 'assets/bank1.dat')
        write_pointers_addresses_as_binary(pointers_1, long_low_rom_pointer(snes_to_rom(0x228000)), 'assets/bank1.ptr')
