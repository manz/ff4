"""
The release readme with its version and date filled in: `@VERSION@` and `@DATE@` ("Octobre 2026", the month of the
last commit, so a rebuild gives the same file). The month is French unless the language is given.

    uv run python -m utils.lisezmoi release/LISEZMOI.txt v1.0.0b0 > dist/LISEZMOI.txt
    uv run python -m utils.lisezmoi release/README.txt v1.0.0b0 en > dist/README.txt
"""

from __future__ import annotations

import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

MONTHS = {
    "fr": ("Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre",
           "Novembre", "Décembre"),
    "en": ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
           "November", "December"),
}


def month(when: datetime, lang: str = "fr") -> str:
    return f"{MONTHS[lang][when.month - 1]} {when.year}"


def fill(template: str, version: str, when: datetime, lang: str = "fr") -> str:
    return template.replace("@VERSION@", version).replace("@DATE@", month(when, lang))


def _last_commit() -> datetime:
    stamp = subprocess.run(["git", "log", "-1", "--format=%ct"], capture_output=True, text=True, check=True).stdout
    return datetime.fromtimestamp(int(stamp), UTC)


def main() -> None:
    template, version = Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[2]
    lang = sys.argv[3] if len(sys.argv) > 3 else "fr"
    sys.stdout.write(fill(template, version, _last_commit(), lang))


if __name__ == "__main__":
    main()
