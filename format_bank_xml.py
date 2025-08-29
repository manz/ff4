#!/usr/bin/env python3
"""
Script to format bank*.xml files while preserving original XML formatting.
"""

import xml.etree.ElementTree as ET
import sys
import os
import glob
import re
from pathlib import Path
from script import Table
from metrics import TextMetrics

WINDOW_WIDTH = 208


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
                # Check if we hit [end] at current position (only [end], not other control codes)
                if text[i: i + 5] == "[end]" and sentence.strip():
                    # We found [end] and we already have some sentence content
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
                    elif text[i: i + 5] == "[end]":  # Followed by [end] (special case)
                        break
                    elif i < len(text) and text[i] == "[":
                        # Check if this is followed by a control code (not [end])
                        # Continue consuming control codes as part of the sentence
                        # Find the closing bracket
                        bracket_end = text.find("]", i)
                        if bracket_end != -1:
                            control_code = text[i: bracket_end + 1]
                            if control_code != "[end]":
                                # This is a control code, include it in the sentence but don't consume following spaces
                                sentence += text[i: bracket_end + 1]
                                i = bracket_end + 1
                                # Don't consume the space - let the main loop handle it
                                continue
                            else:
                                # This is [end], break here
                                break
                    elif i < len(text) and text[i].isspace():
                        # Check if next non-space character is uppercase or special pattern
                        j = i
                        while j < len(text) and text[j].isspace():
                            j += 1
                        if j < len(text):
                            if (
                                    text[j].isupper()
                                    or text[j: j + 1] == "«"
                                    or self.character_pattern.match(text, j)
                                    or text[j: j + 5] == "[end]"
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
                normal_length_table = Path("assets/font_length_table.dat").read_bytes()
                bold_length_table = Path("assets/bold_font_length_table.dat").read_bytes()
                book_length_table = Path("assets/book_font_length_table.dat").read_bytes()
                wicked_length_table = Path("assets/wicked_font_length_table.dat").read_bytes()
                table = Table("text/ff4fr.tbl")
                self.text_metrics = TextMetrics(table, [normal_length_table, wicked_length_table, bold_length_table,
                                                        book_length_table])
            except (FileNotFoundError, Exception):
                # Fallback to None if metrics can't be loaded (for testing)
                self.text_metrics = None
        else:
            self.text_metrics = text_metrics

    def parse(self, tokens):
        """Parse tokens into dialog segments with intelligent grouping."""
        result = []
        current_character = None
        accumulated_sentences = []
        accumulated_text = ""
        accumulated_lines = 0

        i = 0
        while i < len(tokens):
            token = tokens[i]

            if token.type == "CHARACTER":
                # Character change - process any accumulated sentences first
                if accumulated_sentences:
                    # Always add [new] when character changes (except for the very first character)
                    add_new = current_character is not None
                    result.extend(
                        self._flush_pre_wrapped_sentences(
                            accumulated_sentences, add_new=add_new
                        )
                    )
                    accumulated_sentences = []
                    accumulated_text = ""
                    accumulated_lines = 0

                current_character = "[bold]" + token.value + "[normal]"
                i += 1

            elif token.type == "SENTENCE":
                if current_character:
                    # Character speech sentence
                    is_first_sentence = not accumulated_sentences
                    sentence = (
                        f"{current_character}: {token.value}"
                        if is_first_sentence
                        else token.value
                    )

                    # Apply word wrapping to this sentence immediately
                    wrapped_sentence = self.text_metrics.word_warp(
                        sentence, WINDOW_WIDTH
                    )

                    # Check if adding this wrapped sentence would exceed 4-line limit
                    if accumulated_sentences:
                        # Calculate total lines for all accumulated sentences plus this new one
                        all_wrapped_sentences = accumulated_sentences + [
                            wrapped_sentence
                        ]
                        combined_wrapped_text = "\n".join(all_wrapped_sentences)
                        lines_needed = self._measure_lines_wrapped(
                            combined_wrapped_text
                        )

                        if lines_needed <= 4:
                            # Fits in current dialog box
                            accumulated_sentences.append(wrapped_sentence)
                            accumulated_text = combined_wrapped_text
                            accumulated_lines = lines_needed
                        else:
                            # Would exceed limit - flush accumulated with [new] at end, then start new
                            if accumulated_sentences:
                                result.extend(
                                    self._flush_pre_wrapped_sentences(
                                        accumulated_sentences, add_new=True
                                    )
                                )

                            # Start new accumulation with this wrapped sentence
                            accumulated_sentences = [wrapped_sentence]
                            accumulated_text = wrapped_sentence
                            accumulated_lines = self._measure_lines_wrapped(
                                wrapped_sentence
                            )
                    else:
                        # First sentence for this character
                        accumulated_sentences.append(wrapped_sentence)
                        accumulated_text = wrapped_sentence
                        accumulated_lines = self._measure_lines_wrapped(
                            wrapped_sentence
                        )
                else:
                    # Narrative sentence
                    sentence = token.value

                    # Apply word wrapping to narrative sentences too
                    wrapped_sentence = self.text_metrics.word_warp(
                        sentence, WINDOW_WIDTH
                    )

                    # Apply same intelligent grouping for narrative using wrapped sentences
                    if accumulated_sentences:
                        # Calculate total lines for all accumulated sentences plus this new one
                        all_wrapped_sentences = accumulated_sentences + [
                            wrapped_sentence
                        ]
                        combined_wrapped_text = "\n".join(all_wrapped_sentences)
                        lines_needed = self._measure_lines_wrapped(
                            combined_wrapped_text
                        )

                        if lines_needed <= 4:
                            accumulated_sentences.append(wrapped_sentence)
                            accumulated_text = combined_wrapped_text
                            accumulated_lines = lines_needed
                        else:
                            # Would exceed limit - flush accumulated with [new] at end, then start new
                            if accumulated_sentences:
                                result.extend(
                                    self._flush_pre_wrapped_sentences(
                                        accumulated_sentences, add_new=True
                                    )
                                )

                            # Start new accumulation with this wrapped sentence
                            accumulated_sentences = [wrapped_sentence]
                            accumulated_text = wrapped_sentence
                            accumulated_lines = self._measure_lines_wrapped(
                                wrapped_sentence
                            )
                    else:
                        # First narrative sentence
                        accumulated_sentences.append(wrapped_sentence)
                        accumulated_text = wrapped_sentence
                        accumulated_lines = self._measure_lines_wrapped(
                            wrapped_sentence
                        )

                i += 1

            elif token.type == "GUILLEMET_SPEECH":
                # Flush any accumulated sentences first
                if accumulated_sentences:
                    result.extend(
                        self._flush_pre_wrapped_sentences(
                            accumulated_sentences, add_new=True
                        )
                    )
                    accumulated_sentences = []
                    accumulated_text = ""
                    accumulated_lines = 0

                # Check if this guillemet is followed immediately by [end]
                is_followed_by_end = i + 1 < len(tokens) and tokens[i + 1].type == "END"

                # Add guillemet speech as separate dialog box
                if is_followed_by_end:
                    result.append(token.value)  # Don't add [new] if followed by [end]
                else:
                    result.append(token.value + "[new]")

                current_character = None  # Reset character context
                i += 1

            elif token.type == "END":
                # End marker - flush accumulated and add end marker, then reset state
                if accumulated_sentences:
                    # Add [end] to the last accumulated sentence
                    last_sentence = accumulated_sentences[-1]
                    accumulated_sentences[-1] = last_sentence + "[end]"
                    result.extend(
                        self._flush_pre_wrapped_sentences(accumulated_sentences)
                    )
                    accumulated_sentences = []  # Clear to prevent double processing
                elif result:
                    # No accumulated sentences, but we have previous results - append [end] to the last result
                    result[-1] = result[-1] + "[end]"
                else:
                    # No accumulated sentences and no previous results - this is a standalone [end]
                    result.append("[end]")

                # Reset all state after [end]
                current_character = None
                accumulated_sentences = []
                accumulated_text = ""
                accumulated_lines = 0
                i += 1

            else:
                i += 1

        # Flush any remaining accumulated sentences
        if accumulated_sentences:
            result.extend(self._flush_pre_wrapped_sentences(accumulated_sentences))

        return result

    def _measure_lines_wrapped(self, wrapped_text):
        """Measure how many lines the already-wrapped text takes by counting newlines."""
        if not wrapped_text:
            return 0
        return wrapped_text.count("\n") + 1

    def _flush_pre_wrapped_sentences(self, wrapped_sentences, add_new=False):
        """Flush pre-wrapped sentences without re-wrapping them."""
        if not wrapped_sentences:
            return []

        # Combine pre-wrapped sentences
        if len(wrapped_sentences) == 1:
            text = wrapped_sentences[0]
        else:
            # Join wrapped sentences with newlines
            text = "\n".join(wrapped_sentences)

        if add_new:
            text += "[new]"

        return [text]


def process_dialogue(text):
    """Process dialogue text to add [new] tags when character changes and remove line breaks."""
    if not text:
        return text

    # Strip existing [new] tokens to ensure idempotency, preserving sentence boundaries
    import re

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
                    print(
                        f"Converting pointer IDs to zero-based indexing (subtracting 1)"
                    )
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
