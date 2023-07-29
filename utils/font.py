import numpy as np
from PIL import Image

def get_char(image, char, has_grid, char_width, char_height):
    shape = image.shape
    width = shape[1]
    height = shape[0]

    if has_grid:
        x_char_count = (width - 1) / (char_width + 1)
        y_char_count = (height - 1) / (char_height + 1)
    else:
        x_char_count = width / char_width
        y_char_count = height / char_height

    line = int(char / x_char_count)
    column = int(char % x_char_count)

    if has_grid:
        x_offset = column * (char_width + 1) + 1
        y_offset = line * (char_height + 1) + 1
    else:
        x_offset = column * char_width
        y_offset = line * char_height

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
    image = np.array(Image.open(font_file))

    # image = ndimage.imread(font_file)

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


def remove_grid(font_file):
    image = np.array(Image.open(font_file))

    font = None
    for i in range(0, 0x10):
        line = None
        for k in range(0, 0x10):
            char = get_char(image, i * 0x10 + k, True, 8, 16)

            if line is not None:
                line = np.concatenate([line, char], 1)
            else:
                line = char
        if font is not None:
            font = np.concatenate([font, line], 0)
        else:
            font = line

    im = Image.fromarray(np.uint8(font * 255))
    # output = io.BytesIO()

    im.save('/tmp/font.png', format='PNG')


if __name__ == '__main__':
    remove_grid('/Users/emmanuel/PycharmProjects/ff4/fonts/wicked_vwf.png')