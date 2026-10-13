"""
The script XML (snes.ninja ScriptNS) read as text, pointer by pointer: what the reviews and tests compare.

Two layouts: `<sn:script>` of `<sn:pointer id>` (every French and English file), and the Japanese dump's bank2, an
`<sn:areas>` of `<sn:area id>` holding `<sn:string index>` messages: an area is one pointer of the French bank2 (its
messages, each ending in [end], in order).
"""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree


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
