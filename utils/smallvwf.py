import binascii
import struct
from math import ceil

import numpy as np
from PIL import Image
from script import Table

from utils.font import get_char, get_max_width, write_as_2bpp


def text_to_char(text):
    data = []
    for char in text:
        if 'A' <= char <= 'Z':
            data.append(ord(char) - ord('A') + 0x42)
        elif 'a' <= char <= 'z':
            data.append(ord(char) - ord('a') + 0x42 + ord('Z') - ord('A') + 1)
        elif char == ' ':
            data.append(0xFF)
    return data


def build_text_image(font_file, text_data):
    image = np.array(Image.open(font_file))

    # text = [0x6E, 0x7C, 0x89, 0x90]
    text = text_to_char(text_data)
    buffer = None
    for char in text:
        current_char = None
        current_char = get_char(image, char, True, 8, 8)
        # print(current_char)
        if char == 0xFF:
            width = 2
        else:
            width = get_max_width(current_char)
        culled_char = current_char[0:8, 0:width + 1]
        # print(culled_char)
        if buffer is not None:
            buffer = np.concatenate((buffer, culled_char), 1)
        else:
            buffer = culled_char

    tiled_length = ceil(len(buffer[0]) / 8) * 8

    return buffer


classes = [
    'Chevalier noir     ',
    'Chevalier dragon   ',
    'Invokeur        ',
    'Sage            ',
    'Menestrel       ',
    'Sorcier Blanc   ',
    'Moine            ',
    'Sorcier Noir   ',
    'Sorcier Blanc   ',
    'Paladin         ',
    'Ingenieur        ',
    'Invoker        ',
    'Ninja           ',
    'Selenite        '
]

character_name = [
    'Cecil ',
    'Cain  ',
    'Rydia ',
    'Tella ',
    'Gilbert',
    'Rosa  ',
    'Yang  ',
    'Palom ',
    'Porom ',
    'Cid   ',
    'Edge  ',
    'FuSoYa',
    'Golbez',
    'Anna  '
]

menu_items = [
    # 'Objets',
    # 'Sorts',
    # 'Equiper',
    # 'Statut',
    # 'Placer',
    # 'Changer',
    # 'Options',
    # 'Sauver',
    # 'Petit Meteore',
    'Chevalier noir',
    'Chevalier dragon',
    'Invokeur',
    'Sage',
    'Menestrel',
    'Sorcier Blanc',
    'Moine',
    'Sorcier Noir',
    'Sorcier Blanc',
    'Paladin',
    'Ingenieur',
    'Invoker',
    'Ninja',
    'Selenite'
]


# new file format:
# ptr: 2 len:1 tile_count: 1
#
# ptr: data: len
# on the programming side:
# we need to know where we can write in the vram
# vram_ptr
# need to display item n: lookup the n-th pointer and the data size,
# setup DMA transfer
# know the tile_id and tile_count ?
# ring buffer ?

class VwfAsset:
    def __init__(self, font_file: str, table: Table) -> None:
        self.font = np.array(Image.open(font_file))
        self.strings = []
        self.rendered_strings: dict[str, np.ndarray] = {}
        self.table = table

    def set_strings(self, strings: list[str]) -> None:
        self.strings = strings

    def get_char(self, char: int) -> np.ndarray:
        current_char = get_char(self.font, char, True, 8, 8)
        if char == 0xFF:
            width = 2
        else:
            width = get_max_width(current_char)

        return current_char[0:8, 0:width + 1]

    def render_string(self, string: str) -> np.ndarray | None:
        buffer: np.ndarray | None = None
        chars = self.table.to_bytes(string)
        for char in chars:
            culled_char = self.get_char(char)

            if buffer is not None:
                buffer = np.concatenate((buffer, culled_char), 1)
            else:
                buffer = culled_char

        return buffer

    def render(self) -> None:
        buffer: np.ndarray | None = None

        for string in self.strings:
            string_buffer = self.render_string(string)
            self.rendered_strings[string] = string_buffer

        return buffer

    def serialize(self) -> bytearray:
        pointers: list[tuple[int, int, int]] = []
        data = bytearray()
        data_origin = len(self.rendered_strings.keys()) * 3

        for string, rendered_string in self.rendered_strings.items():
            serialized_string = write_as_2bpp(rendered_string)
            pointers.append((len(data) + data_origin, len(serialized_string), len(serialized_string) // 16))
            data += serialized_string

        pointer_data = bytearray()

        for pointer in pointers:
            pointer_data += struct.pack(">HBB", pointer[0] & 0xffff, pointer[1], pointer[2])


        return pointer_data + data






def generate_8x8_vwf_asset(string_list, prefix, table_start, max_tile_length=None):
    k = 0
    current_id = table_start

    with open('assets/%s.bin' % prefix, 'wb') as output:
        with open('assets/%s.len' % prefix, 'wb') as length_table:
            with open('text/%s.tbl' % prefix, 'wt', encoding='utf-8') as table:
                if max_tile_length:
                    line_length = (max_tile_length * 2 * 8)
                for string in string_list:
                    if max_tile_length:
                        output.seek(k * line_length)
                    data = build_text_image('fonts/8x8vwf2.png', string.strip())
                    data_2bpp = write_as_2bpp(data)
                    output.write(data_2bpp)
                    length_table.write(struct.pack('<H', len(data_2bpp)))
                    tile_count = int(len(data_2bpp) / 2 / 8)
                    print('tile_count', tile_count)
                    table_entry_id = bytearray(range(current_id, current_id + tile_count))
                    print('kiki', binascii.hexlify(table_entry_id))
                    table.write('%s=%s\n' % (binascii.hexlify(table_entry_id).decode('ascii'), string))
                    current_id += tile_count
                    k += 1


if __name__ == '__main__':
    generate_8x8_vwf_asset(['Niveau', 'Gils'], 'niveau', 0xF0)
