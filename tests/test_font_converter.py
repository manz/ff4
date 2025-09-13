from script import Table
from pathlib import Path
import numpy as np
import pytest
from PIL import Image
import tempfile
import os

from numpy.f2py.auxfuncs import ischaracter

from utils.font_converter import FontConverter


class TestFontConverter:

    @pytest.fixture
    def sample_font_file(self):
        data = np.zeros((32, 32), dtype=np.uint8)
        data[0:8, 0:8] = 1
        data[0:8, 9:17] = 1

        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
            Image.fromarray(data * 255).save(f.name, 'PNG')
            yield f.name
        os.unlink(f.name)



    def test_font_converter_init(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        assert converter.font_file == sample_font_file
        assert converter.image is None

    def test_load_image(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        converter._load_image()
        assert converter.image is not None
        assert isinstance(converter.image, np.ndarray)

    def test_get_char_with_grid(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        char = converter.get_char(0, True, 8, 8)
        assert char.shape == (8, 8)

    def test_get_char_without_grid(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        char = converter.get_char(0, False, 8, 8)
        assert char.shape == (8, 8)

    def test_char_as_1bbp(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        char = np.array([[1, 0, 1, 0, 1, 0, 1, 0]])
        result = converter.char_as_1bbp(char)
        assert isinstance(result, bytes)
        assert len(result) == 1
        assert result[0] == 0b10101010

    def test_get_max_width(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        char = np.array([[1, 1, 0, 0], [1, 1, 1, 0]])
        width = converter.get_max_width(char)
        assert width == 3

    def test_convert_to_1bpp(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        len_table, data = converter.convert_to_1bpp(has_grid=True, char_height=8)
        assert isinstance(len_table, dict)
        assert isinstance(data, bytes)

    def test_convert_to_2bpp(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        len_table, data = converter.convert_to_2bpp(has_grid=True, char_height=8)
        assert isinstance(len_table, dict)
        assert isinstance(data, bytes)

    def test_write_as_2bpp(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        data = np.zeros((8, 16), dtype=np.uint8)
        result = converter.write_as_2bpp(data)
        assert isinstance(result, bytearray)

    def test_remove_grid(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
            converter.remove_grid(f.name)
            assert os.path.exists(f.name)
            os.unlink(f.name)

    def test_with_vwf_font_and_tbl(self):
        from script import Table
        from pathlib import Path

        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        if not vwf_path.exists() or not tbl_path.exists():
            pytest.skip("VWF font or TBL file not found")

        # Load the table to find char index for 'T'
        table = Table(str(tbl_path))
        char_bytes = table.to_bytes("T")

        if not char_bytes:
            pytest.skip("Character 'T' not found in TBL file")

        char_index = char_bytes[0]  # Get the first byte as char index

        # Test FontConverter with actual VWF font
        converter = FontConverter(str(vwf_path))
        char_data = converter.get_char(char_index, False, 8, 16)

        assert char_data.shape == (16, 8)
        assert isinstance(char_data, np.ndarray)

        # Test that the character has some non-zero pixels (assuming 'T' has content)
        assert np.any(char_data > 0), "Character 'T' should have some visible pixels"

        # Get the width of the character and trim to that width
        char_width = converter.get_max_width(char_data)
        trimmed_char = char_data[:, :char_width]

        assert trimmed_char.shape == (16, char_width)
        assert char_width > 0, "Character 'T' should have a positive width"

        # Test with character "a"
        char_a_bytes = table.to_bytes("a")
        char_a_index = char_a_bytes[0]
        char_a_data = converter.get_char(char_a_index, False, 8, 16)

        assert char_a_data.shape == (16, 8)
        assert np.any(char_a_data > 0), "Character 'a' should have some visible pixels"

        # Get the width of character "a" and trim to that width
        char_a_width = converter.get_max_width(char_a_data)
        trimmed_char_a = char_a_data[:, :char_a_width]

        # Find where 'a' actually starts horizontally (first non-empty column)
        a_cols_with_pixels = np.any(trimmed_char_a > 0, axis=0)
        a_left_col = np.argmax(a_cols_with_pixels) if np.any(a_cols_with_pixels) else 0
        a_right_col = len(a_cols_with_pixels) - 1 - np.argmax(a_cols_with_pixels[::-1]) if np.any(
            a_cols_with_pixels) else char_a_width - 1
        a_actual_width = a_right_col - a_left_col + 1

        # Extract only the part of 'a' that has pixels
        actual_trimmed_char_a = trimmed_char_a[:, a_left_col:a_right_col + 1]

        assert trimmed_char_a.shape == (16, char_a_width)
        assert char_a_width > 0, "Character 'a' should have a positive width"

        # Find the vertical extent of 'a' - where it actually has pixels
        a_rows_with_pixels = np.any(trimmed_char_a > 0, axis=1)
        a_top_row = np.argmax(a_rows_with_pixels) if np.any(a_rows_with_pixels) else 0
        a_bottom_row = len(a_rows_with_pixels) - 1 - np.argmax(a_rows_with_pixels[::-1]) if np.any(
            a_rows_with_pixels) else 15
        a_height = a_bottom_row - a_top_row + 1

        # Find the vertical extent of 'T'
        t_rows_with_pixels = np.any(trimmed_char > 0, axis=1)
        t_top_row = np.argmax(t_rows_with_pixels) if np.any(t_rows_with_pixels) else 0
        t_bottom_row = len(t_rows_with_pixels) - 1 - np.argmax(t_rows_with_pixels[::-1]) if np.any(
            t_rows_with_pixels) else 15

        # Compute horizontal kerning (1 pixel spacing between chars)
        kerning = 1

        # Create a combined array with T + kerning + a
        combined_width = char_width + kerning + char_a_width
        combined_char = np.zeros((16, combined_width), dtype=np.uint8)

        # Place T at the beginning
        combined_char[:, :char_width] = trimmed_char

        # Place a after T with kerning
        combined_char[:, char_width + kerning:] = trimmed_char_a

        assert combined_char.shape == (16, combined_width)
        assert np.any(combined_char[:, :char_width] > 0), "T part should have visible pixels"
        assert np.any(combined_char[:, char_width + kerning:] > 0), "a part should have visible pixels"

        # Verify kerning space is empty
        if kerning > 0:
            assert not np.any(combined_char[:, char_width:char_width + kerning] > 0), "Kerning space should be empty"

        # Compute optimal kerning by finding how much closer we can bring 'a' to 'T'
        # Since T has horizontal crossbar at top and 'a' sits lower, they can overlap significantly
        max_kerning_reduction = 0

        # Check each possible kerning reduction, allowing 'a' to move under T's crossbar
        for reduction in range(1, kerning + char_width + 1):  # Can potentially overlap completely
            collision = False

            # Calculate where 'a' would start with this reduction
            a_start_pos = char_width + kerning - reduction

            # Check for pixel collision only in rows where both characters have content
            overlap_top = max(a_top_row, t_top_row)
            overlap_bottom = min(a_bottom_row, t_bottom_row)

            # Only check for collision if there's actual vertical overlap
            if overlap_top <= overlap_bottom:
                for row in range(overlap_top, overlap_bottom + 1):
                    for a_col in range(char_a_width):
                        a_pixel_pos = a_start_pos + a_col

                        # If 'a' pixel is within T's width, check for collision
                        if 0 <= a_pixel_pos < char_width:
                            t_pixel = trimmed_char[row, a_pixel_pos]
                            a_pixel = trimmed_char_a[row, a_col]

                            if t_pixel > 0 and a_pixel > 0:
                                collision = True
                                break
                    if collision:
                        break

            if not collision:
                max_kerning_reduction = reduction
            else:
                break

        optimal_kerning = kerning - max_kerning_reduction + 1

        # Debug: print the kerning values to see what's happening
        print(f"Original kerning: {kerning}")
        print(f"Max kerning reduction: {max_kerning_reduction}")
        print(f"Optimal kerning: {optimal_kerning}")
        print(f"T vertical range: {t_top_row}-{t_bottom_row}")
        print(f"a vertical range: {a_top_row}-{a_bottom_row}")

        # Create optimally kerned version using actual character dimensions
        optimal_combined_width = char_width + optimal_kerning + a_actual_width
        optimal_combined_char = np.zeros((16, optimal_combined_width), dtype=np.uint8)

        # Place T at the beginning
        optimal_combined_char[:, :char_width] = trimmed_char

        # Place a with optimal kerning at its correct vertical position
        a_start_col = char_width + optimal_kerning
        a_end_col = a_start_col + a_actual_width

        print(f"T ends at column: {char_width - 1}")
        print(f"a starts at column: {a_start_col}")
        print(f"Gap between T and a: {a_start_col - char_width} pixels")
        print(f"a_actual_width: {a_actual_width}")
        print(f"actual_trimmed_char_a shape: {actual_trimmed_char_a.shape}")
        print(f"a_end_col: {a_end_col}")
        print(f"Placing 'a' from column {a_start_col} to {a_end_col - 1}")
        print(f"a_left_col: {a_left_col}")
        print(f"a_right_col: {a_right_col}")
        print(f"First row of 'a' that has pixels: {actual_trimmed_char_a[a_top_row, :].tolist()}")

        # Only place 'a' pixels in the rows where 'a' actually has content
        optimal_combined_char[a_top_row:a_bottom_row + 1, a_start_col:a_start_col + char_a_width] = trimmed_char_a[
            a_top_row:a_bottom_row + 1, :]

        assert optimal_combined_char.shape == (16, optimal_combined_width)
        assert optimal_combined_width <= combined_width, "Optimal kerning should not increase width"

        kerning_improvement = combined_width - optimal_combined_width
        assert kerning_improvement >= 0, "Kerning should improve or stay the same"

    def test_render_string_methods(self):

        known_pairs_to_kern = []

        letters = ["T", "V", "F"]
        vowels = ["a", "e", "i", "o", "u", "é", "à", "è", "ê", "ï"]
        for letter in letters:
            for vowel in vowels:
                known_pairs_to_kern.append(letter + vowel)

        for vowel in vowels:
            known_pairs_to_kern.append(vowel + "j")

        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        # Create converter and table
        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)

        table = Table(str(tbl_path))
        pairs_to_kern_for_real = []
        # known_pairs_to_kern =  []
        # symbols = set(filter(lambda k: len(k) == 1 and k.isalpha(), table.lookup.keys()))
        #
        # symbols = symbols - {'\n'}
        # for k in symbols:
        #     for j in symbols:
        #         known_pairs_to_kern .append(k+j)
        for pair in known_pairs_to_kern:
            chars = table.to_bytes(pair)
            if len(chars) != 2:
                continue
            if converter.compute_kerning(chars[0], chars[1]) < 1:
                pairs_to_kern_for_real.append(pair)

        # test_dir = Path(__file__).parent.parent
        # vwf_path = test_dir / "fonts" / "8x8vwf2p.png"
        # tbl_path = test_dir / "text" / "ff4_menus.tbl"
        # # Create converter and table
        # converter = FontConverter(str(vwf_path), has_grid=True, char_height=8)
        #

        # Test string
        test_text = "-".join(pairs_to_kern_for_real)
        text_bytes = table.to_bytes(test_text)

        if not text_bytes:
            pytest.skip(f"Could not convert text '{test_text}' to bytes")

        # Test simple render_string method
        simple_rendered = converter.render_string(text_bytes)

        # assert simple_rendered.shape[0] == 16, "Rendered text should have correct height"
        # assert simple_rendered.shape[1] > 0, "Rendered text should have positive width"
        # assert np.any(simple_rendered > 0), "Rendered text should have visible pixels"
        #
        # Test optimized render_kerned_string method
        kerned_rendered = converter.render_kerned_string(text_bytes)

        # assert kerned_rendered.shape[0] == 16, "Kerned text should have correct height"
        # assert kerned_rendered.shape[1] > 0, "Kerned text should have positive width"
        # assert np.any(kerned_rendered > 0), "Kerned text should have visible pixels"
        #
        # Kerned version should generally be more compact (smaller width)
        # though this isn't guaranteed for all strings
        print(f"Simple rendering width: {simple_rendered.shape[1]}")
        print(f"Kerned rendering width: {kerned_rendered.shape[1]}")
        print(f"Space saved: {simple_rendered.shape[1] - kerned_rendered.shape[1]} pixels")
        kerned_rendered = kerned_rendered * 255
        simple_rendered = simple_rendered * 255
        # Both should have the same height
        assert simple_rendered.shape[0] == kerned_rendered.shape[0], "Both renderings should have same height"

    def test_kerning_pair(self) -> None:
        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        # Create converter and table
        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)

        table = Table(str(tbl_path))

        data = table.to_bytes("fo")
        advance_x = converter.compute_kerning(data[0], data[1], 0)

        kerned_rendered = converter.render_kerned_string(data) * 255

        assert advance_x != 0
