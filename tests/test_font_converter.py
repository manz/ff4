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
        # 256x256 covers any 16x16 grid of 8x16 (default) or 8x8 cells
        # so tests that loop over 256 chars don't slice out of bounds.
        data = np.zeros((256, 256), dtype=np.uint8)
        data[0:8, 0:8] = 1
        data[0:8, 9:17] = 1

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            # Save as raw 0/1 (mode L) so the converter's bit-packing
            # routines see binary pixel values, not 0/255.
            Image.fromarray(data, mode="L").save(f.name, "PNG")
            yield f.name
        os.unlink(f.name)

    @pytest.fixture
    def vwf_converter_and_table(self):
        """Fixture providing FontConverter and Table for VWF font tests"""
        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        if not vwf_path.exists() or not tbl_path.exists():
            pytest.skip("VWF font or TBL file not found")

        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)
        table = Table(str(tbl_path))

        return converter, table

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
        converter = FontConverter(
            sample_font_file, has_grid=True, char_width=8, char_height=8
        )
        char = converter.get_char(0)
        assert char.shape == (8, 8)

    def test_get_char_without_grid(self, sample_font_file):
        converter = FontConverter(
            sample_font_file, has_grid=False, char_width=8, char_height=8
        )
        char = converter.get_char(0)
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
        converter = FontConverter(
            sample_font_file, has_grid=True, char_width=8, char_height=8
        )
        len_table, data = converter.convert_to_1bpp(width_overrides={})
        assert isinstance(len_table, dict)
        assert isinstance(data, bytes)

    def test_convert_to_2bpp(self, sample_font_file):
        converter = FontConverter(
            sample_font_file, has_grid=True, char_width=8, char_height=8
        )
        len_table, data = converter.convert_to_2bpp()
        assert isinstance(len_table, dict)
        assert isinstance(data, bytes)

    def test_write_as_2bpp(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        data = np.zeros((8, 16), dtype=np.uint8)
        result = converter.write_as_2bpp(data)
        assert isinstance(result, bytearray)

    def test_remove_grid(self, sample_font_file):
        converter = FontConverter(sample_font_file)
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
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
        char_data = converter.get_char(char_index)

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
        char_a_data = converter.get_char(char_a_index)

        assert char_a_data.shape == (16, 8)
        assert np.any(char_a_data > 0), "Character 'a' should have some visible pixels"

        # Get the width of character "a" and trim to that width
        char_a_width = converter.get_max_width(char_a_data)
        trimmed_char_a = char_a_data[:, :char_a_width]

        # Find where 'a' actually starts horizontally (first non-empty column)
        a_cols_with_pixels = np.any(trimmed_char_a > 0, axis=0)
        a_left_col = np.argmax(a_cols_with_pixels) if np.any(a_cols_with_pixels) else 0
        a_right_col = (
            len(a_cols_with_pixels) - 1 - np.argmax(a_cols_with_pixels[::-1])
            if np.any(a_cols_with_pixels)
            else char_a_width - 1
        )
        a_actual_width = a_right_col - a_left_col + 1

        # Extract only the part of 'a' that has pixels
        actual_trimmed_char_a = trimmed_char_a[:, a_left_col : a_right_col + 1]

        assert trimmed_char_a.shape == (16, char_a_width)
        assert char_a_width > 0, "Character 'a' should have a positive width"

        # Find the vertical extent of 'a' - where it actually has pixels
        a_rows_with_pixels = np.any(trimmed_char_a > 0, axis=1)
        a_top_row = np.argmax(a_rows_with_pixels) if np.any(a_rows_with_pixels) else 0
        a_bottom_row = (
            len(a_rows_with_pixels) - 1 - np.argmax(a_rows_with_pixels[::-1])
            if np.any(a_rows_with_pixels)
            else 15
        )
        a_height = a_bottom_row - a_top_row + 1

        # Find the vertical extent of 'T'
        t_rows_with_pixels = np.any(trimmed_char > 0, axis=1)
        t_top_row = np.argmax(t_rows_with_pixels) if np.any(t_rows_with_pixels) else 0
        t_bottom_row = (
            len(t_rows_with_pixels) - 1 - np.argmax(t_rows_with_pixels[::-1])
            if np.any(t_rows_with_pixels)
            else 15
        )

        # Compute horizontal kerning (1 pixel spacing between chars)
        kerning = 1

        # Create a combined array with T + kerning + a
        combined_width = char_width + kerning + char_a_width
        combined_char = np.zeros((16, combined_width), dtype=np.uint8)

        # Place T at the beginning
        combined_char[:, :char_width] = trimmed_char

        # Place a after T with kerning
        combined_char[:, char_width + kerning :] = trimmed_char_a

        assert combined_char.shape == (16, combined_width)
        assert np.any(combined_char[:, :char_width] > 0), (
            "T part should have visible pixels"
        )
        assert np.any(combined_char[:, char_width + kerning :] > 0), (
            "a part should have visible pixels"
        )

        # Verify kerning space is empty
        if kerning > 0:
            assert not np.any(
                combined_char[:, char_width : char_width + kerning] > 0
            ), "Kerning space should be empty"

        # Compute optimal kerning by finding how much closer we can bring 'a' to 'T'
        # Since T has horizontal crossbar at top and 'a' sits lower, they can overlap significantly
        max_kerning_reduction = 0

        # Check each possible kerning reduction, allowing 'a' to move under T's crossbar
        for reduction in range(
            1, kerning + char_width + 1
        ):  # Can potentially overlap completely
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
        print(
            f"First row of 'a' that has pixels: {actual_trimmed_char_a[a_top_row, :].tolist()}"
        )

        # Only place 'a' pixels in the rows where 'a' actually has content
        optimal_combined_char[
            a_top_row : a_bottom_row + 1, a_start_col : a_start_col + char_a_width
        ] = trimmed_char_a[a_top_row : a_bottom_row + 1, :]

        assert optimal_combined_char.shape == (16, optimal_combined_width)
        assert optimal_combined_width <= combined_width, (
            "Optimal kerning should not increase width"
        )

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
        # vwf_path = test_dir / "fonts" / "8x8vwf.png"
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
        print(
            f"Space saved: {simple_rendered.shape[1] - kerned_rendered.shape[1]} pixels"
        )
        kerned_rendered = kerned_rendered * 255
        simple_rendered = simple_rendered * 255
        # Both should have the same height
        assert simple_rendered.shape[0] == kerned_rendered.shape[0], (
            "Both renderings should have same height"
        )

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

    def test_va_kerning_pair_with_vwf_font(self) -> None:
        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        if not vwf_path.exists() or not tbl_path.exists():
            pytest.skip("VWF font or TBL file not found")

        # Create converter and table
        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)
        table = Table(str(tbl_path))

        # Test that 'va' kerning pair is detected by find_kerning_pairs
        test_pairs = ["va"]
        kerning_pairs = converter.find_kerning_pairs(table, test_pairs)

        # Convert 'va' to bytes
        va_bytes = table.to_bytes("va")
        if len(va_bytes) != 2:
            pytest.skip("Could not convert 'va' to character bytes")

        v_char, a_char = va_bytes[0], va_bytes[1]

        # Test that the kerning pair was found (should be in the result if kerning < 1)
        kerning_key = (v_char, a_char)

        # Compute optimal kerning manually
        optimal_kerning = converter.compute_kerning(v_char, a_char, default_kerning=1)

        # The pair should benefit from kerning (optimal < 1)
        assert optimal_kerning < 1, (
            f"'va' pair should benefit from kerning, got optimal_kerning={optimal_kerning}"
        )

        # According to find_kerning_pairs logic: optimal_kerning != 1 and optimal_kerning < 0
        # Only negative kerning values are included in the kerning_pairs dict
        if optimal_kerning != 1 and optimal_kerning < 0:
            assert kerning_key in kerning_pairs, (
                f"'va' pair should be in kerning_pairs dict"
            )
            assert kerning_pairs[kerning_key] == optimal_kerning, (
                f"Kerning value should match: expected {optimal_kerning}, got {kerning_pairs[kerning_key]}"
            )

        # Test rendering the 'va' pair with kerning
        va_kerned = converter.render_kerned_string(va_bytes)
        va_simple = converter.render_string(va_bytes)

        # Kerned version should be more compact than simple version
        assert va_kerned.shape[1] <= va_simple.shape[1], (
            "Kerned 'va' should be same width or more compact than simple rendering"
        )

        # Both should have the same height
        assert va_kerned.shape[0] == va_simple.shape[0] == 16, (
            "Both renderings should have height of 16"
        )

        # Both should have visible pixels
        assert np.any(va_kerned > 0), "Kerned 'va' should have visible pixels"
        assert np.any(va_simple > 0), "Simple 'va' should have visible pixels"

    def test_diagonal_collision_detection(self) -> None:
        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        if not vwf_path.exists() or not tbl_path.exists():
            pytest.skip("VWF font or TBL file not found")

        # Create converter and table
        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)
        table = Table(str(tbl_path))

        # Test a pair that should benefit from better kerning with diagonal collision allowance
        # 'Ta' is a classic kerning pair where 'a' can fit under T's horizontal bar
        ta_bytes = table.to_bytes("Ta")
        if len(ta_bytes) != 2:
            pytest.skip("Could not convert 'Ta' to character bytes")

        t_char, a_char = ta_bytes[0], ta_bytes[1]

        # Compute kerning for Ta pair
        optimal_kerning = converter.compute_kerning(t_char, a_char, default_kerning=1)

        # Ta should benefit from kerning (allowing one diagonal collision)
        assert optimal_kerning < 1, (
            f"'Ta' pair should benefit from kerning with diagonal collision allowance, got {optimal_kerning}"
        )

        # Test rendering
        ta_kerned = converter.render_kerned_string(ta_bytes)
        ta_simple = converter.render_string(ta_bytes)

        # Kerned version should be more compact
        assert ta_kerned.shape[1] <= ta_simple.shape[1], (
            "Kerned 'Ta' should be same width or more compact than simple rendering"
        )

    def test_ie_kerning_pair_with_vwf_font(self) -> None:
        test_dir = Path(__file__).parent.parent
        vwf_path = test_dir / "fonts" / "vwf.png"
        tbl_path = test_dir / "text" / "ff4fr.tbl"

        if not vwf_path.exists() or not tbl_path.exists():
            pytest.skip("VWF font or TBL file not found")

        # Create converter and table
        converter = FontConverter(str(vwf_path), has_grid=False, char_height=16)
        table = Table(str(tbl_path))

        # Test the 'ïe' kerning pair - special characters with diacritics
        ie_bytes = table.to_bytes("ïe")
        if len(ie_bytes) != 2:
            pytest.skip("Could not convert 'ïe' to character bytes")

        i_char, e_char = ie_bytes[0], ie_bytes[1]

        # Compute kerning for ïe pair
        optimal_kerning = converter.compute_kerning(i_char, e_char, default_kerning=1)

        # ïe should benefit from kerning with diagonal collision allowance
        assert optimal_kerning < 1, (
            f"'ïe' pair should benefit from kerning with diagonal collision allowance, got {optimal_kerning}"
        )

        # Test rendering
        ie_kerned = converter.render_kerned_string(ie_bytes)
        ie_simple = converter.render_string(ie_bytes)

        # Kerned version should be more compact than simple version
        assert ie_kerned.shape[1] <= ie_simple.shape[1], (
            "Kerned 'ïe' should be same width or more compact than simple rendering"
        )

        # Both should have the same height
        assert ie_kerned.shape[0] == ie_simple.shape[0] == 16, (
            "Both renderings should have height of 16"
        )

        # Both should have visible pixels
        assert np.any(ie_kerned > 0), "Kerned 'ïe' should have visible pixels"
        assert np.any(ie_simple > 0), "Simple 'ïe' should have visible pixels"

        # Test that find_kerning_pairs detects this pair
        test_pairs = ["ïe"]
        kerning_pairs = converter.find_kerning_pairs(table, test_pairs)

        kerning_key = (i_char, e_char)

        # If the kerning is negative (overlapping), it should be in the kerning_pairs dict
        if optimal_kerning != 1 and optimal_kerning < 0:
            assert kerning_key in kerning_pairs, (
                f"'ïe' pair should be in kerning_pairs dict when kerning is negative"
            )
            assert kerning_pairs[kerning_key] == optimal_kerning, (
                f"Kerning value should match: expected {optimal_kerning}, got {kerning_pairs[kerning_key]}"
            )

    def test_ie_kerning_expects_minus_1(self, vwf_converter_and_table) -> None:
        """Test that ïe has kerning -1"""
        converter, table = vwf_converter_and_table

        ie_bytes = table.to_bytes("ïe")
        if len(ie_bytes) != 2:
            pytest.skip("Could not convert 'ïe' to character bytes")

        i_char, e_char = ie_bytes[0], ie_bytes[1]
        kerning = converter.compute_kerning(i_char, e_char, default_kerning=1)

        assert kerning == -1, f"ïe should have kerning -1, got {kerning}"

    def test_re_kerning_expects_minus_1(self, vwf_converter_and_table) -> None:
        """Test that re has kerning -1"""
        converter, table = vwf_converter_and_table

        re_bytes = table.to_bytes("re")
        if len(re_bytes) != 2:
            pytest.skip("Could not convert 're' to character bytes")

        r_char, e_char = re_bytes[0], re_bytes[1]
        kerning = converter.compute_kerning(r_char, e_char, default_kerning=1)

        assert kerning == -1, f"re should have kerning -1, got {kerning}"

    def test_ce_kerning_expects_0(self, vwf_converter_and_table) -> None:
        """Test that ce has kerning 0"""
        converter, table = vwf_converter_and_table

        ce_bytes = table.to_bytes("ce")
        if len(ce_bytes) != 2:
            pytest.skip("Could not convert 'ce' to character bytes")

        c_char, e_char = ce_bytes[0], ce_bytes[1]
        kerning = converter.compute_kerning(c_char, e_char, default_kerning=1)

        assert kerning == 0, f"ce should have kerning 0, got {kerning}"
