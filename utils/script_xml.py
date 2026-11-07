"""
The script XML (snes.ninja ScriptNS) read as text, pointer by pointer: what the reviews and tests compare.

Two layouts: `<sn:script>` of `<sn:pointer id>` (every French and English file), and the Japanese dump's bank2, an
`<sn:areas>` of `<sn:area id>` holding `<sn:string index>` messages: an area is one pointer of the French bank2 (its
messages, each ending in [end], in order).
"""

from __future__ import annotations

import argparse
import re
from collections.abc import Mapping, Sequence
from pathlib import Path
from xml.etree import ElementTree
from xml.sax.saxutils import escape

END = "[end]"


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def pointer_texts(path: Path) -> dict[str, str]:
    """A script file's text by pointer id (an area's messages joined); empty if the file doesn't exist."""
    if not path.exists():
        return {}
    root = ElementTree.parse(path).getroot()
    areas = [element for element in root if _local(element.tag) == "area"]
    if areas:
        return {area.get("id", ""): "".join(string.text or "" for string in area) for area in areas}
    return {element.get("id", ""): element.text or "" for element in root if _local(element.tag) == "pointer"}


def split_messages(text: str) -> list[str]:
    """A pointer's messages: cut after each [end] (the newline that follows it is layout, not text). A tail with no
    [end] (bytes past the last message) stays a message of its own."""
    return [m for m in re.split(r"(?<=\[end\])\n?", text) if m]


def write_areas(path: Path, areas: Mapping[str, Sequence[str]]) -> None:
    """Areas of messages in the Japanese dump's layout: `<sn:area id>` of `<sn:string index>`."""
    out = ['<?xml version="1.0" encoding="utf-8"?>\n<sn:areas xmlns:sn="http://snes.ninja/ScriptNS">\n']
    for area, messages in areas.items():
        out.append(f'<sn:area id="{area}">\n')
        out.extend(f'<sn:string index="{i}">{escape(m)}</sn:string>\n' for i, m in enumerate(messages))
        out.append("</sn:area>\n\n")
    out.append("</sn:areas>\n")
    path.write_text("".join(out), encoding="utf-8")


def split_file(path: Path) -> None:
    """A `<sn:script>` of pointers rewritten as areas, one string per message."""
    root = ElementTree.parse(path).getroot()
    write_areas(path, {e.get("id", ""): split_messages(e.text or "") for e in root if _local(e.tag) == "pointer"})


def main() -> None:
    parser = argparse.ArgumentParser(description="Rewrite pointer scripts as areas of messages (bank2's layout).")
    parser.add_argument("paths", type=Path, nargs="+")
    for path in parser.parse_args().paths:
        split_file(path)


if __name__ == "__main__":
    main()
