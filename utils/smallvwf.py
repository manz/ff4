from math import ceil
import binascii
import struct
from PIL import Image
from utils.font import get_char, get_max_width
import numpy as np

def text_to_char(text):
    ord('Z') - ord('A')
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


def write_as_2bpp(data):
    binary_data = bytearray()
    for y_value in range(0, len(data[0]), 8):
        char = data[0:8, y_value:y_value + 8]

        for byte in char:
            byte_value = int(''.join(byte.astype(str)).ljust(8, '0'), 2)
            binary_data.append(0xFF)
            binary_data.append(byte_value)

    return binary_data

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


def generate_8x8_vwf_asset(string_list, prefix, table_start, max_tile_length=None):
    k = 0
    current_id = table_start

    with open('assets/%s.bin' % prefix, 'wb') as output:
        with open('assets/%s.len' % prefix, 'wb') as length_table:
            with open('text/gen/%s.tbl' % prefix, 'wt', encoding='utf-8') as table:
                if max_tile_length:
                    line_length = (max_tile_length * 2 * 8)
                for string in string_list:
                    if max_tile_length:
                        output.seek(k * line_length)
                    data = build_text_image('fonts/8x8vwf.png', string.strip())
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