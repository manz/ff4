"""
A script pointer side by side in Japanese, the English draft and French: what a translation review reads.

    uv run python -m utils.compare_pointers battle_messages.xml 20 43 100-110
    uv run python -m utils.compare_pointers bank1-1.xml 18 --sugoi

Japanese comes from `text/jp` (the reference dump), the others from `text/en` and `text/fr`, read by
`utils.script_xml` (the Japanese bank2's areas are its pointers; the English bank2 has fewer pointers than the others,
its ids don't line up). Each pointer is checked for what can be checked exactly: a character the
Japanese names by its name code ($04 n) and the French doesn't. `--sugoi` adds a fresh English reading of the
Japanese by Sugoi-14B-Ultra (Ollama), cached in `local/sugoi/`: a second opinion on kana-only lines, not a reference
(it misreads terse ones). Read-only: edits go into the XML by hand.

Back from the attic (_attic/ff4/compare_pointers.py: bank1-1 only, one id, an ElementTree writer).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import urllib.request
from collections import Counter
from collections.abc import Iterable
from pathlib import Path

from script import Table

from utils.script_xml import pointer_texts

LANGUAGES = ("jp", "en", "fr")
SUGOI = "hf.co/sugoitoolkit/Sugoi-14B-Ultra-GGUF"
OLLAMA = "http://localhost:11434/api/chat"
NAMES = ("Cecil", "Caïn", "Rydia", "Tellah", "Edward", "Rosa", "Yang", "Palom", "Porom", "Cid", "Edge", "FuSoYa",
         "Golbez", "Anna")  # name codes $04 00 to $04 0D


def ids(specs: Iterable[str]) -> list[str]:
    """"20", "100-110" → ids, in order."""
    out: list[str] = []
    for spec in specs:
        first, _, last = spec.partition("-")
        out += [str(i) for i in range(int(first), int(last or first) + 1)]
    return out


def name_codes(data: bytes) -> Counter:
    return Counter(data[i + 1] for i in range(len(data) - 1) if data[i] == 0x04 and data[i + 1] < len(NAMES))


def lost_names(japanese: str, french: str, jp_table: Table, fr_table: Table) -> list[str]:
    """The characters the Japanese names by code and the French doesn't (written out, or dropped)."""
    try:
        lost = name_codes(jp_table.to_bytes(japanese.replace("\n", ""))) - name_codes(fr_table.to_bytes(french))
    except (KeyError, ValueError):
        return []
    return [NAMES[code] for code in sorted(lost)]


def normalise(japanese: str) -> str:
    """The dump's Japanese as plain text for a model: tags out, 。 and … back, 『 as Cecil speaking."""
    text = re.sub(r"\[[^\]]*\]", "", japanese).replace("゜", "。").replace("‥", "…").replace("『", "セシル「")
    return re.sub(r"\n\s*\n+", "\n", text).strip()


def sugoi(japanese: str, cache: Path) -> str:
    """Sugoi's English for `japanese`, cached by text."""
    cache.mkdir(parents=True, exist_ok=True)
    key = cache / f"{hashlib.sha1(japanese.encode()).hexdigest()[:16]}.json"
    if key.exists():
        return json.loads(key.read_text(encoding="utf-8"))["en"]
    body = {"model": SUGOI, "stream": False, "options": {"temperature": 0}, "messages": [
        {"role": "system", "content": "You are a professional localizer whose primary goal is to translate Japanese to English."},
        {"role": "user", "content": normalise(japanese)}]}
    request = urllib.request.Request(OLLAMA, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        english = json.loads(response.read())["message"]["content"].strip()
    key.write_text(json.dumps({"jp": japanese, "en": english}, ensure_ascii=False), encoding="utf-8")
    return english


def compare(name: str, pointer: str, texts: dict[str, dict[str, str]], lost: list[str], reading: str | None) -> str:
    """The pointer in each language of `texts` (Japanese, English draft, French; one left out is skipped)."""
    out = [f"POINTER {name} #{pointer}"]
    for lang, label in (("jp", "JAPANESE"), ("en", "ENGLISH (draft)"), ("fr", "FRENCH")):
        if lang in texts:
            out += ["", f"{label}:", texts[lang].get(pointer, "(none)").strip() or "(empty)"]
    if reading is not None:
        out += ["", "SUGOI (second opinion):", reading]
    if lost:
        out += ["", "CHECK: name codes the French loses: " + ", ".join(lost)]
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", help="a script file, e.g. bank1-1.xml or battle_messages.xml")
    parser.add_argument("ids", nargs="+", help="pointer ids or ranges (100-110)")
    parser.add_argument("--text", type=Path, default=Path("text"))
    parser.add_argument("--no-english", action="store_true", help="leave the English draft out: Japanese and French only")
    parser.add_argument("--sugoi", action="store_true", help="add Sugoi-14B-Ultra's English (Ollama)")
    parser.add_argument("--cache", type=Path, default=Path("local/sugoi"))
    args = parser.parse_args()
    languages = [lang for lang in LANGUAGES if not (args.no_english and lang == "en")]
    texts = {lang: pointer_texts(args.text / lang / args.file) for lang in languages}
    jp_table = Table(str(args.text / "ff4_jap.tbl"))
    fr_table = Table(str(args.text / "ff4fr.tbl"))
    blocks = []
    for pointer in ids(args.ids):
        if pointer not in texts["fr"] and pointer not in texts["jp"]:
            continue
        japanese, french = texts["jp"].get(pointer, ""), texts["fr"].get(pointer, "")
        reading = sugoi(japanese, args.cache) if args.sugoi and japanese.strip() else None
        blocks.append(compare(args.file, pointer, texts, lost_names(japanese, french, jp_table, fr_table), reading))
    print(f"\n\n{'=' * 60}\n\n".join(blocks) or "nothing")


if __name__ == "__main__":
    main()
