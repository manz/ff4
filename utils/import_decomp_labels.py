#!/usr/bin/env python3
"""Import vanilla routine names from the ff4decomp disassembly notes into
the kintsuki project overlay.

`ff4decomp/notes/ff4j-sfc.asm` is a full disassembly of the JP ROM where
every routine is introduced by a `; [ name ]` header followed by lines of
the form::

    01/818A: 48           PHA
    0D/FCCB: 00 08 00 00

The header's first address becomes an overlay label. Data blocks (byte
lines with no mnemonic) are typed `data`, everything else `code`.

Our own symbols are NOT imported: a816 already emits them into
`build/ff4.ips.adbg`, which kintsuki loads alongside the project, so
duplicating them in the overlay only creates entries that rot the moment
an address moves. Addresses already present in the .adbg, and overlay
labels that already carry a name, are left alone.

Every parsed line is checked against the ROM before its label is
written -- a wrong ROM, or an address the notes place elsewhere, shows
up as a byte mismatch instead of a plausible-looking wrong name. The
check reads the pristine ROM file rather than the emulator, which loads
`build/ff4.ips` on top: our own patch sites differ from vanilla by
design and would otherwise all be rejected.

The notes track a slightly different revision, so whole stretches sit at
a small constant offset from our ROM -- bank $00 runs +2 from $0089ED
onward. Rather than dropping those names, the import carries a running
per-bank delta: an entry is placed at the delta that already worked for
the previous entry in its bank, and a new delta is adopted only when the
block's opening bytes occur exactly once in a tight window around the
expected address. Anything ambiguous is skipped.

Usage:
    python utils/import_decomp_labels.py --dry-run
    python utils/import_decomp_labels.py
"""
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def _find_decomp_notes() -> Path:
    """Locate `ff4j-sfc.asm` in a checkout near this one.

    The disassembly lives in its own repo, cloned beside this one or
    beside its parent depending on how the working copies are laid out.
    Search both rather than hard-coding one nesting depth; `--asm`
    overrides when it sits somewhere else entirely.
    """
    tail = Path("ff4decomp") / "notes" / "ff4j-sfc.asm"
    roots = [REPO.parent, REPO.parent.parent, REPO.parent / "ff4", REPO.parent.parent / "ff4"]
    for root in roots:
        candidate = root / tail
        if candidate.is_file():
            return candidate
    return roots[0] / tail


DEFAULT_ASM = _find_decomp_notes()
DEFAULT_PROJECT = REPO / "ff4.kintsuki"
DEFAULT_ROM = REPO / "build" / "ff4.sfc"
DEFAULT_ADBG = REPO / "build" / "ff4.ips.adbg"

HEADER_RE = re.compile(r"^;\s*\[\s*(.*?)\s*\]\s*$")
LINE_RE = re.compile(
    r"^(?P<bank>[0-9A-F]{2})/(?P<addr>[0-9A-F]{4}):"
    r"(?P<rest>(?:\s+[0-9A-F]{2,4})+)"
    r"(?P<tail>\s+[A-Z].*)?$"
)


@dataclass(frozen=True)
class Entry:
    """One `; [ name ]` block: where it starts and what it holds."""

    addr: int          # 24-bit bus address
    name: str          # normalised identifier
    title: str         # the header text, verbatim
    is_code: bool
    first_bytes: bytes  # for the ROM cross-check


def normalise(title: str) -> str:
    """`special effect $34: telescope` -> `special_effect_34_telescope`."""
    name = re.sub(r"[^0-9a-z]+", "_", title.lower()).strip("_")
    if name and name[0].isdigit():
        name = f"_{name}"
    return name


def parse(asm_path: Path) -> list[Entry]:
    """Walk the disassembly, one Entry per named block."""
    entries: list[Entry] = []
    pending: str | None = None

    for raw in asm_path.read_text(encoding="utf-8", errors="replace").splitlines():
        header = HEADER_RE.match(raw)
        if header:
            # Unnamed blocks (`; [  ]`) carry no information worth keeping.
            pending = header.group(1) or None
            continue
        if pending is None:
            continue
        m = LINE_RE.match(raw)
        if not m:
            continue

        # Word-sized operands appear in pointer tables; only whole bytes
        # can be checked against the ROM, so stop at the first non-byte.
        chunks = m.group("rest").split()
        data = bytearray()
        for chunk in chunks:
            if len(chunk) != 2:
                break
            data.append(int(chunk, 16))

        name = normalise(pending)
        if name and data:
            entries.append(Entry(
                addr=(int(m.group("bank"), 16) << 16) | int(m.group("addr"), 16),
                name=name,
                title=pending,
                is_code=bool(m.group("tail")),
                first_bytes=bytes(data),
            ))
        pending = None

    return entries


def deduplicate(entries: list[Entry]) -> list[Entry]:
    """Keep one entry per address; suffix names reused across blocks."""
    by_addr: dict[int, Entry] = {}
    for entry in entries:
        by_addr.setdefault(entry.addr, entry)

    seen: dict[str, int] = {}
    out: list[Entry] = []
    for addr in sorted(by_addr):
        entry = by_addr[addr]
        count = seen.get(entry.name, 0)
        seen[entry.name] = count + 1
        if count:
            entry = Entry(entry.addr, f"{entry.name}_{addr:06x}",
                          entry.title, entry.is_code, entry.first_bytes)
        out.append(entry)
    return out


SEARCH_RADIUS = 64  # bytes either side when re-anchoring a shifted block


def locate(entry: Entry, rom: bytes, rom_off: int, delta: int) -> int | None:
    """Byte offset the block actually sits at, or None if unresolvable.

    Tries the running `delta` first, then no shift, then a unique
    occurrence within SEARCH_RADIUS. A one-byte opener is far too common
    to anchor on, so it is only ever accepted at a delta already known
    to work.
    """
    want = entry.first_bytes
    for candidate in (delta, 0):
        if rom[rom_off + candidate:rom_off + candidate + len(want)] == want:
            return candidate
    if len(want) < 2:
        return None
    lo = max(0, rom_off - SEARCH_RADIUS)
    window = rom[lo:rom_off + SEARCH_RADIUS]
    hits = [lo + i - rom_off for i in range(len(window))
            if window[i:i + len(want)] == want]
    return hits[0] if len(hits) == 1 else None


def adbg_addresses(adbg_path: Path) -> set[int]:
    """Addresses our own build already names. Empty when there is no
    debug info yet -- the import still runs, just without that filter."""
    if not adbg_path.exists():
        return set()
    from a816 import debug_info
    return {s.address & 0xFFFFFF for s in debug_info.read(adbg_path).symbols}


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--asm", type=Path, default=DEFAULT_ASM)
    ap.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    ap.add_argument("--rom", type=Path, default=DEFAULT_ROM)
    ap.add_argument("--adbg", type=Path, default=DEFAULT_ADBG)
    ap.add_argument("--dry-run", action="store_true",
                    help="parse + verify against the ROM, write nothing")
    ap.add_argument("--overwrite", action="store_true",
                    help="replace overlay labels that already have a name")
    args = ap.parse_args()

    if not args.asm.exists():
        print(f"disassembly notes not found: {args.asm}")
        return 1

    entries = deduplicate(parse(args.asm))
    print(f"parsed {len(entries)} named blocks from {args.asm.name}")

    from kintsuki import Emu

    emu = Emu(load_srm_sidecar=False)
    emu.load_rom(str(args.rom))
    emu.project_open(str(args.project))

    pristine = args.rom.read_bytes()
    ours = adbg_addresses(args.adbg)
    existing = {l["addr"] & 0xFFFFFF for l in emu.project_labels() if l["name"]}

    written = unresolved = skipped_ours = skipped_named = unmapped = 0
    shifts: dict[int, int] = {}   # bank -> running delta
    shifted = 0
    for entry in sorted(entries, key=lambda e: e.addr):
        rom_off = emu.project_bus_to_rom(entry.addr)
        if rom_off is None:
            unmapped += 1
            continue
        bank = entry.addr >> 16
        delta = locate(entry, pristine, rom_off, shifts.get(bank, 0))
        if delta is None:
            unresolved += 1
            continue
        if delta != shifts.get(bank, 0):
            print(f"  bank ${bank:02X}: notes shift {delta:+d} from "
                  f"${entry.addr + delta:06X} ({entry.name})")
            shifts[bank] = delta
        if delta:
            shifted += 1

        addr = entry.addr + delta
        if addr in ours:
            skipped_ours += 1
            continue
        if addr in existing and not args.overwrite:
            skipped_named += 1
            continue
        if not args.dry_run:
            emu.project_label_set(
                addr, entry.name,
                type="code" if entry.is_code else "data",
                comment=entry.title)
        written += 1

    print(f"  {written} label(s) {'to write' if args.dry_run else 'written'}"
          f" ({shifted} re-anchored past a revision shift)")
    print(f"  {unresolved} skipped: opening bytes not found near the noted address")
    print(f"  {skipped_ours} skipped: already named by build/ff4.ips.adbg")
    print(f"  {skipped_named} skipped: overlay label already named")
    print(f"  {unmapped} skipped: address outside the cart mapping")

    if not args.dry_run:
        emu.project_save()
        named = len([l for l in emu.project_labels() if l["name"]])
        print(f"saved; overlay now has {named} named labels")
    emu.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
