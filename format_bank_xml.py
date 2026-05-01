#!/usr/bin/env python3
"""
Script to format bank*.xml files while preserving original XML formatting.
"""

import xml.etree.ElementTree as ET
import sys
import os
import re
from script import Table
from metrics import TextMetrics

WINDOW_WIDTH = 208
FOURTH_LINE_WIDTH = 200  # Fourth line is 8 pixels shorter


class Token:
    def __init__(self, type_, value, position=0):
        self.type = type_
        self.value = value
        self.position = position

    def __repr__(self):
        return f"Token({self.type}, {repr(self.value)})"


class DialogLexer:
    def __init__(self):
        self.character_pattern = re.compile(r"(\w+(?:\s+\w+)*):")
        self.guillemet_pattern = re.compile(r"«([^»]*)»")
        self.end_pattern = re.compile(r"\[end\]")
        self.close_window_pattern = re.compile(r"\[close_window\]")

    def tokenize(self, text):
        tokens = []
        position = 0

        # Clean up whitespace but preserve structure
        text = re.sub(r"\s+", " ", text.strip())

        i = 0
        while i < len(text):
            # Skip whitespace
            while i < len(text) and text[i].isspace():
                i += 1

            if i >= len(text):
                break

            # Check for [end] marker
            end_match = self.end_pattern.match(text, i)
            if end_match:
                tokens.append(Token("END", "[end]", i))
                i = end_match.end()
                continue

            # Check for [close_window] marker
            close_window_match = self.close_window_pattern.match(text, i)
            if close_window_match:
                tokens.append(Token("CLOSE_WINDOW", "[close_window]", i))
                i = close_window_match.end()
                continue

            # Check for guillemet speech
            guillemet_match = self.guillemet_pattern.match(text, i)
            if guillemet_match:
                tokens.append(Token("GUILLEMET_SPEECH", guillemet_match.group(0), i))
                i = guillemet_match.end()
                continue

            # Check for character name
            char_match = self.character_pattern.match(text, i)
            if char_match:
                character_name = char_match.group(1)
                tokens.append(Token("CHARACTER", character_name, i))
                i = char_match.end()

                # Skip the colon and any following whitespace
                while i < len(text) and (text[i] == ":" or text[i].isspace()):
                    i += 1
                continue

            # Extract sentence (everything up to sentence-ending punctuation + space + capital, character pattern, or end of text)
            sentence_start = i
            sentence = ""

            while i < len(text):
                # Check if we hit [end] or [close_window] at current position
                if text[i : i + 5] == "[end]" and sentence.strip():
                    # We found [end] and we already have some sentence content
                    break
                if text[i : i + 14] == "[close_window]" and sentence.strip():
                    # We found [close_window] and we already have some sentence content
                    break

                # Check if we hit a guillemet at current position
                if text[i] == "«" and sentence.strip():
                    # We found a guillemet and we already have some sentence content
                    break

                # Check if we hit a character pattern at current position
                char_match_here = self.character_pattern.match(text, i)
                if char_match_here and sentence.strip():
                    # We found a character pattern and we already have some sentence content
                    break

                char = text[i]
                sentence += char
                i += 1

                # Check if we hit sentence-ending punctuation
                if char in ".!?":
                    # Check for abbreviations like "M." (Monsieur)
                    if char == "." and sentence.endswith("M."):
                        # Don't break on "M." abbreviation
                        continue

                    # Look ahead to see if this ends the sentence
                    if i >= len(text):  # End of text
                        break
                    elif text[i : i + 5] == "[end]":  # Followed by [end] (special case)
                        break
                    elif (
                        text[i : i + 14] == "[close_window]"
                    ):  # Followed by [close_window] (special case)
                        break
                    elif i < len(text) and text[i] == "[":
                        # Check if this is followed by a control code (not [end])
                        # Continue consuming control codes as part of the sentence
                        # Find the closing bracket
                        bracket_end = text.find("]", i)
                        if bracket_end != -1:
                            control_code = text[i : bracket_end + 1]
                            if control_code not in ["[end]", "[close_window]"]:
                                # This is a control code, include it in the sentence but don't consume following spaces
                                sentence += text[i : bracket_end + 1]
                                i = bracket_end + 1
                                # Don't consume the space - let the main loop handle it
                                continue
                            else:
                                # This is [end] or [close_window], break here
                                break
                    elif i < len(text) and text[i].isspace():
                        # Check if next non-space character is uppercase or special pattern
                        j = i
                        while j < len(text) and text[j].isspace():
                            j += 1
                        if j < len(text):
                            if (
                                text[j].isupper()
                                or text[j : j + 1] == "«"
                                or self.character_pattern.match(text, j)
                                or text[j : j + 5] == "[end]"
                                or text[j : j + 14] == "[close_window]"
                            ):
                                break
                    else:
                        # Check if immediately followed by character pattern (no space)
                        if self.character_pattern.match(text, i):
                            break

            if sentence.strip():
                tokens.append(Token("SENTENCE", sentence.strip(), sentence_start))

        return tokens


class DialogParser:
    def __init__(self, text_metrics=None):
        # Initialize TextMetrics if not provided
        if text_metrics is None:
            try:
                table = Table("text/ff4fr.tbl")

                # Use new interleaved format with correct font order
                font_files = [
                    "assets/font.dat",  # Index 0: [normal] (fe 00)
                    "assets/wicked_font.dat",  # Index 1: [wicked] (fe 01)
                    "assets/book_font.dat",  # Index 2: [book/force_book] (fe 02)
                    "assets/bold_font.dat",  # Index 3: [bold] (fe 03)
                ]

                self.text_metrics = TextMetrics(table, font_files, char_height=16)
            except (FileNotFoundError, Exception):
                # Fallback to None if metrics can't be loaded (for testing)
                self.text_metrics = None
        else:
            self.text_metrics = text_metrics

        # Initialize font state tracking
        self.reset_font_context()

    def reset_font_context(self):
        """Reset font context to default state for processing a new pointer."""
        self.current_font_index = (
            0  # Track current font index (0=normal, 1=wicked, 2=book, 3=bold)
        )

    def parse(self, tokens):
        """Parse tokens and inject WINDOW_BREAK tokens for guillemet speech transitions."""
        # First pass: inject WINDOW_BREAK tokens for guillemet transitions
        enhanced_tokens = self._inject_window_breaks(tokens)

        # Second pass: process the enhanced tokens for dialog formatting
        return self._format_dialog(enhanced_tokens)

    @staticmethod
    def _is_control_only(text):
        """True if SENTENCE value contains only control codes (e.g. [delay][0x5])."""
        return not re.sub(r"\[[^\]]*\]", "", text).strip()

    def _inject_window_breaks(self, tokens):
        """Inject WINDOW_BREAK tokens where guillemet speeches should create new windows."""
        enhanced_tokens = []
        in_character_context = False

        for i, token in enumerate(tokens):
            enhanced_tokens.append(token)

            if token.type == "CHARACTER":
                in_character_context = True
            elif token.type in ("GUILLEMET_SPEECH", "END", "CLOSE_WINDOW"):
                in_character_context = False

            next_token = tokens[i + 1] if i + 1 < len(tokens) else None
            next_type = next_token.type if next_token else None

            # Skip break when next SENTENCE is only control codes (e.g. [delay]):
            # no visible text means no need for a fresh window.
            next_is_visible_sentence = (
                next_type == "SENTENCE" and not self._is_control_only(next_token.value)
            )

            if token.type == "GUILLEMET_SPEECH" and (
                next_type in ("CHARACTER", "GUILLEMET_SPEECH")
                or next_is_visible_sentence
            ):
                enhanced_tokens.append(Token("WINDOW_BREAK", "[window_break]"))
            elif (
                token.type == "SENTENCE"
                and in_character_context
                and next_type == "GUILLEMET_SPEECH"
            ):
                enhanced_tokens.append(Token("WINDOW_BREAK", "[window_break]"))

        return enhanced_tokens

    def _wrap(self, sentence):
        wrapped, self.current_font_index = self.text_metrics.word_warp(
            sentence, WINDOW_WIDTH, self.current_font_index
        )
        return wrapped

    def _accumulate(self, wrapped_sentence, accumulated, result):
        """Append wrapped sentence to accumulated; flush with [new] if overflow."""
        if not accumulated:
            accumulated.append(wrapped_sentence)
            return accumulated

        combined = "\n".join(accumulated + [wrapped_sentence])
        if self._fits_in_dialog_window(combined):
            accumulated.append(wrapped_sentence)
            return accumulated

        result.extend(self._flush_pre_wrapped_sentences(accumulated, add_new=True))
        return [wrapped_sentence]

    def _format_dialog(self, tokens):
        """Format dialog tokens into final output, handling WINDOW_BREAK tokens."""
        result = []
        current_character = None
        accumulated_sentences = []

        for i, token in enumerate(tokens):
            if token.type == "WINDOW_BREAK":
                if accumulated_sentences:
                    result.extend(
                        self._flush_pre_wrapped_sentences(
                            accumulated_sentences, add_new=True
                        )
                    )
                    accumulated_sentences = []
                current_character = None

            elif token.type == "CHARACTER":
                if accumulated_sentences:
                    add_new = current_character is not None
                    result.extend(
                        self._flush_pre_wrapped_sentences(
                            accumulated_sentences, add_new=add_new
                        )
                    )
                    accumulated_sentences = []
                current_character = "[bold]" + token.value + "[normal]"

            elif token.type == "SENTENCE":
                # Control-only sentences ([delay][0x5] etc.) carry no visible text;
                # glue them to the previous output instead of starting a new window.
                if (
                    self._is_control_only(token.value)
                    and not accumulated_sentences
                    and result
                ):
                    result[-1] += token.value
                else:
                    if current_character and not accumulated_sentences:
                        sentence = f"{current_character}: {token.value}"
                    else:
                        sentence = token.value
                    wrapped = self._wrap(sentence)
                    accumulated_sentences = self._accumulate(
                        wrapped, accumulated_sentences, result
                    )

            elif token.type == "GUILLEMET_SPEECH":
                if accumulated_sentences:
                    result.extend(
                        self._flush_pre_wrapped_sentences(accumulated_sentences)
                    )
                    accumulated_sentences = []

                wrapped_guillemet = self._wrap(token.value)
                next_is_window_break = (
                    i + 1 < len(tokens) and tokens[i + 1].type == "WINDOW_BREAK"
                )
                result.append(
                    wrapped_guillemet + "[new]"
                    if next_is_window_break
                    else wrapped_guillemet
                )
                current_character = None

            elif token.type in ("END", "CLOSE_WINDOW"):
                marker = "[end]" if token.type == "END" else "[close_window]"
                if accumulated_sentences:
                    accumulated_sentences[-1] += marker
                    result.extend(
                        self._flush_pre_wrapped_sentences(accumulated_sentences)
                    )
                    accumulated_sentences = []
                elif result:
                    result[-1] += marker
                else:
                    result.append(marker)
                current_character = None

        if accumulated_sentences:
            result.extend(self._flush_pre_wrapped_sentences(accumulated_sentences))

        return result

    def _measure_lines_wrapped(self, wrapped_text):
        """Measure how many lines the already-wrapped text takes by counting newlines."""
        if not wrapped_text:
            return 0
        return wrapped_text.count("\n") + 1

    def _fits_in_dialog_window(self, wrapped_text):
        """Check if the wrapped text fits in a dialog window considering the fourth line is 8 pixels shorter."""
        if not wrapped_text:
            return True

        lines = wrapped_text.split("\n")
        num_lines = len(lines)

        # More than 4 lines never fits
        if num_lines > 4:
            return False

        # If we have exactly 4 lines, check if the fourth line fits in the reduced width
        if num_lines == 4:
            fourth_line = lines[3]
            # Measure the fourth line width using current font context
            fourth_line_width = self.text_metrics.measure_string(fourth_line)
            if fourth_line_width > FOURTH_LINE_WIDTH:
                return False

        # 3 or fewer lines, or 4 lines where the fourth line fits
        return True

    def _flush_pre_wrapped_sentences(self, wrapped_sentences, add_new=False):
        """Flush pre-wrapped sentences without re-wrapping them."""
        if not wrapped_sentences:
            return []
        text = "\n".join(wrapped_sentences)
        if add_new:
            text += "[new]"
        return [text]


def process_dialogue(text):
    """Process dialogue text to add [new] tags when character changes and remove line breaks."""
    if not text:
        return text

    # Strip existing [new] tokens to ensure idempotency, preserving sentence boundaries
    # Replace [new]\n with just \n to preserve line breaks
    clean_text = text.replace("[new]\n", "\n")
    clean_text = clean_text.replace("[bold]", "")
    clean_text = clean_text.replace("[normal]", "")
    clean_text = clean_text.replace("[book]", "")
    clean_text = clean_text.replace("[wicked]", "")

    # Replace standalone [new] (at end of lines) with nothing, but preserve the line structure
    clean_text = re.sub(r"\[new\](?=\n)", "", clean_text)
    # Replace any remaining [new] tags
    clean_text = clean_text.replace("[new]", "")

    # Clean up multiple consecutive newlines that may result from stripping [new] tags
    clean_text = re.sub(r"\n\s*\n", "\n", clean_text)

    # Use lexer/parser approach
    lexer = DialogLexer()
    parser = DialogParser()

    tokens = lexer.tokenize(clean_text)
    result = parser.parse(tokens)

    return "\n".join(result)


def format_bank_xml(file_path):
    """Format bank*.xml file content while preserving XML structure."""
    try:
        # Parse the XML
        tree = ET.parse(file_path)
        root = tree.getroot()

        modified = False

        # Check if pointer IDs need to be converted to zero-based indexing
        pointers = root.findall(".//{http://snes.ninja/ScriptNS}pointer")
        if pointers:
            # Find the minimum pointer ID
            pointer_ids = []
            for pointer in pointers:
                try:
                    pointer_id = int(pointer.get("id"))
                    pointer_ids.append(pointer_id)
                except (ValueError, TypeError):
                    continue

            if pointer_ids:
                min_id = min(pointer_ids)
                if min_id == 1:
                    # Convert to zero-based indexing
                    print("Converting pointer IDs to zero-based indexing (subtracting 1)")
                    for pointer in pointers:
                        try:
                            current_id = int(pointer.get("id"))
                            new_id = current_id - 1
                            pointer.set("id", str(new_id))
                            modified = True
                        except (ValueError, TypeError):
                            continue

        # Process the content without changing XML formatting
        for pointer in pointers:
            pointer_id = pointer.get("id")
            text_content = pointer.text or ""

            # Process dialogue to add [new] tags when character changes
            new_content = process_dialogue(text_content)

            if new_content != text_content:
                pointer.text = new_content
                modified = True
                print(f"Modified pointer {pointer_id}")

        # Write back to file if modifications were made
        if modified:
            # Register namespace to ensure proper prefixes
            ET.register_namespace("sn", "http://snes.ninja/ScriptNS")
            tree.write(file_path, encoding="utf-8", xml_declaration=True)
            print(f"Updated: {file_path}")
        else:
            print(f"No changes needed: {file_path}")

        return True

    except ET.ParseError as e:
        print(f"Error parsing {file_path}: {e}")
        return False
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return False


def main():
    """Main function to process bank*.xml files."""
    if len(sys.argv) > 1:
        files_to_process = sys.argv[1:]
    else:
        print("You need to pass a file path to the file as cmdline arg.")
        exit(128)
    # else:
    #     files_to_process = glob.glob('text/**/bank*.xml', recursive=True)

    if not files_to_process:
        print("No bank*.xml files found.")
        return

    success_count = 0
    total_count = len(files_to_process)

    for file_path in files_to_process:
        if os.path.exists(file_path):
            if format_bank_xml(file_path):
                success_count += 1
        else:
            print(f"File not found: {file_path}")

    print(f"\nProcessed {success_count}/{total_count} files successfully.")


if __name__ == "__main__":
    main()
