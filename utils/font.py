import numpy as np
from scipy import ndimage


def get_char(image, char,  has_grid):
    shape = image.shape
    width = shape[1]
    height = shape[0]

    x_char_count = (width - 1) / (8 + 1)
    y_char_count = (height - 1) / (16 + 1)

    line = int(char / x_char_count)
    column = int(char % x_char_count)

    x_offset = column * (8 + 1) + 1
    y_offset = line * (16 + 1) + 1

    return image[y_offset:y_offset + 16, x_offset:x_offset + 8]


def char_as_1bbp(char):
    binary_data = []
    for byte in char:
        byte_value = int(''.join(byte.astype(str)), 2)
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

    char = get_char(image, 0x00, has_grid)

    data = b''
    char_index = 1
    while len(char) > 0:
        data += char_as_1bbp(char)
        char = get_char(image, char_index, has_grid)
        char_index += 1

    len_table = {}
    for i in range(char_index - 1):
        len_table[i] = get_max_width(get_char(image, i, has_grid))

    return len_table, data
    # Espace
    len_table[0xFF] = 5
    # Espace fine
    len_table[0xFD] = 1
    # Espace insécable
    len_table[0xFE] = 5

    with open('assets/font.dat', 'wb') as fd:
        fd.write(data)
    with open('assets/font_length_table.dat', 'wb') as fd:
        fd.write(bytes(len_table.values()))


# convert_font_to_1bpp('vwf.bmp')
