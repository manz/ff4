import numpy as np
from PIL import Image
from typing import Optional, Dict, Tuple, List


class FontConverter:
    def __init__(self, font_file: str, has_grid: bool = False, char_width: int = 8, char_height: int = 16) -> None:
        self.font_file = font_file
        self.has_grid = has_grid
        self.char_width = char_width
        self.char_height = char_height
        self.image: Optional[np.ndarray] = None
        
    def _load_image(self) -> None:
        if self.image is None:
            self.image = np.array(Image.open(self.font_file))
    
    def get_char(self, char: int) -> np.ndarray:
        self._load_image()
        shape = self.image.shape
        width = shape[1]
        height = shape[0]

        if self.has_grid:
            x_char_count = (width - 1) / (self.char_width + 1)
            y_char_count = (height - 1) / (self.char_height + 1)
        else:
            x_char_count = width / self.char_width
            y_char_count = height / self.char_height

        line = int(char / x_char_count)
        column = int(char % x_char_count)

        if self.has_grid:
            x_offset = column * (self.char_width + 1) + 1
            y_offset = line * (self.char_height + 1) + 1
        else:
            x_offset = column * self.char_width
            y_offset = line * self.char_height

        return self.image[y_offset : y_offset + self.char_height, x_offset : x_offset + self.char_width]

    def char_as_1bbp(self, char: np.ndarray) -> bytes:
        binary_data = []
        for byte in char:
            byte_value = int("".join(byte.astype(str)).ljust(8, "0"), 2)
            binary_data.append(byte_value)
        return bytes(binary_data)

    def get_max_width(self, char: np.ndarray) -> int:
        max_width = 0
        for byte in char:
            trimmed = np.trim_zeros(byte, "b")
            max_width = max(len(trimmed), max_width)

        return max_width

    def convert_to_1bpp(self, width_overrides: dict[int, int]) -> tuple[dict[int, int], bytes]:
        self._load_image()

        data = b""
        char_index = 0
        while char_index <= 0xff:
            char = self.get_char(char_index)

            data += self.char_as_1bbp(char)

            char_width = self.get_max_width(char)

            char_width_override = width_overrides.get(char_index, 0)

            if char_width_override < 0:
                char_width += char_width_override
            elif char_width_override > 0:
                char_width = char_width_override

            data += bytes([char_width])
            # char = self.get_char(char_index)
            char_index += 1

        len_table = {}
        for i in range(char_index - 1):
            len_table[i] = self.get_max_width(self.get_char(i))

        return len_table, data

    def convert_to_2bpp(self) -> tuple[dict[int, int], bytes]:
        self._load_image()
        char = self.get_char(0x00)

        data = b""
        char_index = 1
        while len(char) > 0:
            data += self.write_as_2bpp(char)
            char = self.get_char(char_index)
            char_index += 1

        len_table = {}
        for i in range(char_index - 1):
            len_table[i] = self.get_max_width(self.get_char(i))

        return len_table, data

    def remove_grid(self, output_path: str = "/tmp/font.png") -> None:
        self._load_image()
        font = None
        for i in range(0, 0x10):
            line = None
            for k in range(0, 0x10):
                char = self.get_char(i * 0x10 + k)

                if line is not None:
                    line = np.concatenate([line, char], 1)
                else:
                    line = char
            if font is not None:
                font = np.concatenate([font, line], 0)
            else:
                font = line

        im = Image.fromarray(np.uint8(font * 255))
        im.save(output_path, format="PNG")

    def write_as_2bpp(self, data: np.ndarray) -> bytearray:
        binary_data = bytearray()
        for y_value in range(0, len(data[0]), 8):
            char = data[0:8, y_value : y_value + 8]

            for byte in char:
                byte_value = int("".join(byte.astype(str)).ljust(8, "0"), 2)
                binary_data.append(0xFF)
                binary_data.append(byte_value)

        return binary_data

    def _get_char_bounds(self, char_data: np.ndarray) -> tuple[int, int]:
        """Get top and bottom row indices where character has pixels."""
        rows_with_pixels = np.any(char_data > 0, axis=1)
        if not np.any(rows_with_pixels):
            return 0, self.char_height - 1
        
        top_row = np.argmax(rows_with_pixels)
        bottom_row = len(rows_with_pixels) - 1 - np.argmax(rows_with_pixels[::-1])
        return top_row, bottom_row
    
    def _check_collision(self, char1_data: np.ndarray, char2_data: np.ndarray, 
                        char2_start_pos: int, overlap_top: int, overlap_bottom: int) -> bool:
        """Check if characters collide at given position."""
        char1_width = char1_data.shape[1]
        char2_width = char2_data.shape[1]
        
        for row in range(overlap_top, overlap_bottom + 1):
            for char2_col in range(char2_width):
                char2_pixel_pos = char2_start_pos + char2_col
                
                if 0 <= char2_pixel_pos < char1_width and char2_data[row, char2_col] > 0:
                    # Direct collision
                    if char1_data[row, char2_pixel_pos] > 0:
                        return True
                    
                    # Check immediate left diagonal (prevents char2 from getting too close to horizontal bars)
                    if (char2_pixel_pos > 0 and 
                        char1_data[row, char2_pixel_pos - 1] > 0):
                        return True
        return False

    def compute_kerning(self, char1_index: int, char2_index: int, default_kerning: int = 1) -> int:
        """Compute optimal kerning between two characters."""
        self._load_image()
        
        char1_data = self.get_char(char1_index)
        char2_data = self.get_char(char2_index)
        
        char1_width = self.get_max_width(char1_data)
        trimmed_char1 = char1_data[:, :char1_width]
        trimmed_char2 = char2_data[:, :self.get_max_width(char2_data)]
        
        char1_top, char1_bottom = self._get_char_bounds(trimmed_char1)
        char2_top, char2_bottom = self._get_char_bounds(trimmed_char2)
        
        overlap_top = max(char1_top, char2_top)
        overlap_bottom = min(char1_bottom, char2_bottom)
        
        max_kerning_reduction = 0
        max_reduction_limit = max(1, default_kerning) + char1_width
        
        for reduction in range(1, max_reduction_limit + 1):
            char2_start_pos = char1_width + default_kerning - reduction
            
            # Only check collision if there's vertical overlap
            if overlap_top <= overlap_bottom:
                if self._check_collision(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom):
                    break
            max_kerning_reduction = reduction
        
        # When default_kerning is 0, try negative kerning (overlapping)
        if default_kerning == 0 and max_kerning_reduction == 0:
            for overlap_pixels in range(1, char1_width):
                char2_start_pos = char1_width - overlap_pixels
                if overlap_top > overlap_bottom or not self._check_collision(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom):
                    return -overlap_pixels
        
        optimal_kerning = default_kerning - max_kerning_reduction
        
        return optimal_kerning

    def render_kerned_string(self, text_bytes: bytes, default_kerning: int = 1) -> np.ndarray:
        """
        Render a string with optimal kerning between character pairs.
        
        Args:
            text_bytes: Bytes representing character indices (from table.to_bytes())
            has_grid: Whether the font has grid lines
            char_width: Width of each character cell
            char_height: Height of each character cell
            default_kerning: Default spacing between characters
            
        Returns:
            2D numpy array containing the rendered text with optimal kerning
        """
        if len(text_bytes) == 0:
            return np.zeros((self.char_height, 0), dtype=np.uint8)
        
        self._load_image()
        
        # Get all character data and compute widths
        chars = []
        char_widths = []
        for char_index in text_bytes:
            char_data = self.get_char(char_index)
            actual_width = self.get_max_width(char_data)
            chars.append(char_data[:, :actual_width])
            char_widths.append(actual_width)
        
        if len(chars) == 1:
            # Single character, no kerning needed
            return chars[0]
        
        # Calculate optimal kerning between each pair and total width
        kerning_values = []
        total_width = char_widths[0]  # First character width
        
        for i in range(len(text_bytes) - 1):
            char1_index = text_bytes[i]
            char2_index = text_bytes[i + 1]
            kerning = self.compute_kerning(char1_index, char2_index, default_kerning) + 1
            kerning_values.append(kerning)
            total_width += kerning + char_widths[i + 1]
        
        # Create output array and place characters
        result = np.zeros((self.char_height, total_width), dtype=np.uint8)
        
        # Place first character
        current_pos = 0
        result[:, current_pos:current_pos + char_widths[0]] = chars[0]
        current_pos += char_widths[0]
        
        # Place remaining characters with optimal kerning
        for i in range(1, len(chars)):
            kerning = kerning_values[i - 1]
            current_pos += kerning
            
            # Find vertical extent of current character for proper placement
            char_rows_with_pixels = np.any(chars[i] > 0, axis=1)
            char_top_row = np.argmax(char_rows_with_pixels) if np.any(char_rows_with_pixels) else 0
            char_bottom_row = len(char_rows_with_pixels) - 1 - np.argmax(char_rows_with_pixels[::-1]) if np.any(char_rows_with_pixels) else self.char_height-1
            
            # Place character at its correct vertical position
            result[char_top_row:char_bottom_row+1, current_pos:current_pos + char_widths[i]] = chars[i][char_top_row:char_bottom_row+1, :]
            current_pos += char_widths[i]
        
        return result

    def render_string(self, text_bytes: bytes) -> np.ndarray:
        """
        Render a string with fixed 1-pixel kerning between characters.
        
        Args:
            text_bytes: Bytes representing character indices (from table.to_bytes())
            
        Returns:
            2D numpy array containing the rendered text with 1-pixel spacing
        """
        if len(text_bytes) == 0:
            return np.zeros((self.char_height, 0), dtype=np.uint8)
        
        self._load_image()
        
        # Get all character data and compute widths
        chars = []
        char_widths = []
        for char_index in text_bytes:
            char_data = self.get_char(char_index)
            actual_width = self.get_max_width(char_data)
            chars.append(char_data[:, :actual_width])
            char_widths.append(actual_width)
        
        if len(chars) == 1:
            # Single character, no kerning needed
            return chars[0]
        
        # Calculate total width with 1-pixel kerning between characters
        total_width = sum(char_widths) + (len(chars) - 1)  # chars + gaps
        
        # Create output array and place characters
        result = np.zeros((self.char_height, total_width), dtype=np.uint8)
        
        # Place characters with 1-pixel spacing
        current_pos = 0
        for i, char in enumerate(chars):
            # Find vertical extent of current character for proper placement
            char_rows_with_pixels = np.any(char > 0, axis=1)
            char_top_row = np.argmax(char_rows_with_pixels) if np.any(char_rows_with_pixels) else 0
            char_bottom_row = len(char_rows_with_pixels) - 1 - np.argmax(char_rows_with_pixels[::-1]) if np.any(char_rows_with_pixels) else self.char_height-1
            
            # Place character at its correct vertical position
            result[char_top_row:char_bottom_row+1, current_pos:current_pos + char_widths[i]] = char[char_top_row:char_bottom_row+1, :]
            current_pos += char_widths[i] + 1  # Move to next position with 1-pixel gap
        
        return result

    def find_kerning_pairs(self, table, test_pairs: List[str]) -> Dict[Tuple[int, int], int]:
        """Find character pairs that benefit from kerning."""
        kerning_pairs = {}

        print("Testing character pairs for kerning benefits...")
        for pair in test_pairs:
            chars = table.to_bytes(pair)
            if len(chars) != 2:
                continue

            try:
                optimal_kerning = self.compute_kerning(chars[0], chars[1], default_kerning=1)
                if optimal_kerning < -1:
                    optimal_kerning = 0
                # Skip useless entries:
                # - Same as default (no benefit)
                # - Invalid kerning values
                if optimal_kerning != 1 and optimal_kerning < 0:  # Different from default and valid
                    kerning_pairs[(chars[0], chars[1])] = optimal_kerning
                    char1_str = table.to_text(bytes([chars[0]]))
                    char2_str = table.to_text(bytes([chars[1]]))
                    print(f"  {pair} '{chars[0]}{chars[1]}' ({chars[0]:02x},{chars[1]:02x}): kerning = {optimal_kerning}")
            except Exception as e:
                print(f"  Warning: Failed to compute kerning for '{pair}': {e}")
                continue

        print(f"Found {len(kerning_pairs)} pairs that benefit from kerning")
        return kerning_pairs