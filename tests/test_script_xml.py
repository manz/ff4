"""bank2's area layout: messages split after [end], written as the Japanese dump is, and read back joined."""

from __future__ import annotations

from pathlib import Path

from utils.script_xml import pointer_texts, split_file, split_messages, write_areas


def test_split_cuts_after_each_end() -> None:
    assert split_messages("Un![end]\nDeux![end]") == ["Un![end]", "Deux![end]"]


def test_split_keeps_a_message_with_no_newline_after_end() -> None:
    assert split_messages("Un![end]«Deux»[end]") == ["Un![end]", "«Deux»[end]"]


def test_split_keeps_a_tail_with_no_end() -> None:
    assert split_messages("Un![end]\nT") == ["Un![end]", "T"]


def test_split_of_an_empty_pointer_is_empty() -> None:
    assert split_messages("") == []


def test_areas_read_back_as_their_messages_joined(tmp_path: Path) -> None:
    path = tmp_path / "bank2.xml"
    write_areas(path, {"0": ["Un & deux![end]", "Trois![end]"], "1": ["Quatre![end]"]})
    assert pointer_texts(path) == {"0": "Un & deux![end]Trois![end]", "1": "Quatre![end]"}


def test_split_file_rewrites_pointers_as_areas(tmp_path: Path) -> None:
    path = tmp_path / "bank2.xml"
    path.write_text('<?xml version="1.0"?>\n<sn:script xmlns:sn="http://snes.ninja/ScriptNS">'
                    '<sn:pointer id="0">Un![end]\nDeux![end]</sn:pointer></sn:script>', encoding="utf-8")
    split_file(path)
    assert pointer_texts(path) == {"0": "Un![end]Deux![end]"}
