#!/usr/bin/env python3.4
from a816.cpu.cpu_65c816 import snes_to_rom
from script import Table
from script.formulas import long_low_rom_pointer

from script.pointers import read_pointers_from_xml, write_pointers_value_as_binary, write_pointers_addresses_as_binary

if __name__ == '__main__':
    french_table = Table('text/ff4fr.tbl')

    pointers = read_pointers_from_xml('text/fr-bank1.xml', french_table)

    write_pointers_value_as_binary(pointers, 'assets/bank1.dat')
    write_pointers_addresses_as_binary(pointers, long_low_rom_pointer(snes_to_rom(0x228000)), 'assets/bank1.ptr')
