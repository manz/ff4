from math import ceil
import binascii
import numpy as np
from scipy import ndimage
import struct


def get_char(image, char, has_grid, char_width, char_height):
    shape = image.shape
    width = shape[1]
    height = shape[0]

    x_char_count = (width - 1) / (char_width + 1)
    y_char_count = (height - 1) / (char_height + 1)

    line = int(char / x_char_count)
    column = int(char % x_char_count)

    x_offset = column * (char_width + 1) + 1
    y_offset = line * (char_height + 1) + 1

    return image[y_offset:y_offset + char_height, x_offset:x_offset + char_width]



def char_as_1bbp(char):
    binary_data = []
    for byte in char:
        byte_value = int(''.join(byte.astype(str)).ljust(8, '0'), 2)
        binary_data.append(byte_value)
    return bytes(binary_data)


def get_max_width(char):
    max_width = 0
    for byte in char:
        trimmed = np.trim_zeros(byte, 'b')
        max_width = max(len(trimmed), max_width)

    return max_width


def convert_font_to_1bpp(font_file, has_grid=True):
    image = ndimage.imread(font_file)

    char = get_char(image, 0x00, has_grid, 8, 16)

    data = b''
    char_index = 1
    while len(char) > 0:
        data += char_as_1bbp(char)
        char = get_char(image, char_index, has_grid, 8, 16)
        char_index += 1

    len_table = {}
    for i in range(char_index - 1):
        len_table[i] = get_max_width(get_char(image, i, has_grid, 8, 16))

    return len_table, data
