import colorsys


def hex_to_rgb(hex_color):
    """Converts a 24-bit hex color string to an RGB tuple."""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hsl(rgb):
    """Converts an 8-bit RGB tuple to an HSL tuple."""
    r, g, b = (c / 255.0 for c in rgb)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return (h, s, l)


def hsl_to_rgb(hsl):
    """Converts an HSL tuple back to an 8-bit RGB tuple."""
    h, s, l = hsl
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (int(r * 255), int(g * 255), int(b * 255))


def rgb8_to_bgr5(rgb8):
    """Converts an 8-bit RGB tuple to a 15-bit BGR5 hex value."""
    r, g, b = rgb8

    # Quantize the 8-bit values to 5-bit
    b5 = b >> 3
    g5 = g >> 3
    r5 = r >> 3

    # Pack the 5-bit components into a 16-bit word
    # The SNES format is 0BBBBBGGGGGRRRRR
    bgr5_value = (b5 << 10) | (g5 << 5) | r5

    return bgr5_value


def main():
    # Input color as a 24-bit hex string
    hex_input = "4e5955"

    # Define the darkening factor
    darkening_factor = 0.5

    print(f"Original 24-bit RGB hex: #{hex_input}")

    # Step 1: Convert hex to 8-bit RGB
    original_rgb8 = hex_to_rgb(hex_input)
    print(f"Original 8-bit RGB: {original_rgb8}")

    # Step 2: Convert RGB to HSL
    hsl_color = rgb_to_hsl(original_rgb8)
    print(f"Original HSL: {hsl_color}")

    # Step 3: Darken the HSL color
    # Note: L is the second element in the tuple from colorsys.rgb_to_hls
    h, s, l = hsl_color
    darkened_hsl = (h, s, l * darkening_factor)
    print(f"Darkened HSL: {darkened_hsl}")

    # Step 4: Convert darkened HSL back to 8-bit RGB
    darkened_rgb8 = hsl_to_rgb(darkened_hsl)
    print(f"Darkened 8-bit RGB: {darkened_rgb8}")

    # Step 5: Convert the new RGB8 to BGR5
    # The result is a 16-bit integer, with the top bit cleared.
    darkened_bgr5_hex = rgb8_to_bgr5(darkened_rgb8)
    print(f"Darkened 15-bit BGR5 hex value: {hex(darkened_bgr5_hex)}")


if __name__ == "__main__":
    main()