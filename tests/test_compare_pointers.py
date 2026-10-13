"""utils/compare_pointers.py: reading the script files and the exact checks (Sugoi never runs here)."""
from __future__ import annotations

from pathlib import Path

from script import Table

from utils.compare_pointers import compare, ids, lost_names, normalise
from utils.script_xml import pointer_texts


def test_ids_take_ranges() -> None:
    assert ids(["20", "100-102"]) == ["20", "100", "101", "102"]


NS = 'xmlns:sn="http://snes.ninja/ScriptNS"'


def test_pointers_are_read_by_id(tmp_path: Path) -> None:
    (tmp_path / "a.xml").write_text(f'<sn:script {NS}><sn:pointer id="3">x &amp; y</sn:pointer></sn:script>', encoding="utf-8")
    assert pointer_texts(tmp_path / "a.xml") == {"3": "x & y"}


def test_an_area_is_one_pointer(tmp_path: Path) -> None:
    (tmp_path / "a.xml").write_text(
        f'<sn:areas {NS}><sn:area id="0"><sn:string index="0">a[end]</sn:string>'
        '<sn:string index="1">b[end]</sn:string></sn:area><sn:area id="1"><sn:string index="0">c[end]</sn:string>'
        "</sn:area></sn:areas>", encoding="utf-8")
    assert pointer_texts(tmp_path / "a.xml") == {"0": "a[end]b[end]", "1": "c[end]"}


def test_a_name_written_out_is_lost() -> None:
    jp, fr = Table("text/ff4_jap.tbl"), Table("text/ff4_menus.tbl")  # the menu table spells names out
    assert lost_names("Cain", "Caïn", jp, fr) == ["Caïn"]


def test_a_name_kept_as_code_is_not_lost() -> None:
    assert lost_names("Cain", "Caïn", Table("text/ff4_jap.tbl"), Table("text/ff4fr.tbl")) == []


def test_normalise_gives_plain_japanese() -> None:
    assert normalise("『ありがとう゜[end]") == "セシル「ありがとう。"


def test_the_comparison_shows_all_three() -> None:
    text = compare("f.xml", "1", {"jp": {"1": "JP"}, "en": {"1": "EN"}, "fr": {"1": "FR"}}, ["Caïn"], None)
    assert all(part in text for part in ("JP", "EN", "FR", "name codes the French loses: Caïn"))
