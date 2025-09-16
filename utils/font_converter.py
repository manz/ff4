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
    
    def _count_touches(self, char1_data: np.ndarray, char2_data: np.ndarray, 
                       char2_start_pos: int, overlap_top: int, overlap_bottom: int) -> tuple[int, int]:
        """Count diagonal and orthogonal touches between two characters separately."""
        char1_width = char1_data.shape[1]
        char2_width = char2_data.shape[1]
        char1_height = char1_data.shape[0]
        
        # Calculate total width for the combined render
        total_width = max(char1_width, char2_start_pos + char2_width)
        
        # Create a combined render and track ownership
        combined = np.zeros((char1_height, total_width), dtype=np.uint8)
        ownership = np.zeros((char1_height, total_width), dtype=np.uint8)  # 1=char1, 2=char2
        
        # Place char1 first
        for row in range(char1_data.shape[0]):
            for col in range(char1_data.shape[1]):
                if char1_data[row, col] > 0:
                    combined[row, col] = char1_data[row, col]
                    ownership[row, col] = 1
        
        # Place char2, only overwriting with non-zero pixels
        for row in range(char2_data.shape[0]):
            for col in range(char2_data.shape[1]):
                if char2_data[row, col] > 0:  # Only place non-zero pixels
                    result_col = char2_start_pos + col
                    if result_col < total_width:
                        combined[row, result_col] = char2_data[row, col]
                        ownership[row, result_col] = 2
        
        # Count diagonal and orthogonal touches separately
        diagonal_pairs = set()
        orthogonal_pairs = set()
        
        for row in range(char1_height):
            for col in range(total_width):
                if combined[row, col] == 1:
                    pixel_owner = ownership[row, col]
                    
                    # Check diagonal directions
                    for dr, dc in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
                        new_row, new_col = row + dr, col + dc
                        if (0 <= new_row < char1_height and 0 <= new_col < total_width and
                            combined[new_row, new_col] == 1):
                            
                            neighbor_owner = ownership[new_row, new_col]
                            
                            # Only count touches between different characters
                            if pixel_owner != neighbor_owner and pixel_owner > 0 and neighbor_owner > 0:
                                # Create a unique key for this touch pair to avoid double counting
                                touch_key = tuple(sorted([(row, col), (new_row, new_col)]))
                                diagonal_pairs.add(touch_key)
                    
                    # Check orthogonal directions
                    for dr, dc in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
                        new_row, new_col = row + dr, col + dc
                        if (0 <= new_row < char1_height and 0 <= new_col < total_width and
                            combined[new_row, new_col] == 1):
                            
                            neighbor_owner = ownership[new_row, new_col]
                            
                            # Only count touches between different characters
                            if pixel_owner != neighbor_owner and pixel_owner > 0 and neighbor_owner > 0:
                                # Create a unique key for this touch pair to avoid double counting
                                touch_key = tuple(sorted([(row, col), (new_row, new_col)]))
                                orthogonal_pairs.add(touch_key)
        
        return len(diagonal_pairs), len(orthogonal_pairs)

    def _check_collision(self, char1_data: np.ndarray, char2_data: np.ndarray, 
                        char2_start_pos: int, overlap_top: int, overlap_bottom: int) -> bool:
        """Check for direct collisions (overlapping pixels)."""
        char1_width = char1_data.shape[1]
        char2_width = char2_data.shape[1]
        char1_height = char1_data.shape[0]
        
        # Check for direct pixel overlap
        for row in range(char1_height):
            for char2_col in range(char2_width):
                char2_pixel_pos = char2_start_pos + char2_col
                
                if (0 <= char2_pixel_pos < char1_width and
                    char1_data[row, char2_pixel_pos] == 1 and
                    char2_data[row, char2_col] == 1):
                    return True
        
        return False

    def compute_kerning(self, char1_index: int, char2_index: int, default_kerning: int = 1) -> int:
        """Compute optimal kerning between two characters, targeting exactly 1 touch."""
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
        
        # Try kerning values from most aggressive to most conservative
        best_kerning = default_kerning
        max_reduction_limit = max(1, default_kerning) + char1_width
        
        for reduction in range(1, max_reduction_limit + 1):
            # Calculate the actual position used in rendering (kerning + 1)
            kerning = default_kerning - reduction
            actual_spacing = kerning + 1
            char2_start_pos = char1_width + actual_spacing
            
            # Check for direct collisions (forbidden)
            if overlap_top <= overlap_bottom:
                if self._check_collision(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom):
                    break
            
            # Count diagonal and orthogonal touches separately
            diagonal_touches, orthogonal_touches = self._count_touches(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom)
            
            # Reject if any orthogonal touches (horizontal/vertical adjacency not allowed)
            if orthogonal_touches > 0:
                continue
            
            # Target exactly 1 diagonal touch as optimal
            if diagonal_touches == 1:
                return kerning
            elif diagonal_touches == 0:
                # 0 diagonal touches is also acceptable, save as fallback
                best_kerning = kerning
            # If diagonal_touches > 1, this kerning is too aggressive, continue to less aggressive values
        
        # When default_kerning is 0, try negative kerning (overlapping)
        if default_kerning == 0 and best_kerning == default_kerning:
            for overlap_pixels in range(1, char1_width):
                # Calculate the actual position used in rendering (kerning + 1)
                kerning = -overlap_pixels
                actual_spacing = kerning + 1
                char2_start_pos = char1_width + actual_spacing
                
                if overlap_top <= overlap_bottom:
                    if self._check_collision(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom):
                        continue
                
                diagonal_touches, orthogonal_touches = self._count_touches(trimmed_char1, trimmed_char2, char2_start_pos, overlap_top, overlap_bottom)
                
                # Reject if any orthogonal touches
                if orthogonal_touches > 0:
                    continue
                
                if diagonal_touches == 1:
                    return kerning
                elif diagonal_touches == 0:
                    best_kerning = kerning
        
        return best_kerning

    def render_kerned_string(self, text_bytes: bytes, default_kerning: int = 1, external_kerning_table: dict = None, external_width_table: bytes = None) -> np.ndarray:
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
        
        # Get all character data and determine widths
        chars = []
        char_widths = []
        for char_index in text_bytes:
            char_data = self.get_char(char_index)
            
            if external_width_table is not None:
                # Use width from external table (file-based)
                actual_width = external_width_table[char_index]
            else:
                # Compute width from PNG (autohint)
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
            
            if external_kerning_table and (char1_index, char2_index) in external_kerning_table:
                # Use external kerning table value (already includes the +1)
                kerning = external_kerning_table[(char1_index, char2_index)] + 1
            elif external_kerning_table is not None:
                # External kerning table provided but no entry for this pair - use default spacing
                kerning = default_kerning
            else:
                # No external kerning table - use auto-generated kerning
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
            
            # Place character, only overwriting with non-zero pixels
            char_data = chars[i]
            for row in range(char_data.shape[0]):
                for col in range(char_data.shape[1]):
                    if char_data[row, col] > 0:  # Only place non-zero pixels
                        result_col = current_pos + col
                        if result_col < result.shape[1]:
                            result[row, result_col] = char_data[row, col]
            
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

    def debug_kerned_string(self, text: str, table) -> None:
        """Debug tool to display and analyze a kerned string with detailed information."""
        print(f"=== KERNING DEBUG: '{text}' ===")
        
        # Convert to bytes
        text_bytes = table.to_bytes(text)
        if not text_bytes:
            print(f"Could not convert '{text}' to bytes")
            return
        
        print(f"Text bytes: {[hex(b) for b in text_bytes]}")
        print()
        
        # Analyze each character pair
        pairs_info = []
        for i in range(len(text_bytes) - 1):
            char1_index = text_bytes[i]
            char2_index = text_bytes[i + 1]
            char1_str = table.to_text(bytes([char1_index]))
            char2_str = table.to_text(bytes([char2_index]))
            
            # Get character data
            char1_data = self.get_char(char1_index)
            char2_data = self.get_char(char2_index)
            char1_width = self.get_max_width(char1_data)
            char2_width = self.get_max_width(char2_data)
            
            # Compute kerning
            kerning = self.compute_kerning(char1_index, char2_index, default_kerning=1)
            actual_spacing = kerning + 1
            char2_start_pos = char1_width + actual_spacing
            
            # Count diagonal and orthogonal touches separately
            diagonal_touches, orthogonal_touches = self._count_touches(
                char1_data[:, :char1_width], 
                char2_data[:, :char2_width],
                char2_start_pos, 0, 15
            )
            
            # Check for direct collisions
            has_collision = self._check_collision(
                char1_data[:, :char1_width], 
                char2_data[:, :char2_width],
                char2_start_pos, 0, 15
            )
            
            pairs_info.append({
                'pair': f"{char1_str}{char2_str}",
                'chars': (char1_index, char2_index),
                'widths': (char1_width, char2_width),
                'kerning': kerning,
                'actual_spacing': actual_spacing,
                'char2_start_pos': char2_start_pos,
                'diagonal_touches': diagonal_touches,
                'orthogonal_touches': orthogonal_touches,
                'has_collision': has_collision
            })
            
            print(f"Pair {i+1}: '{char1_str}'{char2_str}' ({char1_index:02x},{char2_index:02x})")
            print(f"  Widths: char1={char1_width}, char2={char2_width}")
            print(f"  Kerning: {kerning} (actual spacing: {actual_spacing})")
            print(f"  Char2 starts at position: {char2_start_pos}")
            print(f"  Diagonal touches: {diagonal_touches}")
            print(f"  Orthogonal touches: {orthogonal_touches}")
            print(f"  Direct collision: {has_collision}")
            print()
        
        # Render the string
        kerned_render = self.render_kerned_string(text_bytes)
        simple_render = self.render_string(text_bytes)
        
        print("KERNED RENDER:")
        self._display_render_with_boundaries(kerned_render, pairs_info)
        
        print("\nSIMPLE RENDER (1px spacing):")
        for i, row in enumerate(simple_render):
            row_str = ''.join('█' if pixel == 1 else ' ' for pixel in row)
            print(f'{i:2d}: {row_str}')
        
        print(f"\nWidth comparison: Kerned={kerned_render.shape[1]}, Simple={simple_render.shape[1]}")
        print(f"Space saved: {simple_render.shape[1] - kerned_render.shape[1]} pixels")
    
    def _display_render_with_boundaries(self, render, pairs_info):
        """Display render with character boundaries marked."""
        # Calculate character boundaries
        boundaries = []
        current_pos = 0
        
        # First character
        if pairs_info:
            char1_width = pairs_info[0]['widths'][0]
            boundaries.append(current_pos + char1_width - 1)  # End of char1
            current_pos += char1_width
            
            # Remaining characters
            for info in pairs_info:
                current_pos += info['actual_spacing']
                char2_width = info['widths'][1]
                boundaries.append(current_pos + char2_width - 1)  # End of char2
                current_pos += char2_width
        
        # Create column numbers header
        col_nums = ''.join(str(i % 10) for i in range(render.shape[1]))
        print(f"   {col_nums}")
        
        # Display each row with boundary markers
        for i, row in enumerate(render):
            row_str = ''.join('█' if pixel == 1 else ' ' for pixel in row)
            
            # Add boundary markers
            marked_row = list(row_str)
            for boundary in boundaries:
                if boundary < len(marked_row):
                    if marked_row[boundary] == '█':
                        marked_row[boundary] = '╬'  # Character pixel at boundary
                    else:
                        marked_row[boundary] = '|'  # Empty space at boundary
            
            print(f'{i:2d}: {"".join(marked_row)}')

    def debug_diagonal_touches(self, pair: str, table, test_kerning: int) -> None:
        """Debug tool to visualize diagonal touches for a character pair at a specific kerning."""
        print(f"=== DIAGONAL TOUCHES DEBUG: '{pair}' at kerning {test_kerning} ===")
        
        # Convert to bytes
        chars = table.to_bytes(pair)
        if len(chars) != 2:
            print(f"Could not convert '{pair}' to character pair")
            return
        
        char1_data = self.get_char(chars[0])
        char2_data = self.get_char(chars[1])
        char1_width = self.get_max_width(char1_data)
        char2_width = self.get_max_width(char2_data)
        
        # Calculate positioning
        actual_spacing = test_kerning + 1
        char2_start_pos = char1_width + actual_spacing
        
        print(f"char1_width={char1_width}, char2_width={char2_width}")
        print(f"actual_spacing={actual_spacing}, char2_start_pos={char2_start_pos}")
        print()
        
        # Create combined render and track ownership
        total_width = max(char1_width, char2_start_pos + char2_width)
        combined = np.zeros((16, total_width), dtype=np.uint8)
        ownership = np.zeros((16, total_width), dtype=np.uint8)  # 1=char1, 2=char2
        
        # Place char1 first
        for row in range(char1_data.shape[0]):
            for col in range(char1_width):
                if char1_data[row, col] > 0:
                    combined[row, col] = char1_data[row, col]
                    ownership[row, col] = 1
        
        # Place char2, only non-zero pixels
        for row in range(char2_data.shape[0]):
            for col in range(char2_width):
                if char2_data[row, col] > 0:
                    result_col = char2_start_pos + col
                    if 0 <= result_col < total_width:
                        combined[row, result_col] = char2_data[row, col]
                        ownership[row, result_col] = 2
        
        # Find diagonal touches and mark them
        touch_pairs = set()
        touch_pixels = set()  # All pixels involved in touches
        
        for row in range(16):
            for col in range(total_width):
                if combined[row, col] == 1:
                    pixel_owner = ownership[row, col]
                    
                    # Check all 4 diagonal directions
                    for dr, dc in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
                        new_row, new_col = row + dr, col + dc
                        if (0 <= new_row < 16 and 0 <= new_col < total_width and
                            combined[new_row, new_col] == 1):
                            
                            neighbor_owner = ownership[new_row, new_col]
                            
                            # Only count touches between different characters
                            if pixel_owner != neighbor_owner and pixel_owner > 0 and neighbor_owner > 0:
                                # Create a unique key for this touch pair
                                touch_key = tuple(sorted([(row, col), (new_row, new_col)]))
                                if touch_key not in touch_pairs:
                                    touch_pairs.add(touch_key)
                                    touch_pixels.add((row, col))
                                    touch_pixels.add((new_row, new_col))
                                    direction_name = {
                                        (1, 1): '↘', (1, -1): '↙', 
                                        (-1, 1): '↗', (-1, -1): '↖'
                                    }[dr, dc]
                                    char_type1 = 'char1' if pixel_owner == 1 else 'char2'
                                    char_type2 = 'char2' if neighbor_owner == 2 else 'char1'
                                    print(f"Touch: {char_type1}({row},{col}) {direction_name} {char_type2}({new_row},{new_col})")
        
        print(f"\\nTotal diagonal touches found: {len(touch_pairs)}")
        print()
        
        # Create visualization
        print("Visualization (* = touch pixel, █ = regular pixel, · = empty):")
        col_nums = ''.join(str(i % 10) for i in range(total_width))
        print(f"   {col_nums}")
        
        for row in range(16):
            row_str = ""
            for col in range(total_width):
                if (row, col) in touch_pixels:
                    row_str += '*'
                elif combined[row, col] == 1:
                    row_str += '█'
                else:
                    row_str += '·'
            print(f"{row:2d}: {row_str}")
        
        print()
        print(f"Character boundary: char1 ends at col {char1_width-1}, char2 starts at col {char2_start_pos}")

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